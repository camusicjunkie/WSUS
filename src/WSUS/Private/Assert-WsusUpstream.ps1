function Assert-WsusUpstream {
    <#
    .SYNOPSIS
        Throws unless the connected node is an upstream.
    .DESCRIPTION
        Approval rules and approvals/declines exist only on the upstream; a replica copies them.
        The error names the node and the function to use instead.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Wsus,

        [Parameter(Mandatory)]
        [string] $Server,

        [string] $Instead = 'run it against the upstream'
    )

    if ((Get-WsusNodeRole -Wsus $Wsus) -ne 'Upstream') {
        throw "$Server is a replica. This works on the upstream only; $Instead."
    }
}
