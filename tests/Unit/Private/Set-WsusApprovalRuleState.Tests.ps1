BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusApprovalRuleState' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Rules @(
            @{ Name = 'Auto - Critical and Security'; Enabled = $false },
            @{ Name = 'Auto - Definition Updates'; Enabled = $true },
            @{ Name = 'Default Automatic Approval Rule'; Enabled = $false }
        )
        $script:rules = @($script:fake.GetInstallApprovalRules())
    }

    It 'turns the named rule on, saves it and reports it as changed' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Auto - Critical and Security' -Enabled $true -Server 'wsus01.contoso.local'
        }

        $result.PSObject.TypeNames | Should -Contain 'WSUS.ApprovalRule'
        $result.Server | Should -Be 'wsus01.contoso.local'
        $result.Name | Should -Be 'Auto - Critical and Security'
        $result.Enabled | Should -BeTrue
        $result.Changed | Should -BeTrue
        $script:fake.Calls | Should -Contain 'Rule.Save:Auto - Critical and Security'
    }

    It 'turns the named rule off' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Auto - Definition Updates' -Enabled $false -Server 'wsus01.contoso.local'
        }

        $result.Enabled | Should -BeFalse
        $result.Changed | Should -BeTrue
        ($script:rules | Where-Object Name -eq 'Auto - Definition Updates').Enabled | Should -BeFalse
    }

    It 'skips a rule that is already in the state: reported unchanged, not saved' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Auto - Definition Updates' -Enabled $true -Server 'wsus01.contoso.local'
        }

        $result.Enabled | Should -BeTrue
        $result.Changed | Should -BeFalse
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Auto - Definition Updates'
    }

    It 'matches wildcards and several names, and leaves other rules alone' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Auto - Crit*', 'Auto - Def*' -Enabled $false -Server 'wsus01.contoso.local'
        }

        @($result).Count | Should -Be 2
        ($script:rules | Where-Object Name -like 'Default*').Enabled | Should -BeFalse
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Default Automatic Approval Rule'
    }

    It 'returns nothing when no rule matches' {
        InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Nope*' -Enabled $true -Server 'wsus01.contoso.local'
        } | Should -BeNullOrEmpty
    }

    It 'accepts an empty rule list' {
        InModuleScope WSUS {
            Set-WsusApprovalRuleState -Rule @() -Name '*' -Enabled $true -Server 'wsus01.contoso.local'
        } | Should -BeNullOrEmpty
    }

    It 'changes nothing under -WhatIf but still reports the rules' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            Set-WsusApprovalRuleState -Rule $Rules -Name '*' -Enabled $true -Server 'wsus01.contoso.local' -WhatIf
        }

        @($result).Count | Should -Be 3
        ($script:rules | Where-Object Name -eq 'Auto - Critical and Security').Enabled | Should -BeFalse
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Auto - Critical and Security'
    }

    It 'follows the caller''s -WhatIf preference' {
        $result = InModuleScope WSUS -Parameters @{ Rules = $script:rules } {
            $WhatIfPreference = $true
            Set-WsusApprovalRuleState -Rule $Rules -Name 'Auto - Critical and Security' -Enabled $true -Server 'wsus01.contoso.local'
        }

        $result.Changed | Should -BeFalse
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Auto - Critical and Security'
    }
}
