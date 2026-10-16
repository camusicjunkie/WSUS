function Get-WsusNodeStatus {
    <#
    .SYNOPSIS
        Reports plain facts about one or more WSUS nodes: role, last sync, content disk and run logs.
    .DESCRIPTION
        Read-only; works on an upstream and a replica. Role and last sync work remotely. Content disk
        and maintenance/decline log facts can only be read on this machine, so for any other
        -WsusServer those properties are $null.

        No verdict is returned (no 'Healthy' flag); filter the objects with Where-Object.
        A node that can't be reached writes a non-terminating error naming the node and port, and
        the remaining nodes are still processed.
    .EXAMPLE
        Get-WsusNodeStatus
        Status of the local node.
    .EXAMPLE
        'wsus01.contoso.local', 'wsus02.contoso.local' | Get-WsusNodeStatus | Where-Object ContentFreePercent -lt 15
        Checks both nodes and lists any with little free content disk (disk facts are local-only).
    .OUTPUTS
        WSUS.NodeStatus
    #>
    [CmdletBinding()]
    [OutputType('WSUS.NodeStatus')]
    param (
        # Node names. Accepts pipeline input and a WsusServer or Server property. Defaults to this machine's FQDN.
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Server')]
        [string[]] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices

        $localNames = @($env:COMPUTERNAME, 'localhost')
        try { $localNames += Get-WsusLocalFqdn } catch { Write-Verbose "Local FQDN not resolved: $($_.Exception.Message)" }
    }

    process {
        foreach ($server in $WsusServer) {
            try {
                $wsus = Connect-WsusNode -Server $server -Port $Port
            }
            catch {
                Write-Error -Message $_.Exception.Message -Category ConnectionError -TargetObject $server -ErrorId 'WsusNodeUnreachable'
                continue
            }

            $config = $wsus.GetConfiguration()
            $lastSync = $wsus.GetSubscription().GetLastSynchronizationInfo()

            $status = [ordered]@{
                PSTypeName                 = 'WSUS.NodeStatus'
                Server                     = $server
                Role                       = Get-WsusNodeRole -Wsus $wsus
                LastSyncTime               = $null
                LastSyncResult             = $null
                ContentPath                = $null
                ContentFreeGB              = $null
                ContentTotalGB             = $null
                ContentFreePercent         = $null
                MaintenanceLogPath         = $null
                MaintenanceLogLastWriteTime = $null
                DeclineLogPath             = $null
                DeclineLogLastWriteTime    = $null
            }

            if ($lastSync) {
                $status.LastSyncTime = $lastSync.StartTime
                $status.LastSyncResult = [string] $lastSync.Result
            }

            if ($server -in $localNames) {
                $status.ContentPath = $config.LocalContentCachePath

                $disk = Get-WsusContentDisk -ContentPath $status.ContentPath
                if ($disk) {
                    $status.ContentFreeGB = $disk.FreeGB
                    $status.ContentTotalGB = $disk.TotalGB
                    $status.ContentFreePercent = $disk.FreePercent
                }

                $maintLog = Get-WsusNewestLog -Kind Maintenance
                if ($maintLog) {
                    $status.MaintenanceLogPath = $maintLog.FullName
                    $status.MaintenanceLogLastWriteTime = $maintLog.LastWriteTime
                }
                $declineLog = Get-WsusNewestLog -Kind Decline
                if ($declineLog) {
                    $status.DeclineLogPath = $declineLog.FullName
                    $status.DeclineLogLastWriteTime = $declineLog.LastWriteTime
                }
            }

            [PSCustomObject] $status
        }
    }
}
