BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusReplicaConfig' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local'
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus02.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Test-WsusUpstreamReachable { $true }
    }

    Context 'configuring a fresh node' {
        It 'makes the node a replica of the upstream and returns a ReplicaConfig' {
            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false

            $config = $script:fake.Config
            $config.IsReplicaServer | Should -BeTrue
            $config.UpstreamWsusServerName | Should -Be 'wsus01.contoso.local'
            $config.UpstreamWsusServerPortNumber | Should -Be 8531
            $script:fake.Calls | Should -Contain 'Config.Save'

            $result.PSObject.TypeNames | Should -Contain 'WSUS.ReplicaConfig'
            $result.Server | Should -Be 'wsus02.contoso.local'
            $result.Upstream | Should -Be 'wsus01.contoso.local:8531'
            $result.SyncStarted | Should -BeFalse
            $result.NextStep | Should -BeLike '*Get-WsusNodeStatus*Register-WsusMaintenanceTask*'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Role'
        }
    }

    Context 'upstream port' {
        It 'passes -UpstreamPort to the probe and the configuration' {
            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -UpstreamPort 8530 -Confirm:$false

            Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 1 -ParameterFilter { $Port -eq 8530 }
            $script:fake.Config.UpstreamWsusServerPortNumber | Should -Be 8530
            $result.Upstream | Should -Be 'wsus01.contoso.local:8530'
        }
    }

    Context 'sync schedule' {
        It 'saves the schedule and reports it' {
            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -SyncsPerDay 4 -FirstSyncUtcHour 6 -Confirm:$false

            $sub = $script:fake.Subscription
            $sub.SynchronizeAutomaticallyTimeOfDay | Should -Be ([timespan]::FromHours(6))
            $sub.NumberOfSynchronizationsPerDay | Should -Be 4
            $script:fake.Calls | Should -Contain 'Subscription.Save'
            $result.Schedule | Should -Be '4 syncs/day from 06:00 UTC'
        }

        It 'does not start a sync unless -SyncNow is given' {
            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false | Out-Null

            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
        }

        It 'starts a sync with -SyncNow' {
            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -SyncNow -Confirm:$false

            $script:fake.Calls | Should -Contain 'StartSynchronization'
            $result.SyncStarted | Should -BeTrue
        }

        It 'rejects an out-of-range -SyncsPerDay' {
            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -SyncsPerDay 25 } | Should -Throw
        }
    }

    Context 'guards' {
        It 'refuses when the upstream is the node itself' {
            { Set-WsusReplicaConfig -UpstreamFqdn 'WSUS02.contoso.local' -Confirm:$false } | Should -Throw '*itself*'
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
        }

        It 'refuses an Upstream with custom computer groups unless -Force' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -ComputerGroups 'All Computers', 'Unassigned Computers', 'Pilot'

            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false } | Should -Throw '*-Force*'
            $script:fake.Calls | Should -Not -Contain 'Config.Save'

            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Force -Confirm:$false | Out-Null
            $script:fake.Config.IsReplicaServer | Should -BeTrue
        }

        It 'refuses an Upstream with custom approval rules unless -Force' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -Rules @(@{ Name = 'Default Automatic Approval Rule'; Enabled = $true }, @{ Name = 'Auto - Servers'; Enabled = $true })

            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false } | Should -Throw '*-Force*'
        }

        It 'refuses an Upstream with approvals unless -Force' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -ApprovalCount 3

            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false } | Should -Throw '*-Force*'
        }

        It 'says the state is kept and points at a clean node when refusing' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -ApprovalCount 3

            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false } | Should -Throw '*stays in its database*clean node*'
        }

        It 'turns the approval rules off, warns and reports them when demoting with -Force' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -Rules @(
                @{ Name = 'Default Automatic Approval Rule'; Enabled = $false },
                @{ Name = 'Auto - Servers'; Enabled = $true },
                @{ Name = 'Auto - Definitions'; Enabled = $false })

            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Force -Confirm:$false -WarningVariable warnings 3>$null

            ($script:fake.Rules | Where-Object Name -EQ 'Auto - Servers').Enabled | Should -BeFalse
            $script:fake.Calls | Should -Not -Contain 'Rule.Save:Default Automatic Approval Rule'
            $result.DisabledRules | Should -Be @('Auto - Servers')
            $warnings | Should -BeLike '*ApprovedUpdateCount*'
            $script:fake.Config.IsReplicaServer | Should -BeTrue
        }

        It 'leaves the rules on under -WhatIf' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -Rules @(@{ Name = 'Auto - Servers'; Enabled = $true })

            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Force -WhatIf 3>$null | Out-Null

            $script:fake.Rules[0].Enabled | Should -BeTrue
        }

        It 'does not warn or disable anything on a fresh node' {
            $result = Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Force -Confirm:$false -WarningVariable warnings

            $warnings | Should -BeNullOrEmpty
            $result.DisabledRules | Should -BeNullOrEmpty
        }

        It 'reconfigures an existing replica without needing -Force' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -IsReplica $true -UpstreamName 'old.contoso.local' -ComputerGroups 'All Computers', 'Pilot'

            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false | Out-Null

            $script:fake.Config.UpstreamWsusServerName | Should -Be 'wsus01.contoso.local'
        }
    }

    Context 'upstream probe' {
        It 'fails before saving when the upstream does not answer' {
            Mock -ModuleName WSUS Test-WsusUpstreamReachable { $false }

            { Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Confirm:$false } | Should -Throw '*wsus01.contoso.local*'
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
            Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 1 -ParameterFilter { $Fqdn -eq 'wsus01.contoso.local' -and $Port -eq 8531 }
        }

        It 'skips the probe with -Force' {
            Mock -ModuleName WSUS Test-WsusUpstreamReachable { $false }

            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -Force -Confirm:$false | Out-Null

            Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 0
            $script:fake.Config.IsReplicaServer | Should -BeTrue
        }
    }

    Context '-WhatIf' {
        It 'saves nothing, starts no sync and skips the probe' {
            Set-WsusReplicaConfig -UpstreamFqdn 'wsus01.contoso.local' -SyncNow -WhatIf | Out-Null

            $script:fake.Config.IsReplicaServer | Should -BeFalse
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
            $script:fake.Calls | Should -Not -Contain 'Subscription.Save'
            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
            Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 0
        }
    }
}
