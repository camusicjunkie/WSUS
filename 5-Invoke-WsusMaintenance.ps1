<#
.SYNOPSIS
    WSUS maintenance on one node: targeted declines, built-in cleanup and WID index maintenance.

.DESCRIPTION
    Runs from scheduled tasks on BOTH nodes, as SYSTEM. Detects whether the node is a replica.

    Full run (weekly, both nodes):
      1. Upstream only: declines superseded updates older than -SupersededAgeDays and titles
         matching -DeclinePattern. Replicas inherit declines from the upstream.
         After the first full sync (or to recover a full content disk), run it once with
         -SupersededAgeDays 0 so every superseded update is declined and its files deleted.
      2. Runs Invoke-WsusServerCleanup. Replicas skip the decline options, which they can't use.
      3. SUSDB in WID: adds Microsoft's two recommended indexes, reindexes, updates statistics.

    -DeclineOnly run (every 15 minutes, upstream only):
      Declines updates that arrived in the last -RecentDays and match -DeclinePattern, so ARM64
      cumulative updates (~5 GB) approved at the end of a sync are caught before much downloads.
      On a replica it exits without doing anything, so the same task can exist on both nodes.

.EXAMPLE
    .\5-Invoke-WsusMaintenance.ps1 -WhatIf

.EXAMPLE
    .\5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0
    First-build or disk-full cleanup: decline every superseded update and delete unneeded files.

.EXAMPLE
    # Register both tasks once on each node; re-register on a rebuilt node.
    $script = 'C:\Scripts\WSUS\5-Invoke-WsusMaintenance.ps1'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $weeklyParams = @{
        TaskName  = 'WSUS Maintenance'
        Action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
            "-NoProfile -ExecutionPolicy Bypass -File $script")
        Trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '02:00'
        Principal = $principal
    }
    Register-ScheduledTask @weeklyParams

    $declineParams = @{
        TaskName  = 'WSUS Decline Unwanted'
        Action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
            "-NoProfile -ExecutionPolicy Bypass -File $script -DeclineOnly")
        Trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
        Principal = $principal
    }
    Register-ScheduledTask @declineParams

    Stagger the weekly task on WSUS02 (for example 04:00) so both nodes aren't busy at once.
#>
#Requires -Version 5.1
#Requires -Modules UpdateServices
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Full')]
param (
    # Only decline recently arrived updates that match -DeclinePattern (post-sync task).
    [Parameter(Mandatory, ParameterSetName = 'DeclineOnly')]
    [switch] $DeclineOnly,

    # DeclineOnly: how many days of recent arrivals to check.
    [Parameter(ParameterSetName = 'DeclineOnly')]
    [ValidateRange(1, 30)]
    [int] $RecentDays = 2,

    # Full run: decline superseded updates that arrived more than this many days ago.
    [Parameter(ParameterSetName = 'Full')]
    [ValidateRange(0, 365)]
    [int] $SupersededAgeDays = 30,

    # Full run: WID named pipe. Only change this for a non-default WID.
    [Parameter(ParameterSetName = 'Full')]
    [string] $WidInstance = '\\.\pipe\MICROSOFT##WID\tsql\query',

    # Node FQDN to connect to. Defaults to this node.
    [string] $WsusServer = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName,

    # WSUS API port on the node.
    [int] $Port = 8531,

    # Regex matched against update titles to decline: other architectures, previews, and Windows 11
    # versions you don't run (21H2 titles carry no version, hence 'Windows 11 for ').
    [string] $DeclinePattern = 'ARM64|Preview|Beta|Itanium|Windows 11 for |Windows 11,? version (21H2|22H2|23H2)',

    # Folder for transcripts.
    [string] $LogPath = 'C:\ProgramData\WsusMaintenance',

    # Number of transcripts to keep, per run type.
    [ValidateRange(1, 520)]
    [int] $KeepLogs = 12
)

begin {
    $ErrorActionPreference = 'Stop'

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

    $logPrefix = if ($DeclineOnly) { 'decline' } else { 'maint' }
    $null = New-Item -ItemType Directory -Path $LogPath -Force -WhatIf:$false
    $transcript = Join-Path -Path $LogPath -ChildPath ('{0}_{1:yyyyMMdd_HHmm}.log' -f $logPrefix, (Get-Date))
    $null = Start-Transcript -Path $transcript -WhatIf:$false
}

end {
    $declined = 0
    $cleanup = $null
    $databaseResult = 'Skipped'
    $isReplica = $false

    try {
        $wsus = Get-WsusServer -Name $WsusServer -PortNumber $Port -UseSsl
        $isReplica = $wsus.GetConfiguration().IsReplicaServer

        # --- 1. Targeted declines (upstream only) ----------------------------------------------
        if ($isReplica) {
            Write-Verbose -Message 'Replica: declines come from the upstream, skipping'
        } else {
            $now = [datetime]::UtcNow
            $cutoff = $now.AddDays(-$SupersededAgeDays)
            $scope = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateScope
            if ($DeclineOnly) {
                $scope.FromArrivalDate = $now.AddDays(-$RecentDays)
            }
            foreach ($update in $wsus.GetUpdates($scope)) {
                if ($update.IsDeclined) {
                    continue
                }
                $isOldSuperseded = -not $DeclineOnly -and $update.IsSuperseded -and $update.ArrivalDate -lt $cutoff
                if (($isOldSuperseded -or $update.Title -match $DeclinePattern) -and
                    $PSCmdlet.ShouldProcess($update.Title, 'Decline')) {
                    $update.Decline()
                    $declined++
                }
            }
        }

        if (-not $DeclineOnly) {
            # --- 2. Built-in cleanup ------------------------------------------------------------
            $cleanupParams = @{
                UpdateServer                = $wsus
                CleanupObsoleteComputers    = $true
                CleanupObsoleteUpdates      = $true
                CleanupUnneededContentFiles = $true
                CompressUpdates             = $true
            }
            if (-not $isReplica) {
                $cleanupParams['DeclineExpiredUpdates'] = $true
                $cleanupParams['DeclineSupersededUpdates'] = $true
            }
            if ($PSCmdlet.ShouldProcess($WsusServer, 'Invoke-WsusServerCleanup')) {
                $cleanup = Invoke-WsusServerCleanup @cleanupParams
            }

            # --- 3. SUSDB maintenance in WID ------------------------------------------------------
            if ($PSCmdlet.ShouldProcess("$WidInstance/SUSDB", 'Index and statistics maintenance')) {
                $connectionParams = @{
                    TypeName     = 'System.Data.SqlClient.SqlConnection'
                    ArgumentList = "Server=$WidInstance;Database=SUSDB;Integrated Security=SSPI;"
                }
                $connection = New-Object @connectionParams
                try {
                    $connection.Open()
                    $command = $connection.CreateCommand()
                    $command.CommandText = $maintenanceSql
                    $command.CommandTimeout = 0
                    $null = $command.ExecuteNonQuery()
                    $databaseResult = 'Completed'
                } finally {
                    $connection.Dispose()
                }
            }
        }
    } finally {
        Get-ChildItem -Path $LogPath -Filter ('{0}_*.log' -f $logPrefix) |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip $KeepLogs |
            Remove-Item -Force
        $null = Stop-Transcript
    }

    [PSCustomObject]@{
        Server   = $WsusServer
        Role     = if ($isReplica) { 'Replica' } else { 'Upstream' }
        Mode     = $PSCmdlet.ParameterSetName
        Declined = $declined
        Cleanup  = ($cleanup | Out-String).Trim()
        Database = $databaseResult
        Log      = $transcript
    }
}
