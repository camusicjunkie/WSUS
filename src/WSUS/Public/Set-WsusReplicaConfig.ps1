function Set-WsusReplicaConfig {
    <#
    .SYNOPSIS
        Configures a node as a Replica of an Upstream and sets its sync schedule.
    .DESCRIPTION
        The node copies computer groups, approvals and declines from the Upstream and downloads
        content from it, so only the Upstream talks to Microsoft. Accepts a node in either role
        (a fresh node is an Upstream by role).

        Refuses when -UpstreamFqdn is the node itself, and when the node is an Upstream with
        non-default state (custom computer groups, approval rules or approvals) unless -Force.
        Probes the upstream's wuident.cab over SSL before saving and fails when it does not
        answer; -Force skips the probe. The probe is skipped under -WhatIf.
    .PARAMETER UpstreamFqdn
        FQDN of the Upstream. Must be a SAN on its certificate.
    .PARAMETER UpstreamPort
        SSL port on the Upstream. Default 8531.
    .PARAMETER SyncsPerDay
        Automatic syncs per day (1-24). Default 2.
    .PARAMETER FirstSyncUtcHour
        Hour (UTC) of the first daily sync. Default 4, two hours after the Upstream's first sync.
    .PARAMETER SyncNow
        Start a sync from the Upstream once saved. Does not wait for it to finish.
    .PARAMETER Force
        Bypass the upstream probe and the non-default-state guard.
    .PARAMETER WsusServer
        Node to configure. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port on the node. Default 8531.
    .EXAMPLE
        Set-WsusReplicaConfig -UpstreamFqdn wsus01.contoso.local -SyncNow -WhatIf
        Shows what would change without saving.
    .OUTPUTS
        WSUS.ReplicaConfig
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.ReplicaConfig')]
    param (
        [Parameter(Mandatory)]
        [string] $UpstreamFqdn,

        [int] $UpstreamPort = 8531,

        [ValidateRange(1, 24)]
        [int] $SyncsPerDay = 2,

        [ValidateRange(0, 23)]
        [int] $FirstSyncUtcHour = 4,

        [switch] $SyncNow,

        [switch] $Force,

        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531
    )

    Assert-WsusPrerequisite -Module UpdateServices -Administrator
    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port

    $config = $wsus.GetConfiguration()

    if ($UpstreamFqdn -in @($WsusServer, $wsus.Name)) {
        throw "-UpstreamFqdn '$UpstreamFqdn' is the node itself. A node cannot be its own upstream."
    }

    if (-not $Force) {
        if (-not $config.IsReplicaServer) {
            $builtInGroups = 'All Computers', 'Unassigned Computers'
            $customGroups = @($wsus.GetComputerTargetGroups() | Where-Object { $_.Name -notin $builtInGroups })
            $customRules = @($wsus.GetInstallApprovalRules() | Where-Object { $_.Name -ne 'Default Automatic Approval Rule' })
            $approvals = @($wsus.GetUpdateApprovals((New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateApprovalScope)))
            if ($customGroups.Count -or $customRules.Count -or $approvals.Count) {
                throw ("$WsusServer is an Upstream with its own state ($($customGroups.Count) custom computer group(s), " +
                    "$($customRules.Count) approval rule(s), $($approvals.Count) approval(s)). Making it a replica discards that. Use -Force to continue.")
            }
        }

        if ($WhatIfPreference) {
            Write-Information -MessageData "What if: would probe https://${UpstreamFqdn}:$UpstreamPort/selfupdate/wuident.cab" -InformationAction Continue
        }
        elseif (-not (Test-WsusUpstreamReachable -Fqdn $UpstreamFqdn -Port $UpstreamPort)) {
            throw "Upstream '${UpstreamFqdn}:$UpstreamPort' did not answer https://${UpstreamFqdn}:$UpstreamPort/selfupdate/wuident.cab. Check the name, port and certificate, or use -Force to skip the check."
        }
    }

    $subscription = $wsus.GetSubscription()

    if ($PSCmdlet.ShouldProcess($WsusServer, "Make replica of ${UpstreamFqdn}:$UpstreamPort")) {
        $config.SyncFromMicrosoftUpdate = $false
        $config.UpstreamWsusServerName = $UpstreamFqdn
        $config.UpstreamWsusServerPortNumber = $UpstreamPort
        $config.UpstreamWsusServerUseSsl = ($UpstreamPort -eq 8531)
        $config.IsReplicaServer = $true
        $config.GetContentFromMU = $false
        $config.DownloadExpressPackages = $false
        $config.DownloadUpdateBinariesAsNeeded = $true
        $config.HostBinariesOnMicrosoftUpdate = $false
        $config.TargetingMode = 'Client'
        $config.UseProxy = $false
        $config.Save()
    }

    if ($PSCmdlet.ShouldProcess($WsusServer, 'Save sync schedule')) {
        $subscription.SynchronizeAutomatically = $true
        $subscription.SynchronizeAutomaticallyTimeOfDay = New-TimeSpan -Hours $FirstSyncUtcHour
        $subscription.NumberOfSynchronizationsPerDay = $SyncsPerDay
        $subscription.Save()
    }

    $syncStarted = $false
    if ($SyncNow -and $PSCmdlet.ShouldProcess($WsusServer, 'Start sync from upstream')) {
        $subscription.StartSynchronization()
        $syncStarted = $true
    }

    [PSCustomObject]@{
        PSTypeName  = 'WSUS.ReplicaConfig'
        Server      = $WsusServer
        Upstream    = '{0}:{1}' -f $UpstreamFqdn, $UpstreamPort
        Schedule    = '{0} syncs/day from {1:00}:00 UTC' -f $SyncsPerDay, $FirstSyncUtcHour
        SyncStarted = $syncStarted
        NextStep    = 'Get-WsusNodeStatus to check the sync; Register-WsusMaintenanceTask'
    }
}
