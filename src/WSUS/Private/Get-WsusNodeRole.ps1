function Get-WsusNodeRole {
    <#
    .SYNOPSIS
        Returns 'Upstream' or 'Replica' for a connected WSUS node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        $Wsus
    )

    if ($Wsus.GetConfiguration().IsReplicaServer) { 'Replica' } else { 'Upstream' }
}
