function Connect-WsusNode {
    <#
    .SYNOPSIS
        Connects to a WSUS node over SSL and returns the IUpdateServer.
    .DESCRIPTION
        Always uses SSL. On failure throws one error that names the node and the port, so a wrong
        server can be told apart from a closed port. Does not check prerequisites; callers run
        Assert-WsusPrerequisite first.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Server,

        [int] $Port = 8531
    )

    try {
        Get-WsusServer -Name $Server -PortNumber $Port -UseSsl -ErrorAction Stop
    }
    catch {
        throw "Cannot connect to WSUS node '$Server' on port $Port (SSL): $($_.Exception.Message)"
    }
}
