function Assert-WsusUpstream {
    <#
    .SYNOPSIS
        Throws a terminating error when the connected WSUS node is a replica.
    .DESCRIPTION
        Returns nothing on an upstream. The error names the node and the function to use instead.
    #>
    [CmdletBinding()]
    param (
        # The IUpdateServer returned by Connect-WsusNode.
        [Parameter(Mandatory)]
        $Wsus,

        # Optional text naming what to do on a replica; appended to the error.
        [string] $Instead
    )

    if ((Get-WsusNodeRole -Wsus $Wsus) -eq 'Replica') {
        $message = "'$($Wsus.Name)' is a Replica; this action runs on an Upstream only."
        if ($Instead) { $message += " $Instead" }
        throw $message
    }
}
