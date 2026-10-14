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
    .PARAMETER WsusServer
        One or more node names. Accepts pipeline input and a property named WsusServer or Server.
        Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
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
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Server')]
        [string[]] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices

        $localNames = @($env:COMPUTERNAME, 'localhost')
        try { $localNames += Get-WsusLocalFqdn } catch { Write-Verbose "Local FQDN not resolved: $($_.Exception.Message)" }

        $logRoot = 'C:\ProgramData\WsusMaintenance'
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

                $driveName = if ($status.ContentPath) { [string] $status.ContentPath.Substring(0, 1) }
                $drive = if ($driveName -match '^[A-Za-z]$' -and $status.ContentPath -match '^[A-Za-z]:') {
                    Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
                }
                if ($drive) {
                    $total = [double] $drive.Used + [double] $drive.Free
                    $status.ContentFreeGB = [math]::Round($drive.Free / 1GB, 2)
                    $status.ContentTotalGB = [math]::Round($total / 1GB, 2)
                    if ($total -gt 0) { $status.ContentFreePercent = [math]::Round($drive.Free / $total * 100, 1) }
                }

                $newest = @{}
                foreach ($kind in 'maint', 'decline') {
                    $newest[$kind] = Get-ChildItem -LiteralPath $logRoot -Filter "${kind}_*.log" -File -ErrorAction SilentlyContinue |
                        Sort-Object -Property LastWriteTime -Descending |
                        Select-Object -First 1
                }
                if ($newest.maint) {
                    $status.MaintenanceLogPath = $newest.maint.FullName
                    $status.MaintenanceLogLastWriteTime = $newest.maint.LastWriteTime
                }
                if ($newest.decline) {
                    $status.DeclineLogPath = $newest.decline.FullName
                    $status.DeclineLogLastWriteTime = $newest.decline.LastWriteTime
                }
            }

            [PSCustomObject] $status
        }
    }
}
