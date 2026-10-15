function Assert-WsusReplica {
    <#
    .SYNOPSIS
        Throws unless the connected node is a Replica.
    #>
    [CmdletBinding()]
    param (
        # Connected WSUS node (IUpdateServer) to check.
        [Parameter(Mandatory)]
        $Wsus,

        # Function named in the error as the one to use on an Upstream. Default Set-WsusUpstreamConfig.
        [string] $Instead = 'Set-WsusUpstreamConfig'
    )

    if ((Get-WsusNodeRole -Wsus $Wsus) -ne 'Replica') {
        throw "WSUS node '$($Wsus.Name)' is an Upstream, not a Replica. Use $Instead instead."
    }
}
