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

    It 'rejects an hour outside 0-23 and a count outside 1-24' {
        InModuleScope WSUS -Parameters @{ Sub = $script:subscription } {
            param ($Sub)
            { Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay 1 -FirstSyncUtcHour 24 } | Should -Throw
            { Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay 0 -FirstSyncUtcHour 0 } | Should -Throw
            { Set-WsusSyncSchedule -Subscription $Sub -SyncsPerDay 25 -FirstSyncUtcHour 0 } | Should -Throw
        }
    }
}
