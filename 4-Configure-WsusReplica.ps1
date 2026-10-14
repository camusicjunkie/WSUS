<#
.SYNOPSIS
    Configures WSUS02 as a replica of WSUS01, or promotes it to autonomous if WSUS01 is lost.

.DESCRIPTION
    Replica (default): WSUS02 syncs from WSUS01 over SSL and copies its computer groups,
    approvals and declines. Products and classifications follow the upstream automatically.
    Content is downloaded from WSUS01, so only WSUS01 talks to Microsoft. Nothing is approved
    on WSUS02 while it is a replica.

    Promote (-Promote): turns WSUS02 into an autonomous server that syncs from Microsoft Update.
    Existing approvals, groups and declines stay in its database. Use this only when WSUS01 is
    gone for good, or will be rebuilt as the new replica. Then run 3-Configure-WsusUpstream.ps1
    against WSUS02 and make WSUS02 the primary on the NetScaler.

.EXAMPLE
    .\4-Configure-WsusReplica.ps1 -UpstreamFqdn wsus01.corp.local -SyncNow -WhatIf

.EXAMPLE
    .\4-Configure-WsusReplica.ps1 -Promote -Verbose
#>
#Requires -Version 5.1
#Requires -Modules UpdateServices
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Replica')]
param (
    # FQDN of the upstream node (WSUS01). Must be a SAN on WSUS01's certificate.
    [Parameter(Mandatory, ParameterSetName = 'Replica')]
    [string] $UpstreamFqdn,

    # SSL port on the upstream node.
    [Parameter(ParameterSetName = 'Replica')]
    [int] $UpstreamPort = 8531,

    # Automatic syncs per day.
    [Parameter(ParameterSetName = 'Replica')]
    [ValidateRange(1, 24)]
    [int] $SyncsPerDay = 2,

    # Hour of the first daily sync, in UTC. Two hours after the upstream's first sync.
    [Parameter(ParameterSetName = 'Replica')]
    [ValidateRange(0, 23)]
    [int] $FirstSyncUtcHour = 4,

    # Start a full sync from the upstream as soon as the configuration is saved.
    [Parameter(ParameterSetName = 'Replica')]
    [switch] $SyncNow,

    # Convert this replica to an autonomous server that syncs from Microsoft Update.
    [Parameter(Mandatory, ParameterSetName = 'Promote')]
    [switch] $Promote,

    # Node FQDN to connect to. Defaults to this node.
    [string] $WsusServer = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName,

    # WSUS API port on the node.
    [int] $Port = 8531
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    $wsus = Get-WsusServer -Name $WsusServer -PortNumber $Port -UseSsl
    $config = $wsus.GetConfiguration()
    $subscription = $wsus.GetSubscription()

    if ($Promote) {
        if (-not $config.IsReplicaServer) {
            Write-Warning -Message "$WsusServer is already autonomous. Nothing to promote."
            return
        }
        $config.IsReplicaServer = $false
        $config.SyncFromMicrosoftUpdate = $true
        if ($PSCmdlet.ShouldProcess($WsusServer, 'Promote replica to autonomous (sync from Microsoft Update)')) {
            $config.Save()
        }

        [PSCustomObject]@{
            Server   = $WsusServer
            Role     = 'Autonomous'
            NextStep = ('Run 3-Configure-WsusUpstream.ps1 here, register the decline task here, and make ' +
                        'this node the NetScaler primary. Rebuild the old WSUS01 as the new replica.')
        }
        return
    }

    $config.SyncFromMicrosoftUpdate = $false
    $config.UpstreamWsusServerName = $UpstreamFqdn
    $config.UpstreamWsusServerPortNumber = $UpstreamPort
    $config.UpstreamWsusServerUseSsl = ($UpstreamPort -eq 8531)
    $config.IsReplicaServer = $true
    $config.GetContentFromMU = $false                 # pull content from WSUS01, not Microsoft
    $config.DownloadExpressPackages = $false
    $config.DownloadUpdateBinariesAsNeeded = $true    # download content only once approved
    $config.HostBinariesOnMicrosoftUpdate = $false
    $config.TargetingMode = 'Client'
    $config.UseProxy = $false
    if ($PSCmdlet.ShouldProcess($WsusServer, "Make replica of ${UpstreamFqdn}:$UpstreamPort")) {
        $config.Save()
    }

    $subscription.SynchronizeAutomatically = $true
    $subscription.SynchronizeAutomaticallyTimeOfDay = New-TimeSpan -Hours $FirstSyncUtcHour
    $subscription.NumberOfSynchronizationsPerDay = $SyncsPerDay
    if ($PSCmdlet.ShouldProcess($WsusServer, 'Save sync schedule')) {
        $subscription.Save()
    }

    if ($SyncNow -and $PSCmdlet.ShouldProcess($WsusServer, 'Start full sync from upstream')) {
        $subscription.StartSynchronization()
    }

    [PSCustomObject]@{
        Server   = $WsusServer
        Role     = 'Replica'
        Upstream = '{0}:{1}' -f $UpstreamFqdn, $UpstreamPort
        Schedule = '{0} syncs/day from {1:00}:00 UTC' -f $SyncsPerDay, $FirstSyncUtcHour
        NextStep = 'Check the sync: (Get-WsusServer).GetSubscription().GetLastSynchronizationInfo()'
    }
}
