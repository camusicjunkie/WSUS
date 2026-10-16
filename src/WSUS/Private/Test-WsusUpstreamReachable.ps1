function Test-WsusUpstreamReachable {
    <#
    .SYNOPSIS
        Returns $true when an upstream WSUS node answers on its port.
    .DESCRIPTION
        Test seam over the request for the node's client web service (see Get-WsusEndpoint;
        https on 8531, http otherwise). Makes no decisions; callers decide what an unreachable upstream means.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # FQDN of the upstream WSUS node.
        [Parameter(Mandatory)]
        [string] $Fqdn,

        # Upstream WSUS port. 8531 probes over https, any other port over http. Default 8531.
        [int] $Port = 8531
    )

    try {
        $null = Invoke-WebRequest -Uri (Get-WsusEndpoint -Fqdn $Fqdn -Port $Port).ClientServiceUri -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $true
    }
    catch {
        Write-Verbose "Upstream ${Fqdn}:$Port not reachable: $($_.Exception.Message)"
        $false
    }
}
