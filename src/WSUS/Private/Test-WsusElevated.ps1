function Test-WsusElevated {
    <#
    .SYNOPSIS
        Returns $true when the current process has an elevated administrator token.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    ([System.Security.Principal.WindowsPrincipal] $identity).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
