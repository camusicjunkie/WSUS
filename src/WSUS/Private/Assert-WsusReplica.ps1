function Assert-WsusReplica {
    <#
    .SYNOPSIS
        Throws unless the connected node is a Replica.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Wsus,

        [string] $Instead = 'Set-WsusUpstreamConfig'
    )

    if ((Get-WsusNodeRole -Wsus $Wsus) -ne 'Replica') {
        throw "WSUS node '$($Wsus.Name)' is an Upstream, not a Replica. Use $Instead instead."
    }
}
