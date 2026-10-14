function Test-WsusCertificate {
    <#
    .SYNOPSIS
        Throws unless a certificate in Cert:\LocalMachine\My is usable for a WSUS node.
    .DESCRIPTION
        Checks the certificate exists, has a private key, is valid for at least 30 more days, has the
        Server Authentication EKU and covers every required name as a SAN. All problems are listed in
        one error. Called first by Set-WsusNodeConfig, before anything is changed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Thumbprint,

        [Parameter(Mandatory)]
        [string[]] $RequiredName
    )

    $cert = Get-Item -LiteralPath "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) {
        throw "Certificate $Thumbprint is not in Cert:\LocalMachine\My"
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    if (-not $cert.HasPrivateKey) {
        $problems.Add('no private key')
    }
    if ($cert.NotAfter -lt (Get-Date).AddDays(30)) {
        $problems.Add(('expires {0:yyyy-MM-dd}' -f $cert.NotAfter))
    }
    if ($cert.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.1') {
        $problems.Add('missing Server Authentication EKU')
    }
    $sanNames = $cert.DnsNameList.Unicode
    foreach ($name in $RequiredName) {
        if ($sanNames -notcontains $name) {
            $problems.Add("SAN missing $name")
        }
    }

    if ($problems.Count -gt 0) {
        throw ('Certificate {0} rejected: {1}' -f $Thumbprint, ($problems -join '; '))
    }
    Write-Verbose -Message "Certificate OK: $($sanNames -join ', ')"
}
