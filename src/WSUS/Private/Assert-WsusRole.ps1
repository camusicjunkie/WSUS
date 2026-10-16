function Assert-WsusRole {
    <#
    .SYNOPSIS
        Throws a terminating error unless the connected WSUS node has the role the caller needs.
    .DESCRIPTION
        Returns nothing when the node has the role. The error names the node and says what to do
        instead.

        -Role Upstream throws on a Replica. -Instead is extra text appended to the error.
        -Role Replica throws on an Upstream. -Instead is the function to use, default
        Set-WsusUpstreamConfig.
    #>
    [CmdletBinding()]
    param (
        # The IUpdateServer returned by Connect-WsusNode.
        [Parameter(Mandatory)]
        $Wsus,

        # The role the node must have.
        [Parameter(Mandatory)]
        [ValidateSet('Upstream', 'Replica')]
        [string] $Role,

        # Optional text naming what to do instead; see the description for how each role uses it.
        [string] $Instead
    )

    $actual = Get-WsusNodeRole -Wsus $Wsus
    if ($actual -eq $Role) {
        return
    }

    if ($Role -eq 'Upstream') {
        $message = "'$($Wsus.Name)' is a Replica; this action runs on an Upstream only."
        if ($Instead) { $message += " $Instead" }
        throw $message
    }

    if (-not $Instead) { $Instead = 'Set-WsusUpstreamConfig' }
    throw "WSUS node '$($Wsus.Name)' is an Upstream, not a Replica. Use $Instead instead."
}
