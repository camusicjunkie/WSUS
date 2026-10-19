function Get-WsusNodeStatus {
    <#
    .SYNOPSIS
        Reports plain facts about one or more WSUS nodes: role, sync state, update counts, content disk and run logs.
    .DESCRIPTION
        Read-only; works on an upstream and a replica. Role, sync facts (last result and error, whether a sync
        is running with its phase and progress), the update, approved and declined counts, and content still
        to download (DownloadPendingMB, DownloadFailedCount) work remotely. A replica only receives an approved
        update once its upstream has downloaded that update's content (#37), so check the upstream's
        DownloadPendingMB has been 0 for a few minutes before expecting the replica's counts to match.
        Content disk and maintenance/decline log facts can only be read on this machine, so for any other
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
            $subscription = $wsus.GetSubscription()
            $lastSync = $subscription.GetLastSynchronizationInfo()
            $serverStatus = $wsus.GetStatus()
            $download = $wsus.GetContentDownloadProgress()

            $status = [ordered]@{
                PSTypeName                 = 'WSUS.NodeStatus'
                Server                     = $server
                Role                       = Get-WsusNodeRole -Wsus $wsus
                LastSyncTime               = $null
                LastSyncResult             = $null
                LastSyncError              = $null
                SyncStatus                 = [string] $subscription.GetSynchronizationStatus()
                SyncPhase                  = $null
                SyncProcessedItems         = $null
                SyncTotalItems             = $null
                UpdateCount                = $serverStatus.UpdateCount
                ApprovedUpdateCount        = $serverStatus.ApprovedUpdateCount
                DeclinedUpdateCount        = $serverStatus.DeclinedUpdateCount
                DownloadPendingMB          = [math]::Round(($download.TotalBytesToDownload - $download.DownloadedBytes) / 1MB, 1)
                DownloadFailedCount        = $wsus.GetFailedToDownloadUpdatesCount()
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
                if ($status.LastSyncResult -eq 'Failed') { $status.LastSyncError = [string] $lastSync.Error }
            }

            if ($status.SyncStatus -eq 'Running') {
                $progress = $subscription.GetSynchronizationProgress()
                $status.SyncPhase = [string] $progress.Phase
                $status.SyncProcessedItems = $progress.ProcessedItems
                $status.SyncTotalItems = $progress.TotalItems
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
