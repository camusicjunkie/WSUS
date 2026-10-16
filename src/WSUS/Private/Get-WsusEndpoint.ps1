function Get-WsusEndpoint {
    <#
    .SYNOPSIS
        Describes how to reach a WSUS node: its port, whether it uses SSL, and its client web service URL.
    .DESCRIPTION
        The one place that decides the protocol from the port: 8531 is SSL (https), any other port is
        plain http. Connecting to a node, probing an Upstream and saving a sync source all use it.
    #>
    [CmdletBinding()]
    [OutputType('WSUS.Endpoint')]
    param (
        # FQDN of the WSUS node.
        [Parameter(Mandatory)]
        [string] $Fqdn,

        # WSUS port. 8531 means SSL, any other port plain http. Default 8531.
        [int] $Port = 8531
    )

    $useSsl = $Port -eq 8531
    $scheme = if ($useSsl) { 'https' } else { 'http' }

    [PSCustomObject]@{
        PSTypeName       = 'WSUS.Endpoint'
        Fqdn             = $Fqdn
        Port             = $Port
        UseSsl           = $useSsl
        ClientServiceUri = "${scheme}://${Fqdn}:$Port/ClientWebService/client.asmx"
    }
}
