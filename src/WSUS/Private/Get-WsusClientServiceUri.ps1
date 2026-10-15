function Get-WsusClientServiceUri {
    <#
    .SYNOPSIS
        Returns the URL of a WSUS node's client web service, the endpoint used to probe a node.
    .DESCRIPTION
        The scheme follows the port: 8531 is SSL (https), any other port is plain http.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # FQDN of the WSUS node.
        [Parameter(Mandatory)]
        [string] $Fqdn,

        # WSUS port. 8531 gives an https URL, any other port http. Default 8531.
        [int] $Port = 8531
    )

    $scheme = if ($Port -eq 8531) { 'https' } else { 'http' }
    "${scheme}://${Fqdn}:$Port/ClientWebService/client.asmx"
}
