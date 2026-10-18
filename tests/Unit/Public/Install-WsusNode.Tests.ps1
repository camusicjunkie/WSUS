BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Install-WsusNode' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -ContentPath 'D:\WSUS'
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WindowsFeature {
            [PSCustomObject] @{ Name = $Name; InstallState = 'Available'; Installed = ($Name -eq 'UpdateServices-DB' -and $false) }
        }
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { throw 'not installed yet' }
        Mock -ModuleName WSUS Install-WindowsFeature { [PSCustomObject] @{ RestartNeeded = 'No'; Success = $true } }
        Mock -ModuleName WSUS Test-Path { $false }
        Mock -ModuleName WSUS New-Item { }
        Mock -ModuleName WSUS Invoke-WsusUtil { }
        Mock -ModuleName WSUS Get-NetFirewallRule { }
        Mock -ModuleName WSUS New-NetFirewallRule { }
    }

    Context 'fresh node' {
        It 'returns a WSUS.NodeInstall naming the next step' {
            $result = Install-WsusNode -ContentPath 'D:\WSUS'

            $result.PSObject.TypeNames | Should -Contain 'WSUS.NodeInstall'
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Database | Should -Be 'WID'
            $result.ContentPath | Should -Be 'D:\WSUS'
            $result.RestartNeeded | Should -BeFalse
            $result.NextStep | Should -Be 'Run Set-WsusNodeConfig on this node'
        }
    }
}

Describe 'Install-WsusNode restart and guards' {
    BeforeEach {
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WindowsFeature {
            [PSCustomObject] @{ Name = $Name; InstallState = 'Available'; Installed = $false }
        }
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { throw 'not installed yet' }
        Mock -ModuleName WSUS Install-WindowsFeature { [PSCustomObject] @{ RestartNeeded = 'Yes'; Success = $true } }
        Mock -ModuleName WSUS Test-Path { $false }
        Mock -ModuleName WSUS New-Item { }
        Mock -ModuleName WSUS Invoke-WsusUtil { }
        Mock -ModuleName WSUS Get-NetFirewallRule { }
        Mock -ModuleName WSUS New-NetFirewallRule { }
    }

    It 'reports RestartNeeded and tells the operator to restart first' {
        $result = Install-WsusNode

        $result.RestartNeeded | Should -BeTrue
        $result.NextStep | Should -Be 'Restart first, then run Set-WsusNodeConfig on this node'
    }

    It 'refuses when the SQL database option is installed' {
        Mock -ModuleName WSUS Get-WindowsFeature {
            [PSCustomObject] @{ Name = $Name; InstallState = 'Installed'; Installed = ($Name -eq 'UpdateServices-DB') }
        }

        { Install-WsusNode } | Should -Throw '*UpdateServices-DB*'
        Should -Invoke -ModuleName WSUS Install-WindowsFeature -Times 0
    }

    It 'throws one error when not elevated, before changing anything' {
        Mock -ModuleName WSUS Test-WsusElevated { $false }

        { Install-WsusNode } | Should -Throw '*elevated*'
        Should -Invoke -ModuleName WSUS Install-WindowsFeature -Times 0
    }
}

Describe 'Install-WsusNode postinstall, folder and firewall' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -ContentPath 'D:\WSUS'
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WindowsFeature {
            [PSCustomObject] @{ Name = $Name; InstallState = 'Available'; Installed = $false }
        }
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { throw 'not installed yet' }
        Mock -ModuleName WSUS Install-WindowsFeature { [PSCustomObject] @{ RestartNeeded = 'No'; Success = $true } }
        Mock -ModuleName WSUS Test-Path { $false }
        Mock -ModuleName WSUS New-Item { }
        Mock -ModuleName WSUS Invoke-WsusUtil { }
        Mock -ModuleName WSUS Get-NetFirewallRule { }
        Mock -ModuleName WSUS New-NetFirewallRule { }
    }

    It 'runs wsusutil postinstall with the content path on a fresh node' {
        $null = Install-WsusNode -ContentPath 'E:\Content'

        Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 1 -ParameterFilter {
            $ArgumentList -contains 'postinstall' -and $ArgumentList -contains 'CONTENT_DIR=E:\Content'
        }
    }

    It 'skips postinstall when the node already answers on the plain port with the same content path' {
        # WSUS reports the WsusContent folder postinstall created under CONTENT_DIR.
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -ContentPath 'D:\WSUS\WsusContent'
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }

        $null = Install-WsusNode -ContentPath 'D:\WSUS'

        Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 0
    }

    It 'runs postinstall on a post-installed node when -Force is given' {
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }

        $null = Install-WsusNode -ContentPath 'D:\WSUS' -Force

        Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 1
    }

    It 'runs postinstall when the existing node uses a different content path' {
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }

        $null = Install-WsusNode -ContentPath 'E:\Other'

        Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 1
    }

    It 'creates the content folder only when it is missing' {
        $null = Install-WsusNode
        Should -Invoke -ModuleName WSUS New-Item -Times 1 -ParameterFilter { $Path -eq 'D:\WSUS' }

        Mock -ModuleName WSUS Test-Path { $true }
        $null = Install-WsusNode
        Should -Invoke -ModuleName WSUS New-Item -Times 1
    }

    It 'creates the firewall rule only when it is missing' {
        $null = Install-WsusNode
        Should -Invoke -ModuleName WSUS New-NetFirewallRule -Times 1 -ParameterFilter { $LocalPort -contains 8531 }

        Mock -ModuleName WSUS Get-NetFirewallRule { [PSCustomObject] @{ DisplayName = 'WSUS 8530/8531' } }
        $null = Install-WsusNode
        Should -Invoke -ModuleName WSUS New-NetFirewallRule -Times 1
    }

    It 'changes nothing under -WhatIf' {
        $null = Install-WsusNode -WhatIf

        Should -Invoke -ModuleName WSUS Install-WindowsFeature -Times 0
        Should -Invoke -ModuleName WSUS New-Item -Times 0
        Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 0
        Should -Invoke -ModuleName WSUS New-NetFirewallRule -Times 0
    }
}
