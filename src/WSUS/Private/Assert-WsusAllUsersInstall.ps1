function Assert-WsusAllUsersInstall {
    <#
    .SYNOPSIS
        Throws unless the WSUS module is installed in an all-users module path.
    .DESCRIPTION
        Scheduled tasks run as SYSTEM through powershell.exe and only see the all-users module paths
        of Windows PowerShell 5.1 (Program Files and the system module folder), so registering a task
        from a per-user install or an ad-hoc import would leave a task that can't run.
    #>
    [CmdletBinding()]
    param (
        # Folder the module was loaded from. Defaults to the module's own base; a parameter for testing.
        [string] $ModuleBase = $ExecutionContext.SessionState.Module.ModuleBase
    )

    $roots = @(
        (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
        (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\Modules')
    )

    $base = [System.IO.Path]::GetFullPath($ModuleBase)
    foreach ($root in $roots) {
        if ($base.StartsWith($root.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    throw ("The WSUS module is loaded from '$ModuleBase', which is not an all-users module path. " +
        'Scheduled tasks run as SYSTEM and would not find it. ' +
        "Install it for all users (elevated): Install-Module WSUS -Repository LocalGallery -Scope AllUsers")
}
