function Invoke-WsusDecline {
    <#
    .SYNOPSIS
        The decline run: declines recently arrived updates that match a pattern, on the upstream.
    .DESCRIPTION
        Meant for a 15-minute scheduled task (Register-WsusMaintenanceTask). Declines updates that
        arrived in the last -RecentDays and whose title matches -DeclinePattern, so large unwanted
        updates (for example ARM64 cumulative updates) approved at the end of a sync are caught
        before much downloads.

        Can target a remote upstream; the log is written on the machine running it. On a replica it
        does nothing (declines come from the upstream): it returns Role = 'Replica', Declined = 0 and
        no log, so the same task can exist on both nodes. The first failure throws; the log is
        closed and retention applied regardless, so Task Scheduler sees the failed run.
    .EXAMPLE
        Invoke-WsusDecline -WhatIf
        Lists what the next decline run would decline.
    .OUTPUTS
        WSUS.DeclineRun
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is called per decline by Invoke-WsusDeclinePass, which inherits the -WhatIf and -Confirm.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.DeclineRun')]
    param (
        # How many days of recent arrivals to check (1-30). Default 2.
        [ValidateRange(1, 30)]
        [int] $RecentDays = 2,

        # Regex matched against update titles. Defaults to the pattern shared with Invoke-WsusMaintenance.
        [string] $DeclinePattern = (Get-WsusDefaultDeclinePattern),

        # The upstream node. Defaults to this machine's FQDN.
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531,

        # Folder for transcripts. Default C:\ProgramData\WsusMaintenance.
        [string] $LogPath = (Get-WsusLogLayout).Root,

        # Number of decline transcripts to keep (1-2000). Default 96.
        [ValidateRange(1, 2000)]
        [int] $KeepLogs = 96
    )

    Assert-WsusPrerequisite -Module UpdateServices
    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
    $role = Get-WsusNodeRole -Wsus $wsus

    $declined = @()
    $log = $null
    if ($role -eq 'Upstream') {
        $log = Start-WsusLog -Kind Decline -Path $LogPath -Keep $KeepLogs
        try {
            $declined = @(Invoke-WsusDeclinePass -Wsus $wsus -Pattern $DeclinePattern `
                    -ArrivedSince ([datetime]::UtcNow.AddDays(-$RecentDays)))
        }
        finally {
            Stop-WsusLog -Log $log
        }
    }

    [PSCustomObject]@{
        PSTypeName      = 'WSUS.DeclineRun'
        Server          = $WsusServer
        Role            = $role
        Declined        = $declined.Count
        DeclinedUpdates = $declined
        Log             = if ($log) { $log.Transcript }
    }
}
