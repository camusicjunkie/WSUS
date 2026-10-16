function ConvertTo-WsusUpstream {
    <#
    .SYNOPSIS
        Promotes a Replica to an Upstream that syncs from Microsoft Update.
    .DESCRIPTION
        Use only when the original Upstream is lost for good (or will be rebuilt as the new Replica).
        Existing approvals, groups and declines stay in the node's database. Everything else
        (proxy, languages, content flags, approval rules) stays with Set-WsusUpstreamConfig.

        Throws when the node is already an Upstream. Refuses when the configured upstream still
        answers, unless -Force.
    .EXAMPLE
        ConvertTo-WsusUpstream -WhatIf
        Shows what promoting this replica would do.
    .EXAMPLE
        ConvertTo-WsusUpstream -WsusServer wsus02.contoso.local -Force
        Promotes wsus02 although wsus01 still answers (planned swap).
    .OUTPUTS
        WSUS.PromoteResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('WSUS.PromoteResult')]
    param (
        # Node to promote. Defaults to this machine's FQDN.
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531,

        # Promote even though the current upstream is still reachable.
        [switch] $Force
    )

    Assert-WsusPrerequisite -Module UpdateServices -Administrator
    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
    Assert-WsusReplica -Wsus $wsus

    $config = $wsus.GetConfiguration()
    $previous = '{0}:{1}' -f $config.UpstreamWsusServerName, $config.UpstreamWsusServerPortNumber

    if (-not $Force) {
        if ($WhatIfPreference) {
            Write-Information -MessageData "What if: would probe ${previous} to confirm the upstream is lost" -InformationAction Continue
        }
        elseif (Test-WsusUpstreamReachable -Fqdn $config.UpstreamWsusServerName -Port $config.UpstreamWsusServerPortNumber) {
            throw "The upstream $previous still answers. Promote only when it is lost for good; use -Force to promote anyway (for example when it will be rebuilt as the new replica)."
        }
    }

    if ($PSCmdlet.ShouldProcess($WsusServer, 'Promote replica to Upstream (sync from Microsoft Update)')) {
        Set-WsusSyncSource -Config $config -MicrosoftUpdate
        $config.Save()
    }

    [PSCustomObject]@{
        PSTypeName       = 'WSUS.PromoteResult'
        Server           = $WsusServer
        PreviousUpstream = $previous
        Role             = 'Upstream'
        NextStep         = ("Set-WsusUpstreamConfig -ProxyHost <proxy> here; Enable-WsusApprovalRule -Name 'Auto - *'; " +
            'Start-WsusSync -Wait; Register-WsusMaintenanceTask here; swap the NetScaler primary; ' +
            "rebuild the old upstream as a replica with Set-WsusReplicaConfig -UpstreamFqdn $WsusServer")
    }
}
