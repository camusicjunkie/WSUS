<#
.SYNOPSIS
    Installs WSUS with the Windows Internal Database (WID) and runs postinstall on one node.

.DESCRIPTION
    Run on BOTH nodes. Each node gets its own WID database and its own local content folder;
    nothing is shared between them. Script 3 (WSUS01) or script 4 (WSUS02) decides each node's role.

    Installs the WSUS role with WID, the WSUS PowerShell API, and the IIS PowerShell module
    (Web-Scripting-Tools), which Server Core needs for script 2. Then runs wsusutil postinstall
    and opens 8530/8531.

.EXAMPLE
    .\1-Install-WsusNode.ps1 -ContentPath 'D:\WSUS' -WhatIf

.NOTES
    Server Core has no WSUS console. Manage the nodes from an admin workstation with RSAT
    (Windows 11: Add-WindowsCapability -Online -Name 'Rsat.WSUS.Tools~~~~0.0.1.0') or PowerShell.
    Postinstall log: newest tmp*.tmp / WSUS_PostInstall_*.log in the runner's %TEMP%.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param (
    # Local folder for update content. Use a dedicated data disk of about 100 GB.
    [ValidatePattern('^[A-Za-z]:\\')]
    [string] $ContentPath = 'D:\WSUS'
)

begin {
    $ErrorActionPreference = 'Stop'
    $wsusUtil = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\Tools\wsusutil.exe'
}

end {
    if ((Get-WindowsFeature -Name 'UpdateServices-DB').Installed) {
        throw 'The SQL database option (UpdateServices-DB) is installed. Remove it before installing WID.'
    }

    $featureParams = @{
        Name                   = 'UpdateServices-WidDB', 'UpdateServices-Services', 'UpdateServices-API',
            'Web-Scripting-Tools'
        IncludeManagementTools = $true
    }
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install WSUS with WID')) {
        $null = Install-WindowsFeature @featureParams
    }

    if (-not (Test-Path -LiteralPath $ContentPath) -and $PSCmdlet.ShouldProcess($ContentPath, 'Create folder')) {
        $null = New-Item -ItemType Directory -Path $ContentPath
    }

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Run wsusutil postinstall (content: $ContentPath)")) {
        & $wsusUtil postinstall "CONTENT_DIR=$ContentPath"
        if ($LASTEXITCODE -ne 0) {
            throw "wsusutil postinstall failed with exit code $LASTEXITCODE. Check the log in $env:TEMP."
        }
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

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Database     = 'WID'
        ContentPath  = $ContentPath
        NextStep     = 'Run 2-Set-WsusNodeConfig.ps1 on this node.'
    }
}
