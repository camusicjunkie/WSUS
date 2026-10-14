BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Disable-WsusApprovalRule' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Rules @(
            @{ Name = 'Critical and Security - Packer'; Enabled = $true },
            @{ Name = 'Definitions'; Enabled = $true }
        )
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
    }

    It 'turns every rule off by default and reports each as changed' {
        $result = Disable-WsusApprovalRule

        $result.Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'WSUS.ApprovalRule'
        $result.Enabled | Should -Not -Contain $true
        $result.Changed | Should -Not -Contain $false
        $script:fake.Rules.Enabled | Should -Not -Contain $true
        $script:fake.Calls | Should -Contain 'Rule.Save:Definitions'
    }

    It 'only touches rules matching -Name, wildcards allowed' {
        $result = Disable-WsusApprovalRule -Name 'Crit*'

        @($result).Count | Should -Be 1
        $result.Name | Should -Be 'Critical and Security - Packer'
        ($script:fake.Rules | Where-Object Name -eq 'Definitions').Enabled | Should -BeTrue
    }

    It 'skips a rule that is already off: reported unchanged, not saved' {
        $script:fake = New-FakeWsusServer -Rules @(
            @{ Name = 'Definitions'; Enabled = $false },
            @{ Name = 'Packer'; Enabled = $true }
        )

        $result = Disable-WsusApprovalRule

        ($result | Where-Object Name -eq 'Definitions').Changed | Should -BeFalse
        ($result | Where-Object Name -eq 'Packer').Changed | Should -BeTrue
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Definitions'
    }

    It 'changes nothing under -WhatIf but still reports the rules' {
        $result = Disable-WsusApprovalRule -WhatIf

        @($result).Count | Should -Be 2
        $result.Changed | Should -Not -Contain $true
        $script:fake.Rules.Enabled | Should -Not -Contain $false
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Definitions'
    }

    It 'throws on a replica, naming the node' {
        $script:fake = New-FakeWsusServer -IsReplica $true -Name 'wsus02.contoso.local'

        { Disable-WsusApprovalRule -WsusServer 'wsus02.contoso.local' } | Should -Throw "*'wsus02.contoso.local' is a Replica*"
    }

    It 'takes rule names from the pipeline' {
        $result = 'Definitions' | Disable-WsusApprovalRule

        @($result).Count | Should -Be 1
        $result.Name | Should -Be 'Definitions'
    }
}
