BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusSyncSchedule' {
    BeforeEach {
        $script:fake = New-FakeWsusServer
        $script:subscription = $script:fake.GetSubscription()
    }

    It 'turns automatic sync on and sets the first hour and the syncs per day' {
        InModuleScope WSUS -Parameters @{ Sub = $script:subscription } {
            param ($Sub)
            Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay 4 -FirstSyncUtcHour 5
        }

        $script:subscription.SynchronizeAutomatically | Should -BeTrue
        $script:subscription.SynchronizeAutomaticallyTimeOfDay | Should -Be (New-TimeSpan -Hours 5)
        $script:subscription.NumberOfSynchronizationsPerDay | Should -Be 4
    }

    It 'does not save the subscription; the caller does' {
        InModuleScope WSUS -Parameters @{ Sub = $script:subscription } {
            param ($Sub)
            Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay 1 -FirstSyncUtcHour 0
        }

        $script:fake.Calls | Should -Not -Contain 'Subscription.Save'
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an hour above 23'; Syncs = 1; Hour = 24 }
        @{ Name = 'zero syncs per day'; Syncs = 0; Hour = 0 }
        @{ Name = 'more than 24 syncs per day'; Syncs = 25; Hour = 0 }
    ) {
        {
            InModuleScope WSUS -Parameters @{ Sub = $script:subscription; Syncs = $Syncs; Hour = $Hour } {
                param ($Sub, $Syncs, $Hour)
                Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay $Syncs -FirstSyncUtcHour $Hour
            }
        } | Should -Throw
    }
}
