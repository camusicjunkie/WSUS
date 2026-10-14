function Set-WsusNodeConfig {
    <#
    .SYNOPSIS
        Puts this WSUS node into its steady state: certificate, admin access, pool tuning and SSL.
    .DESCRIPTION
        Local-only: run it on each node after Install-WsusNode (use Invoke-Command for remote nodes).
        Safe to re-run at any time, for example after a WSUS repair, a re-run of postinstall or a
        certificate renewal.

        - Validates this node's certificate (SANs: VIP FQDN and this node's FQDN) before touching anything
        - Adds the admin resource group to the local 'WSUS Administrators' group
        - Tunes WsusPool and ClientWebService for thousands of clients
        - Binds the certificate to 8531 and requires SSL on the web services (update content stays on
          HTTP 8530 by design)
        - Always restarts IIS and WsusService and waits 20 seconds (there is no -NoRestart), then
          self-tests through the WSUS API over SSL

        Under -WhatIf nothing is changed and nothing is returned. A failed self-test writes a
        non-terminating error and still returns the result object. The result has no Role: a fresh
        node has no role until Set-WsusUpstreamConfig or Set-WsusReplicaConfig runs.
    .PARAMETER SslCertThumbprint
        Thumbprint of THIS node's certificate in Cert:\LocalMachine\My. SANs must include the VIP FQDN
        and this node's FQDN.
    .PARAMETER VipFqdn
        FQDN clients use through the NetScaler, for example wsus.corp.local.
    .PARAMETER AdminResourceGroup
        Resource group added to the local 'WSUS Administrators' group.
    .PARAMETER Domain
        NetBIOS domain name of the admin resource group. Defaults to this machine's domain.
    .EXAMPLE
        Set-WsusNodeConfig -SslCertThumbprint '0123456789ABCDEF0123456789ABCDEF01234567' -VipFqdn 'wsus.corp.local' -WhatIf
    .OUTPUTS
        WSUS.NodeConfig
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.NodeConfig')]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9A-Fa-f]{40}$')]
        [string] $SslCertThumbprint,

        [Parameter(Mandatory)]
        [string] $VipFqdn,

        [string] $AdminResourceGroup = 'res.srv.wsus.admin',

        [string] $Domain = $env:USERDOMAIN
    )

    Assert-WsusPrerequisite -Module WebAdministration, UpdateServices -Administrator

    $nodeFqdn = Get-WsusLocalFqdn
    Test-WsusCertificate -Thumbprint $SslCertThumbprint -RequiredName $VipFqdn, $nodeFqdn

    $adminGroupAccount = '{0}\{1}' -f $Domain, $AdminResourceGroup
    $members = (Get-LocalGroupMember -Group 'WSUS Administrators' -ErrorAction SilentlyContinue).Name
    if ($members -notcontains $adminGroupAccount -and
        $PSCmdlet.ShouldProcess('WSUS Administrators', "Add $adminGroupAccount")) {
        Add-LocalGroupMember -Group 'WSUS Administrators' -Member $adminGroupAccount
    }

    # WsusPool tuning (Microsoft guidance for large client counts)
    $poolSettings = [ordered] @{
        'queueLength'                             = 2000
        'processModel.idleTimeout'                = [TimeSpan]::Zero
        'processModel.pingingEnabled'             = $false
        'recycling.periodicRestart.privateMemory' = 0
        'recycling.periodicRestart.time'          = [TimeSpan]::Zero
        'failure.rapidFailProtection'             = $false
        'failure.loadBalancerCapabilities'        = 'TcpLevel'
    }
    if ($PSCmdlet.ShouldProcess('WsusPool', 'Apply tuning')) {
        Set-WsusAppPoolSetting -Setting $poolSettings
    }

    $webConfig = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\WebServices\ClientWebService\Web.config'
    if ($PSCmdlet.ShouldProcess($webConfig, 'Raise executionTimeout and maxRequestLength')) {
        Grant-WsusFileAccess -Path $webConfig
        if (-not (Test-Path -LiteralPath "$webConfig.orig")) {
            Copy-Item -LiteralPath $webConfig -Destination "$webConfig.orig"
        }
        [xml] $config = Get-Content -LiteralPath $webConfig -Raw
        $httpRuntime = $config.configuration.'system.web'.httpRuntime
        $httpRuntime.SetAttribute('executionTimeout', '7200')
        $httpRuntime.SetAttribute('maxRequestLength', '204800')
        $config.Save($webConfig)
    }

    if ($PSCmdlet.ShouldProcess('WSUS Administration :8531', "Bind certificate $SslCertThumbprint")) {
        Set-WsusSslBinding -Thumbprint $SslCertThumbprint
        Invoke-WsusUtil -ArgumentList 'configuressl', $VipFqdn
    }

    if ($WhatIfPreference) {
        return
    }

    Restart-WsusService -Sleep 20

    try {
        $null = Connect-WsusNode -Server $nodeFqdn -Port 8531
        $selfTest = 'Passed'
    }
    catch {
        $selfTest = "Failed: $($_.Exception.Message)"
        Write-Error -Message 'Self-test failed. Check the certificate binding and event log WAS 5021/5057.'
    }

    [PSCustomObject] @{
        PSTypeName   = 'WSUS.NodeConfig'
        ComputerName = $env:COMPUTERNAME
        Certificate  = $SslCertThumbprint
        SelfTest     = $selfTest
        NextStep     = 'Upstream node: Set-WsusUpstreamConfig. Replica node: Set-WsusReplicaConfig.'
    }
}
