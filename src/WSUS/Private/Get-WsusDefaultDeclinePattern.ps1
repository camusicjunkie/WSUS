function Get-WsusDefaultDeclinePattern {
    <#
    .SYNOPSIS
        Returns the default regex of update titles to decline (the one module constant both runs share).
    .DESCRIPTION
        Matches other architectures, previews, and Windows 11 versions you don't run (21H2 titles
        carry no version, hence 'Windows 11 for ').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    'ARM64|Preview|Beta|Itanium|Windows 11 for |Windows 11,? version (21H2|22H2|23H2)'
}
