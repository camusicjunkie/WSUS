function Get-WsusLogLayout {
    <#
    .SYNOPSIS
        Returns where the run logs live and how the log files of each kind of run are named.
    .DESCRIPTION
        The one place that names the log folder and the file prefixes. Start-WsusLog writes them,
        Stop-WsusLog applies retention to them and Get-WsusNewestLog reads them, so they cannot
        disagree. Returns data only. Each call returns a new object.

        Root    Folder holding the logs.
        Prefix  File prefix per kind of run: Maintenance and Decline. A log file is named
                <Prefix>_<timestamp>.log. Prefixes differ, so retention for one kind never removes
                another's logs.
    #>
    [CmdletBinding()]
    [OutputType('WSUS.LogLayout')]
    param ()

    [PSCustomObject]@{
        PSTypeName = 'WSUS.LogLayout'
        Root       = 'C:\ProgramData\WsusMaintenance'
        Prefix     = @{
            Maintenance = 'maint'
            Decline     = 'decline'
        }
    }
}
