function Install-WsusNode {
    <#
    .SYNOPSIS
        Installs WSUS with the Windows Internal Database (WID) and runs postinstall on this node.
    .DESCRIPTION
        Local-only: run it on each node (use Invoke-Command for remote nodes). Each node gets its own
        WID database and content folder. Installs the WSUS role with WID, the WSUS API and the IIS
        PowerShell module, creates the content folder, runs wsusutil postinstall and opens 8530/8531.

        Re-run safe: postinstall is skipped when the node already looks post-installed (the local
        plain-port WSUS API answers and its content path matches); -Force runs it again. Feature
        install, folder and firewall rule are check-then-act. Never reboots; RestartNeeded says
        whether a restart is required before Set-WsusNodeConfig.
    .PARAMETER ContentPath
        Local folder for update content. Use a dedicated data disk of about 100 GB.
    .PARAMETER Force
        Run wsusutil postinstall even when the node already looks post-installed.
    .EXAMPLE
        Install-WsusNode -ContentPath 'D:\WSUS' -WhatIf
    .OUTPUTS
        WSUS.NodeInstall
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.NodeInstall')]
    param (
        [ValidatePattern('^[A-Za-z]:\\')]
        [string] $ContentPath = 'D:\WSUS',

        [switch] $Force
    )

    $features = 'UpdateServices-WidDB', 'UpdateServices-Services', 'UpdateServices-API', 'Web-Scripting-Tools'
    Assert-WsusPrerequisite -Administrator -Feature $features

    if ((Get-WindowsFeature -Name 'UpdateServices-DB').Installed) {
        throw 'The SQL database option (UpdateServices-DB) is installed. Remove it before installing WID.'
    }

    $restartNeeded = $false
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install WSUS with WID')) {
        $installed = Install-WindowsFeature -Name $features -IncludeManagementTools
        $restartNeeded = "$($installed.RestartNeeded)" -eq 'Yes'
    }

    if (-not (Test-Path -LiteralPath $ContentPath) -and $PSCmdlet.ShouldProcess($ContentPath, 'Create folder')) {
        $null = New-Item -ItemType Directory -Path $ContentPath
    }

    $postInstalled = $false
    try {
        $existing = Get-WsusServer -Name (Get-WsusLocalFqdn) -PortNumber 8530 -ErrorAction Stop
        $postInstalled = $existing.GetConfiguration().LocalContentCachePath -eq $ContentPath
    }
    catch {
        Write-Verbose "Node does not answer on the plain port yet: $($_.Exception.Message)"
    }
    if ((-not $postInstalled -or $Force) -and
        $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Run wsusutil postinstall (content: $ContentPath)")) {
        Invoke-WsusUtil -ArgumentList 'postinstall', "CONTENT_DIR=$ContentPath"
    }

    if (-not (Get-NetFirewallRule -DisplayName 'WSUS 8530/8531' -ErrorAction SilentlyContinue)) {
        $firewallParams = @{
            DisplayName = 'WSUS 8530/8531'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = 8530, 8531
            Action      = 'Allow'
        }
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Create firewall rule for 8530/8531')) {
            $null = New-NetFirewallRule @firewallParams
        }
    }

    [PSCustomObject] @{
        PSTypeName    = 'WSUS.NodeInstall'
        ComputerName  = $env:COMPUTERNAME
        Database      = 'WID'
        ContentPath   = $ContentPath
        RestartNeeded = $restartNeeded
        NextStep      = if ($restartNeeded) { 'Restart first, then run Set-WsusNodeConfig on this node' } else { 'Run Set-WsusNodeConfig on this node' }
    }
}
