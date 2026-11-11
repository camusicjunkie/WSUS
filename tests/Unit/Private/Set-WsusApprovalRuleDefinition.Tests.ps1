BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusApprovalRuleDefinition' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -ComputerGroups 'All Computers', 'Pilot', 'Servers'
    }

    It 'creates a new rule that is off, with the named classifications and groups' {
        $rule = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Set-WsusApprovalRuleDefinition -Wsus $Wsus -Name 'Auto - Test' -ClassificationTitle 'Critical Updates', 'Security Updates' -GroupName 'Pilot'
        }

        $script:fake.Calls | Should -Contain 'CreateRule:Auto - Test'
        $rule.Enabled | Should -BeFalse
        $rule.Classifications | Should -Be @('Critical Updates', 'Security Updates')
        $rule.Groups | Should -Be @('Pilot')
        $script:fake.Calls | Should -Contain 'Rule.Save:Auto - Test'
    }

    It 'updates an existing rule and keeps its on/off state' {
        $script:fake = New-FakeWsusServer -ComputerGroups 'Pilot', 'Servers' -Rules @(@{ Name = 'Auto - Test'; Enabled = $true })

        $rule = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Set-WsusApprovalRuleDefinition -Wsus $Wsus -Name 'Auto - Test' -ClassificationTitle 'Definition Updates' -GroupName 'Servers'
        }

        $script:fake.Calls | Should -Not -Contain 'CreateRule:Auto - Test'
        $rule.Enabled | Should -BeTrue
        $rule.Groups | Should -Be @('Servers')
    }

    It 'throws on an unknown classification and creates no rule' {
        {
            InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
                param ($Wsus)
                Set-WsusApprovalRuleDefinition -Wsus $Wsus -Name 'Auto - Test' -ClassificationTitle 'Critcal Updates' -GroupName 'Pilot'
            }
        } | Should -Throw '*Classification not found*Critcal Updates*'
        $script:fake.Calls | Should -Not -Contain 'CreateRule:Auto - Test'
    }

    It 'throws on an unknown group and creates no rule' {
        {
            InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
                param ($Wsus)
                Set-WsusApprovalRuleDefinition -Wsus $Wsus -Name 'Auto - Test' -ClassificationTitle 'Critical Updates' -GroupName 'Pilot', 'Nowhere'
            }
        } | Should -Throw '*Computer group not found*Nowhere*'
        $script:fake.Calls | Should -Not -Contain 'CreateRule:Auto - Test'
    }
}
