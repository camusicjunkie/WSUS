BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusRingPlan' {
    BeforeAll {
        $script:plan = InModuleScope WSUS { Get-WsusRingPlan }
    }

    It 'lists the rings in rollout order' {
        $script:plan.Ring | Should -Be @('Packer', 'Pilot', 'Workstations', 'Servers', 'VDI')
    }

    It 'promotes Critical and Security updates from Pilot to Workstations and Servers' {
        $script:plan.Promotion.From | Should -Be 'Pilot'
        $script:plan.Promotion.To | Should -Be @('Workstations', 'Servers')
        $script:plan.Promotion.ClassificationTitle | Should -Be @('Critical Updates', 'Security Updates')
    }

    It 'defines the Critical and Security rule for Packer and Pilot' {
        $rule = $script:plan.Rule.CritSec
        $rule.Name | Should -Be 'Auto - Critical and Security'
        $rule.ClassificationTitle | Should -Be @('Critical Updates', 'Security Updates')
        $rule.GroupName | Should -Be @('Packer', 'Pilot')
    }

    It 'defines the Definition Updates rule for Packer, Pilot, Workstations and VDI' {
        $rule = $script:plan.Rule.Definition
        $rule.Name | Should -Be 'Auto - Definition Updates'
        $rule.ClassificationTitle | Should -Be @('Definition Updates')
        $rule.GroupName | Should -Be @('Packer', 'Pilot', 'Workstations', 'VDI')
    }

    It 'gives each rule only the keys Set-WsusApprovalRuleDefinition takes' {
        foreach ($rule in $script:plan.Rule.Values) {
            $rule.Keys | Sort-Object | Should -Be @('ClassificationTitle', 'GroupName', 'Name')
        }
    }

    Context 'guards' {
        It 'names only rings that exist in every rule' {
            foreach ($rule in $script:plan.Rule.Values) {
                $rule.GroupName | Where-Object { $_ -notin $script:plan.Ring } | Should -BeNullOrEmpty
            }
        }

        It 'promotes between rings that exist' {
            $script:plan.Promotion.From | Should -BeIn $script:plan.Ring
            $script:plan.Promotion.To | Where-Object { $_ -notin $script:plan.Ring } | Should -BeNullOrEmpty
        }

        It 'promotes forward in rollout order' {
            $from = [array]::IndexOf($script:plan.Ring, $script:plan.Promotion.From)
            foreach ($ring in $script:plan.Promotion.To) {
                [array]::IndexOf($script:plan.Ring, $ring) | Should -BeGreaterThan $from
            }
        }

        It 'never promotes to or from VDI, which only gets definitions' {
            $script:plan.Promotion.From | Should -Not -Be 'VDI'
            $script:plan.Promotion.To | Should -Not -Contain 'VDI'
            $script:plan.Rule.CritSec.GroupName | Should -Not -Contain 'VDI'
        }

        It 'promotes the same classifications the Critical and Security rule approves' {
            $script:plan.Promotion.ClassificationTitle | Should -Be $script:plan.Rule.CritSec.ClassificationTitle
        }
    }

    It 'returns a fresh plan on each call, so a caller cannot change the next one' {
        $first = InModuleScope WSUS { Get-WsusRingPlan }
        $first.Rule.CritSec.GroupName = @('Changed')
        $first.Ring[0] = 'Changed'

        $second = InModuleScope WSUS { Get-WsusRingPlan }
        $second.Rule.CritSec.GroupName | Should -Be @('Packer', 'Pilot')
        $second.Ring[0] | Should -Be 'Packer'
    }
}
