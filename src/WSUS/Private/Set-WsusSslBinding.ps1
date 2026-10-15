function Set-WsusSslBinding {
    <#
    .SYNOPSIS
        Binds a certificate to the WSUS site on 8531 and requires SSL on the WSUS web services.
    .DESCRIPTION
        Test seam over the IIS binding and WebAdministration cmdlets (no decisions). Update content
        stays on HTTP 8530 by design. Mock it by name in tests.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin seam; the public caller owns ShouldProcess.')]
    [CmdletBinding()]
    param (
        # Thumbprint of the certificate in Cert:\LocalMachine\My to bind to 8531.
        [Parameter(Mandatory)]
        [string] $Thumbprint
    )

    $siteName = 'WSUS Administration'
    $binding = Get-WebBinding -Name $siteName -Protocol https -Port 8531
    if (-not $binding) {
        New-WebBinding -Name $siteName -Protocol https -Port 8531
        $binding = Get-WebBinding -Name $siteName -Protocol https -Port 8531
    }
    try {
        $binding.RemoveSslCertificate()
    }
    catch {
        Write-Verbose -Message 'No existing certificate on 8531'
    }
    $binding.AddSslCertificate($Thumbprint, 'My')

    $sslServices = 'ApiRemoting30', 'ClientWebService', 'DSSAuthWebService', 'ServerSyncWebService',
        'SimpleAuthWebService'
    foreach ($webService in $sslServices) {
        $sslParams = @{
            PSPath   = 'IIS:\'
            Location = "$siteName/$webService"
            Filter   = 'system.webServer/security/access'
            Name     = 'sslFlags'
            Value    = 'Ssl'
        }
        Set-WebConfigurationProperty @sslParams
    }
}
