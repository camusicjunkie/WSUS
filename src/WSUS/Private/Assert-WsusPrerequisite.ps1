function Assert-WsusPrerequisite {
    <#
    .SYNOPSIS
        Checks modules, elevation and Windows features; throws one error listing everything missing.
    .DESCRIPTION
        Called first by each public function (each function guards its own prerequisites; the module
        has no RequiredModules). Only Install-WsusNode needs -Feature.
    #>
    [CmdletBinding()]
    param (
        # Modules that must be available, e.g. UpdateServices.
        [string[]] $Module,

        # Require an elevated PowerShell session.
        [switch] $Administrator,

        # Windows features that must be installed.
        [string[]] $Feature
    )

    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $Module) {
        if (-not (Get-Module -ListAvailable -Name $name)) {
            $missing.Add("PowerShell module '$name' is not available")
        }
    }

    if ($Administrator -and -not (Test-WsusElevated)) {
        $missing.Add('PowerShell is not elevated (run as Administrator)')
    }

    foreach ($name in $Feature) {
        try {
            $found = Get-WindowsFeature -Name $name -ErrorAction Stop
        }
        catch {
            $found = $null
        }
        if (-not $found -or $found.InstallState -notin 'Available', 'Installed') {
            $missing.Add("Windows feature '$name' is not available")
        }
    }

    if ($missing.Count -gt 0) {
        throw ("Prerequisites not met:`n" + (($missing | ForEach-Object { " - $_" }) -join "`n"))
    }
}
