<#
.SYNOPSIS
    Puts a WSUS node into its steady state. Idempotent; safe to re-run at any time.

.DESCRIPTION
    Run on BOTH nodes after script 1.
    - Validates this node's certificate (SANs: VIP FQDN + this node's FQDN)
    - Adds the admin resource group to the local 'WSUS Administrators' group
    - Tunes WsusPool and ClientWebService for thousands of clients
    - Binds the certificate to 8531 and requires SSL on the web services
      (update content stays on HTTP 8530 by design)
    - Self-tests through the WSUS API over SSL

    Re-run after a WSUS repair, a re-run of postinstall, or a certificate renewal.

.EXAMPLE
    $params = @{
        SslCertThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'
        VipFqdn           = 'wsus.corp.local'
    }
    .\2-Set-WsusNodeConfig.ps1 @params -WhatIf
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules WebAdministration, UpdateServices
[CmdletBinding(SupportsShouldProcess)]
param (
    # Thumbprint of THIS node's certificate in Cert:\LocalMachine\My.
    # SANs must include the VIP FQDN and this node's FQDN.
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string] $SslCertThumbprint,

    # FQDN clients use through the NetScaler, for example wsus.corp.local.
    [Parameter(Mandatory)]
    [string] $VipFqdn,

    # Resource group added to the local 'WSUS Administrators' group.
    [string] $AdminResourceGroup = 'res.srv.wsus.admin',

    # NetBIOS domain name of the admin resource group. Defaults to this machine's domain.
    [string] $Domain = $env:USERDOMAIN
)

begin {
    $ErrorActionPreference = 'Stop'

    $siteName = 'WSUS Administration'
    $poolPath = 'IIS:\AppPools\WsusPool'
    $wsusUtil = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\Tools\wsusutil.exe'
    $nodeFqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
    $adminGroupAccount = '{0}\{1}' -f $Domain, $AdminResourceGroup


    function Test-WsusCertificate {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string] $Thumbprint,

            [Parameter(Mandatory)]
            [string[]] $RequiredName
        )

        $cert = Get-Item -LiteralPath "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
        if (-not $cert) {
            throw "Certificate $Thumbprint is not in Cert:\LocalMachine\My"
        }

        $problems = [System.Collections.Generic.List[string]]::new()
        if (-not $cert.HasPrivateKey) {
            $problems.Add('no private key')
        }
        if ($cert.NotAfter -lt (Get-Date).AddDays(30)) {
            $problems.Add(('expires {0:yyyy-MM-dd}' -f $cert.NotAfter))
        }
        if ($cert.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.1') {
            $problems.Add('missing Server Authentication EKU')
        }
        $sanNames = $cert.DnsNameList.Unicode
        foreach ($name in $RequiredName) {
            if ($sanNames -notcontains $name) {
                $problems.Add("SAN missing $name")
            }
        }

        if ($problems.Count -gt 0) {
            throw ('Certificate {0} rejected: {1}' -f $Thumbprint, ($problems -join '; '))
        }
        Write-Verbose -Message "Certificate OK: $($sanNames -join ', ')"
    }
}

end {
    # --- Preflight -----------------------------------------------------------------------------
    Test-WsusCertificate -Thumbprint $SslCertThumbprint -RequiredName $VipFqdn, $nodeFqdn

    # --- Admin access ----------------------------------------------------------------------------
    $sidType = [System.Security.Principal.SecurityIdentifier]
    $adminGroupSid = ([System.Security.Principal.NTAccount]$adminGroupAccount).Translate($sidType).Value
    $memberSid = (Get-LocalGroupMember -Group 'WSUS Administrators' -ErrorAction SilentlyContinue).SID.Value
    if ($memberSid -notcontains $adminGroupSid -and
        $PSCmdlet.ShouldProcess('WSUS Administrators', "Add $adminGroupAccount")) {
        Add-LocalGroupMember -Group 'WSUS Administrators' -Member $adminGroupAccount
    }

    # --- WsusPool tuning (Microsoft guidance for large client counts) ---------------------------
    $poolSettings = [ordered]@{
        'queueLength'                             = 2000
        'processModel.idleTimeout'                = [TimeSpan]::Zero
        'processModel.pingingEnabled'             = $false
        'recycling.periodicRestart.privateMemory' = 0
        'recycling.periodicRestart.time'          = [TimeSpan]::Zero
        'failure.rapidFailProtection'             = $false
        'failure.loadBalancerCapabilities'        = 'TcpLevel'
    }
    if ($PSCmdlet.ShouldProcess('WsusPool', 'Apply tuning')) {
        foreach ($setting in $poolSettings.GetEnumerator()) {
            Set-ItemProperty -Path $poolPath -Name $setting.Key -Value $setting.Value
        }
    }

    # --- ClientWebService web.config ---------------------------------------------------------
    $webConfig = Join-Path -Path $env:ProgramFiles -ChildPath (
        'Update Services\WebServices\ClientWebService\Web.config')
    if ($PSCmdlet.ShouldProcess($webConfig, 'Raise executionTimeout and maxRequestLength')) {
        $null = & "$env:SystemRoot\System32\takeown.exe" /f $webConfig
        $null = & "$env:SystemRoot\System32\icacls.exe" $webConfig /grant '*S-1-5-32-544:F'
        if (-not (Test-Path -LiteralPath "$webConfig.orig")) {
            Copy-Item -LiteralPath $webConfig -Destination "$webConfig.orig"
        }
        [xml]$config = Get-Content -LiteralPath $webConfig -Raw
        $httpRuntime = $config.configuration.'system.web'.httpRuntime
        $httpRuntime.SetAttribute('executionTimeout', '7200')
        $httpRuntime.SetAttribute('maxRequestLength', '204800')
        $config.Save($webConfig)
    }

    # --- SSL on 8531 -------------------------------------------------------------------------
    if ($PSCmdlet.ShouldProcess("$siteName :8531", "Bind certificate $SslCertThumbprint")) {
        $binding = Get-WebBinding -Name $siteName -Protocol https -Port 8531
        if (-not $binding) {
            New-WebBinding -Name $siteName -Protocol https -Port 8531
            $binding = Get-WebBinding -Name $siteName -Protocol https -Port 8531
        }
        try {
            $binding.RemoveSslCertificate()
        } catch {
            Write-Verbose -Message 'No existing certificate on 8531'
        }
        $binding.AddSslCertificate($SslCertThumbprint, 'My')

        $sslServices = 'ApiRemoting30', 'ClientWebService', 'DSSAuthWebService', 'ServerSyncWebService',
            'SimpleAuthWebService'
        foreach ($webService in $sslServices) {
            $sslParams = @{
                PSPath   = 'IIS:\'
                Location = "$siteName/$webService"
                Filter   = 'system.webServer/security/access'
                Name     = 'sslFlags'
                Value    = 'Ssl'
            }
            Set-WebConfigurationProperty @sslParams
        }

        & $wsusUtil configuressl $VipFqdn
        if ($LASTEXITCODE -ne 0) {
            throw "wsusutil configuressl failed with exit code $LASTEXITCODE"
        }
    }

    if ($WhatIfPreference) {
        return
    }

    # --- Restart and self-test ---------------------------------------------------------------
    $null = & "$env:SystemRoot\System32\iisreset.exe"
    Restart-Service -Name WsusService
    Start-Sleep -Seconds 20

    try {
        $wsus = Get-WsusServer -Name $nodeFqdn -PortNumber 8531 -UseSsl
        $role = if ($wsus.GetConfiguration().IsReplicaServer) { 'Replica' } else { 'Autonomous' }
        $selfTest = 'Passed'
    } catch {
        $role = $null
        $selfTest = "Failed: $($_.Exception.Message)"
        $errorMessage = 'Self-test failed. Check the certificate binding and event log WAS 5021/5057.'
        Write-Error -Message $errorMessage -ErrorAction Continue
    }

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Certificate  = $SslCertThumbprint
        Role         = $role
        SelfTest     = $selfTest
        NextStep     = 'WSUS01: run 3-Configure-WsusUpstream.ps1. WSUS02: run 4-Configure-WsusReplica.ps1.'
    }
}
