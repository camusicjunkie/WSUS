function Restart-WsusService {
    <#
    .SYNOPSIS
        Restarts IIS and the WSUS service, then optionally waits for them to settle.
    .DESCRIPTION
        Test seam over iisreset.exe and Restart-Service (no decisions). Mock it by name in tests.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin seam; the public caller owns ShouldProcess.')]
    [CmdletBinding()]
    param (
        # Seconds to wait after the restarts.
        [int] $Sleep = 0
    )

    $null = & "$env:SystemRoot\System32\iisreset.exe"
    Restart-Service -Name WsusService
    if ($Sleep -gt 0) {
        Start-Sleep -Seconds $Sleep
    }
}
