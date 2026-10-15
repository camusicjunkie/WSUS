function Grant-WsusFileAccess {
    <#
    .SYNOPSIS
        Takes ownership of a file and grants local Administrators full control.
    .DESCRIPTION
        Test seam over takeown.exe and icacls.exe (no decisions). Mock it by name in tests.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin seam; the public caller owns ShouldProcess.')]
    [CmdletBinding()]
    param (
        # File to take ownership of and grant Administrators full control.
        [Parameter(Mandatory)]
        [string] $Path
    )

    $null = & "$env:SystemRoot\System32\takeown.exe" /f $Path
    $null = & "$env:SystemRoot\System32\icacls.exe" $Path /grant '*S-1-5-32-544:F'
}
