function Test-WsusUpstreamReachable {
    <#
    .SYNOPSIS
        Returns $true when an upstream WSUS node answers on its SSL port.
    .DESCRIPTION
        Test seam over the request for https://<Fqdn>:<Port>/selfupdate/wuident.cab. Makes no
        decisions; callers decide what an unreachable upstream means.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Fqdn,

        [int] $Port = 8531
    )

    try {
        $null = Invoke-WebRequest -Uri "https://${Fqdn}:$Port/selfupdate/wuident.cab" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $true
    }
    catch {
        Write-Verbose "Upstream ${Fqdn}:$Port not reachable: $($_.Exception.Message)"
        $false
    }
}
