function Get-WsusNewestLog {
    <#
    .SYNOPSIS
        Returns the newest '<Prefix>_*.log' file in a folder, or nothing when there is none.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Prefix,

        [string] $Path = 'C:\ProgramData\WsusMaintenance'
    )

    Get-ChildItem -LiteralPath $Path -Filter "${Prefix}_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1
}
