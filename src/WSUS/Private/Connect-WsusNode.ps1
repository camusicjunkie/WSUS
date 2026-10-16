function Connect-WsusNode {
    <#
    .SYNOPSIS
        Connects to a WSUS node and returns the IUpdateServer.
    .DESCRIPTION
        Uses SSL on 8531 and plain HTTP on any other port. On failure throws one error that names the node and the port, so a wrong
        server can be told apart from a closed port. Does not check prerequisites; callers run
        Assert-WsusPrerequisite first.
    #>
    [CmdletBinding()]
    param (
        # FQDN of the WSUS node to connect to.
        [Parameter(Mandatory)]
        [string] $Server,

        # WSUS port. 8531 connects with SSL, any other port without. Default 8531.
        [int] $Port = 8531
    )

    $endpoint = Get-WsusEndpoint -Fqdn $Server -Port $Port
    try {
        Get-WsusServer -Name $Server -PortNumber $Port -UseSsl:$endpoint.UseSsl -ErrorAction Stop
    }
    catch {
        $protocol = if ($endpoint.UseSsl) { 'SSL' } else { 'no SSL' }
        throw "Cannot connect to WSUS node '$Server' on port $Port ($protocol): $($_.Exception.Message)"
    }
}
