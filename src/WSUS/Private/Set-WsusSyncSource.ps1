function Set-WsusSyncSource {
    <#
    .SYNOPSIS
        Sets where a node gets its updates from and the content flags that go with it.
    .DESCRIPTION
        A sync source is Microsoft Update or an Upstream. With -MicrosoftUpdate the node is an Upstream
        that downloads content from Microsoft Update. With -UpstreamFqdn the node becomes a Replica of
        that Upstream, takes content from it and uses no proxy. Both set the content flags every node
        in this module uses.

        Changes the configuration object in memory only. The caller saves it, under its own
        ShouldProcess, so it can set other values first (the proxy, for example).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper; the public caller wraps it in ShouldProcess and saves.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MicrosoftUpdate',
        Justification = 'The switch only selects the parameter set.')]
    [CmdletBinding(DefaultParameterSetName = 'Microsoft')]
    param (
        # IUpdateServerConfiguration of the node, from GetConfiguration().
        [Parameter(Mandatory)]
        $Config,

        # Sync from Microsoft Update.
        [Parameter(Mandatory, ParameterSetName = 'Microsoft')]
        [switch] $MicrosoftUpdate,

        # FQDN of the Upstream to be a Replica of.
        [Parameter(Mandatory, ParameterSetName = 'Upstream')]
        [string] $UpstreamFqdn,

        # SSL port on the Upstream. 8531 means SSL, any other port plain http. Default 8531.
        [Parameter(ParameterSetName = 'Upstream')]
        [int] $UpstreamPort = 8531
    )

    if ($PSCmdlet.ParameterSetName -eq 'Upstream') {
        $endpoint = Get-WsusEndpoint -Fqdn $UpstreamFqdn -Port $UpstreamPort

        $Config.SyncFromMicrosoftUpdate = $false
        $Config.UpstreamWsusServerName = $endpoint.Fqdn
        $Config.UpstreamWsusServerPortNumber = $endpoint.Port
        $Config.UpstreamWsusServerUseSsl = $endpoint.UseSsl
        $Config.IsReplicaServer = $true
        $Config.GetContentFromMU = $false
        $Config.UseProxy = $false
    }
    else {
        # WSUS refuses SyncFromMicrosoftUpdate = true while the node is a replica, so leave replica mode first.
        $Config.IsReplicaServer = $false
        $Config.SyncFromMicrosoftUpdate = $true
        $Config.UpstreamWsusServerName = ''
        # The API rejects 0; 80 is its default and is ignored while SyncFromMicrosoftUpdate is true.
        $Config.UpstreamWsusServerPortNumber = 80
        $Config.GetContentFromMU = $true
    }

    $Config.DownloadExpressPackages = $false          # express files balloon content size
    $Config.HostBinariesOnMicrosoftUpdate = $false    # clients pull content from WSUS
    $Config.DownloadUpdateBinariesAsNeeded = $true    # download content only once approved
    $Config.TargetingMode = 'Client'                  # groups come from client policy
}
