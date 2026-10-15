function Invoke-WsusMaintenance {
    <#
    .SYNOPSIS
        The maintenance run on this node: targeted declines, built-in cleanup and WID index maintenance.
    .DESCRIPTION
        Meant for a weekly scheduled task on both nodes (Register-WsusMaintenanceTask), run as SYSTEM.
        Local only: -WsusServer must be this node's FQDN because the WID pipe and logs are local.

        Steps, in order (the first failure throws and later steps do not run):
          1. Upstream only: declines superseded updates older than -SupersededAgeDays and titles
             matching -DeclinePattern. Replicas inherit declines from the upstream.
          2. Invoke-WsusServerCleanup. A replica uses the cleanup options without the decline options.
          3. SUSDB in WID: adds Microsoft's two recommended indexes, reindexes, updates statistics.

        Writes a transcript (kept: -KeepLogs); retention and closing the log run even on failure.
        After the first full sync, or to recover a full content disk, run it once with
        -SupersededAgeDays 0 so every superseded update is declined and its files deleted.
        Under powershell.exe -Command an uncaught error gives exit code 1 for Task Scheduler.
    .EXAMPLE
        Invoke-WsusMaintenance -WhatIf
    .EXAMPLE
        Invoke-WsusMaintenance -SupersededAgeDays 0
        First-build or disk-full cleanup: decline every superseded update and delete unneeded files.
    .OUTPUTS
        WSUS.MaintenanceRun
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.MaintenanceRun')]
    param (
        # Decline superseded updates that arrived more than this many days ago (0-365). Default 30.
        [ValidateRange(0, 365)]
        [int] $SupersededAgeDays = 30,

        # Regex matched against update titles. Defaults to the pattern shared with Invoke-WsusDecline.
        [string] $DeclinePattern = (Get-WsusDefaultDeclinePattern),

        # WID named pipe. Only change this for a non-default WID.
        [string] $WidInstance = '\\.\pipe\MICROSOFT##WID\tsql\query',

        # Must be this node's FQDN (the default).
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531,

        # Folder for transcripts. Default C:\ProgramData\WsusMaintenance.
        [string] $LogPath = 'C:\ProgramData\WsusMaintenance',

        # Number of maintenance transcripts to keep (1-520). Default 12.
        [ValidateRange(1, 520)]
        [int] $KeepLogs = 12
    )

    $maintenanceSql = @'
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'nclLocalizedPropertyID')
    CREATE NONCLUSTERED INDEX nclLocalizedPropertyID ON dbo.tbLocalizedPropertyForRevision (LocalizedPropertyID);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'nclSupercededUpdateID')
    CREATE NONCLUSTERED INDEX nclSupercededUpdateID ON dbo.tbRevisionSupersedesUpdate (SupersededUpdateID);

DECLARE @cmd nvarchar(max) = N'';
SELECT @cmd += N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
     + CASE WHEN ps.avg_fragmentation_in_percent > 30 THEN N' REBUILD;' ELSE N' REORGANIZE;' END + CHAR(10)
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN sys.objects o ON o.object_id = ps.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE ps.avg_fragmentation_in_percent > 10 AND ps.page_count > 1000 AND i.name IS NOT NULL;
EXEC sp_executesql @cmd;
EXEC sp_updatestats;
'@

    Assert-WsusPrerequisite -Module UpdateServices -Administrator
    $localFqdn = Get-WsusLocalFqdn
    if ($WsusServer -ne $localFqdn) {
        throw "Invoke-WsusMaintenance runs on the local node only (WID and logs are local): '$WsusServer' is not '$localFqdn'."
    }

    $log = Start-WsusLog -Prefix maint -Path $LogPath
    try {
        $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
        $role = Get-WsusNodeRole -Wsus $wsus

        $declined = @()
        $cleanup = $null
        $database = 'Skipped'

        if ($role -eq 'Upstream') {
            $declined = @(Invoke-WsusDeclinePass -Wsus $wsus -Pattern $DeclinePattern `
                    -SupersededOlderThan ([datetime]::UtcNow.AddDays(-$SupersededAgeDays)))
        }

        $cleanupParams = @{
            UpdateServer                = $wsus
            CleanupObsoleteComputers    = $true
            CleanupObsoleteUpdates      = $true
            CleanupUnneededContentFiles = $true
            CompressUpdates             = $true
        }
        if ($role -eq 'Upstream') {
            $cleanupParams['DeclineExpiredUpdates'] = $true
            $cleanupParams['DeclineSupersededUpdates'] = $true
        }
        if ($PSCmdlet.ShouldProcess($WsusServer, 'Invoke-WsusServerCleanup')) {
            $cleanup = Invoke-WsusServerCleanup @cleanupParams
        }

        if ($PSCmdlet.ShouldProcess("$WidInstance/SUSDB", 'Index and statistics maintenance')) {
            Invoke-WsusDatabaseQuery -Instance $WidInstance -Query $maintenanceSql
            $database = 'Completed'
        }
    }
    finally {
        Stop-WsusLog -Prefix maint -Path $LogPath -Keep $KeepLogs
    }

    [PSCustomObject]@{
        PSTypeName      = 'WSUS.MaintenanceRun'
        Server          = $WsusServer
        Role            = $role
        Declined        = $declined.Count
        DeclinedUpdates = $declined
        Cleanup         = $cleanup
        Database        = $database
        Log             = $log
    }
}
