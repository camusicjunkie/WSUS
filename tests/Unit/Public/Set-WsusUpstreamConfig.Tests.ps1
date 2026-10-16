BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusUpstreamConfig' {
    BeforeEach {
        $script:allProducts = 'Windows 11', 'Microsoft Server Operating System-21H2', 'Microsoft Server Operating System-24H2', 'Microsoft Defender Antivirus'
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -Categories $script:allProducts
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Assert-WsusPrerequisite { }
        Mock -ModuleName WSUS Start-Sleep { }
        Mock -ModuleName WSUS Write-Progress { }
    }

    Context 'server configuration' {
        It 'syncs from Microsoft Update by default and returns a WSUS.UpstreamConfig' {
            $result = Set-WsusUpstreamConfig

            $result.PSObject.TypeNames | Should -Contain 'WSUS.UpstreamConfig'
            $result.Server | Should -Be 'wsus01.contoso.local'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Upstream'
            $script:fake.Config.SyncFromMicrosoftUpdate | Should -BeTrue
            $script:fake.Config.TargetingMode | Should -Be 'Client'    # proves Set-WsusSyncSource ran; the flags are tested there
            $script:fake.Calls | Should -Contain 'Config.Save'
        }

        It 'throws on a replica, points at ConvertTo-WsusUpstream and changes nothing' {
            $script:fake = New-FakeWsusServer -IsReplica $true
            { Set-WsusUpstreamConfig } | Should -Throw '*ConvertTo-WsusUpstream*'
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
        }

        It 'always syncs from Microsoft Update: it has no parameter for another upstream' {
            $parameters = (Get-Command -Name Set-WsusUpstreamConfig).Parameters.Keys
            $parameters | Should -Not -Contain 'UpstreamServer'
            $parameters | Should -Not -Contain 'UpstreamPort'
        }

        It 'uses a proxy only when -ProxyHost is given' {
            Set-WsusUpstreamConfig | Out-Null
            $script:fake.Config.UseProxy | Should -BeFalse

            Set-WsusUpstreamConfig -ProxyHost 'proxy.corp.local' -ProxyPort 3128 | Out-Null
            $script:fake.Config.UseProxy | Should -BeTrue
            $script:fake.Config.ProxyName | Should -Be 'proxy.corp.local'
            $script:fake.Config.ProxyServerPort | Should -Be 3128
        }

        It 'applies the language and approval-refresh settings' {
            Set-WsusUpstreamConfig | Out-Null

            $script:fake.Config.AllUpdateLanguagesEnabled | Should -BeFalse
            $script:fake.Config.EnabledUpdateLanguages | Should -Be @('en')
            $script:fake.Config.AutoApproveWsusInfrastructureUpdates | Should -BeTrue
            $script:fake.Config.AutoRefreshUpdateApprovals | Should -BeTrue
            $script:fake.Config.AutoRefreshUpdateApprovalsDeclineExpired | Should -BeTrue
        }

        It 'saves nothing under -WhatIf' {
            Set-WsusUpstreamConfig -WhatIf
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
        }
    }

    Context 'products, classifications and schedule' {
        It 'subscribes to the default products and classifications and saves the schedule' {
            $result = Set-WsusUpstreamConfig

            $sub = $script:fake.Subscription
            $sub.UpdateCategories | Should -Be $script:allProducts
            $sub.UpdateClassifications | Should -Be @('Critical Updates', 'Security Updates', 'Definition Updates')
            $sub.NumberOfSynchronizationsPerDay | Should -Be 2
            $sub.SynchronizeAutomaticallyTimeOfDay | Should -Be ([timespan]::FromHours(2))
            $script:fake.Calls | Should -Contain 'Subscription.Save'
            $result.Products | Should -Be $script:allProducts
            $result.Classification | Should -Be 'Critical Updates, Security Updates, Definition Updates'
        }

        It 'honours -Product, -Classification, -SyncsPerDay and -FirstSyncUtcHour' {
            Set-WsusUpstreamConfig -Product 'Windows 11' -Classification 'Security Updates' -SyncsPerDay 4 -FirstSyncUtcHour 5 | Out-Null

            $sub = $script:fake.Subscription
            $sub.UpdateCategories | Should -Be @('Windows 11')
            $sub.UpdateClassifications | Should -Be @('Security Updates')
            $sub.NumberOfSynchronizationsPerDay | Should -Be 4
            $sub.SynchronizeAutomaticallyTimeOfDay | Should -Be ([timespan]::FromHours(5))
        }

        It 'validates -SyncsPerDay and -FirstSyncUtcHour' {
            { Set-WsusUpstreamConfig -SyncsPerDay 25 } | Should -Throw
            { Set-WsusUpstreamConfig -FirstSyncUtcHour 24 } | Should -Throw
        }

        It 'does not run a category sync when every product title is already known' {
            Set-WsusUpstreamConfig | Out-Null
            $script:fake.Calls | Should -Not -Contain 'StartSynchronizationForCategoryOnly'
        }

        It 'runs a category-only sync and waits when the category list is empty' {
            $script:fake = New-FakeWsusServer -CategoriesAfterSync $script:allProducts
            $result = Set-WsusUpstreamConfig

            $script:fake.Calls | Should -Contain 'StartSynchronizationForCategoryOnly'
            $script:fake.Subscription.GetSynchronizationStatus() | Should -Be 'NotProcessing'
            $result.Products | Should -Be $script:allProducts
        }

        It 'runs a category-only sync when a requested product is not in the list' {
            $script:fake = New-FakeWsusServer -Categories 'Windows 11' -CategoriesAfterSync 'Windows 11', 'Office 2019'
            Set-WsusUpstreamConfig -Product 'Office 2019' | Out-Null

            $script:fake.Calls | Should -Contain 'StartSynchronizationForCategoryOnly'
            $script:fake.Subscription.UpdateCategories | Should -Be @('Office 2019')
        }

        It 'throws naming the missing titles, pointing at Get-WsusProduct, before saving the subscription' {
            { Set-WsusUpstreamConfig -Product 'Windows 11', 'Windows 99', 'Nope' } |
                Should -Throw "*Windows 99*Nope*Get-WsusProduct*"
            $script:fake.Calls | Should -Not -Contain 'Subscription.Save'
        }

        It 'starts no sync and saves no subscription under -WhatIf' {
            $script:fake = New-FakeWsusServer
            Set-WsusUpstreamConfig -WhatIf
            $script:fake.Calls | Should -Not -Contain 'StartSynchronizationForCategoryOnly'
            $script:fake.Calls | Should -Not -Contain 'Subscription.Save'
        }
    }

    Context 'computer groups' {
        It 'creates the missing default groups and reports them' {
            $result = Set-WsusUpstreamConfig

            $script:fake.Calls | Should -Contain 'CreateGroup:Packer'
            $script:fake.Calls | Should -Contain 'CreateGroup:VDI'
            @($script:fake.GetComputerTargetGroups().Name) | Should -Contain 'Workstations'
            $result.Groups | Should -Be 'Packer, Pilot, Workstations, Servers, VDI'
        }

        It 'creates only the groups that are missing, so a re-run creates none' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -ComputerGroups 'All Computers', 'Pilot'
            Set-WsusUpstreamConfig -ComputerGroup 'Pilot', 'Servers' | Out-Null

            $script:fake.Calls | Should -Contain 'CreateGroup:Servers'
            $script:fake.Calls | Should -Not -Contain 'CreateGroup:Pilot'
        }

        It 'creates no group under -WhatIf' {
            Set-WsusUpstreamConfig -WhatIf
            @($script:fake.Calls | Where-Object { $_ -like 'CreateGroup:*' }) | Should -BeNullOrEmpty
        }
    }

    Context 'approval rules' {
        It 'creates the two auto-approval rules off, with their classifications and groups' {
            $result = Set-WsusUpstreamConfig

            $critSec = $script:fake.GetInstallApprovalRules() | Where-Object Name -EQ 'Auto - Critical and Security'
            $critSec.Enabled | Should -BeFalse
            $critSec.Classifications | Should -Be @('Critical Updates', 'Security Updates')
            $critSec.Groups | Should -Be @('Packer', 'Pilot')
            $definition = $script:fake.GetInstallApprovalRules() | Where-Object Name -EQ 'Auto - Definition Updates'
            $definition.Enabled | Should -BeFalse
            $definition.Classifications | Should -Be @('Definition Updates')
            $definition.Groups | Should -Be @('Packer', 'Pilot', 'Workstations', 'VDI')
            $result.Rules | Should -Be 'Auto - Critical and Security (Off); Auto - Definition Updates (Off)'
        }

        It 'honours -CritSecGroup and -DefinitionGroup' {
            Set-WsusUpstreamConfig -CritSecGroup 'Pilot' -DefinitionGroup 'Servers' | Out-Null

            ($script:fake.GetInstallApprovalRules() | Where-Object Name -EQ 'Auto - Critical and Security').Groups | Should -Be @('Pilot')
            ($script:fake.GetInstallApprovalRules() | Where-Object Name -EQ 'Auto - Definition Updates').Groups | Should -Be @('Servers')
        }

        It 'leaves an existing rule in its current on/off state' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Auto - Critical and Security'; Enabled = $true }
                @{ Name = 'Auto - Definition Updates'; Enabled = $false }
            )
            $result = Set-WsusUpstreamConfig

            $result.Rules | Should -Be 'Auto - Critical and Security (On); Auto - Definition Updates (Off)'
            $script:fake.Calls | Should -Not -Contain 'CreateRule:Auto - Critical and Security'
        }

        It 'disables the stock Default Automatic Approval Rule' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Default Automatic Approval Rule'; Enabled = $true }
            )
            Set-WsusUpstreamConfig | Out-Null

            ($script:fake.GetInstallApprovalRules() | Where-Object Name -EQ 'Default Automatic Approval Rule').Enabled | Should -BeFalse
        }

        It 'no longer has -EnableRules' {
            (Get-Command Set-WsusUpstreamConfig).Parameters.Keys | Should -Not -Contain 'EnableRules'
        }

        It 'creates no rule under -WhatIf' {
            Set-WsusUpstreamConfig -WhatIf
            @($script:fake.Calls | Where-Object { $_ -like 'CreateRule:*' }) | Should -BeNullOrEmpty
        }
    }

    Context '-ApplyRulesNow' {
        It 'applies only the rules that are currently enabled' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Auto - Critical and Security'; Enabled = $true }
                @{ Name = 'Auto - Definition Updates'; Enabled = $false }
            )
            Set-WsusUpstreamConfig -ApplyRulesNow | Out-Null

            $script:fake.Calls | Should -Contain 'Rule.Apply:Auto - Critical and Security'
            $script:fake.Calls | Should -Not -Contain 'Rule.Apply:Auto - Definition Updates'
        }

        It 'warns and applies nothing when every rule is off' {
            Set-WsusUpstreamConfig -ApplyRulesNow -WarningVariable warn -WarningAction SilentlyContinue | Out-Null

            $warn | Should -Not -BeNullOrEmpty
            @($script:fake.Calls | Where-Object { $_ -like 'Rule.Apply:*' }) | Should -BeNullOrEmpty
        }

        It 'applies nothing without the switch' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Auto - Critical and Security'; Enabled = $true }
            )
            Set-WsusUpstreamConfig | Out-Null
            @($script:fake.Calls | Where-Object { $_ -like 'Rule.Apply:*' }) | Should -BeNullOrEmpty
        }

        It 'applies nothing under -WhatIf' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Auto - Critical and Security'; Enabled = $true }
            )
            Set-WsusUpstreamConfig -ApplyRulesNow -WhatIf
            @($script:fake.Calls | Where-Object { $_ -like 'Rule.Apply:*' }) | Should -BeNullOrEmpty
        }
    }

    Context 'NextStep' {
        It 'walks through the first sync and cleanup while every rule is off' {
            (Set-WsusUpstreamConfig).NextStep |
                Should -Be 'Start-WsusSync -Wait, then Invoke-WsusMaintenance -SupersededAgeDays 0, then Enable-WsusApprovalRule'
        }

        It 'is just a sync once a rule is on' {
            $script:fake = New-FakeWsusServer -Categories $script:allProducts -Rules @(
                @{ Name = 'Auto - Critical and Security'; Enabled = $true }
            )
            (Set-WsusUpstreamConfig).NextStep | Should -Be 'Start-WsusSync -Wait'
        }
    }
}
