function Get-WsusNewestLog {
    <#
    .SYNOPSIS
        Returns the newest log file of a kind of run, or nothing when there is none.
    #>
    [CmdletBinding()]
    param (
        # Kind of run whose log to find (see Get-WsusLogLayout).
        [Parameter(Mandatory)]
        [ValidateSet('Maintenance', 'Decline')]
        [string] $Kind,

        # Folder holding the logs. Default the log folder in Get-WsusLogLayout.
        [string] $Path = (Get-WsusLogLayout).Root
    )

    $prefix = (Get-WsusLogLayout).Prefix[$Kind]

    Get-ChildItem -LiteralPath $Path -Filter "${prefix}_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1
}
