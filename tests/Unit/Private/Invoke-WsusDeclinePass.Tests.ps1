BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Invoke-WsusDeclinePass' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Updates @(
            @{ Title = 'Update for Windows 11 ARM64 (KB1)'; Kb = @('1') }
            @{ Title = 'Update for Windows 11 x64 (KB2)'; Kb = @('2') }
            @{ Title = 'Old superseded update (KB3)'; Kb = @('3'); IsSuperseded = $true; ArrivalDate = [datetime]::UtcNow.AddDays(-90) }
            @{ Title = 'New superseded update (KB4)'; Kb = @('4'); IsSuperseded = $true; ArrivalDate = [datetime]::UtcNow.AddDays(-5) }
            @{ Title = 'Already declined ARM64 (KB5)'; Kb = @('5'); IsDeclined = $true }
        )
    }

    It 'declines updates whose title matches the regular expression and returns their titles' {
        $result = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'ARM64'
        }

        @($result) | Should -Be @('Update for Windows 11 ARM64 (KB1)')
        $script:fake.Calls | Should -Contain 'Update.Decline:Update for Windows 11 ARM64 (KB1)'
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Update for Windows 11 x64 (KB2)'
    }

    It 'skips updates that are already declined' {
        InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            $null = Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'ARM64'
        }

        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Already declined ARM64 (KB5)'
    }

    It 'declines only superseded updates older than -SupersededOlderThan' {
        $result = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'NoSuchTitle' -SupersededOlderThan ([datetime]::UtcNow.AddDays(-30))
        }

        @($result) | Should -Be @('Old superseded update (KB3)')
    }

    It 'declines no superseded update when -SupersededOlderThan is not given' {
        $result = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'NoSuchTitle'
        }

        @($result) | Should -BeNullOrEmpty
    }

    It 'passes -ArrivedSince to the search scope' {
        $since = [datetime]::UtcNow.AddDays(-7)
        InModuleScope WSUS -Parameters @{ Wsus = $script:fake; Since = $since } {
            param ($Wsus, $Since)
            $null = Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'ARM64' -ArrivedSince $Since
        }

        $script:fake.LastScope.FromArrivalDate | Should -Be $since
    }

    It 'declines nothing and returns nothing under -WhatIf' {
        $result = InModuleScope WSUS -Parameters @{ Wsus = $script:fake } {
            param ($Wsus)
            Invoke-WsusDeclinePass -Wsus $Wsus -Pattern 'ARM64' -WhatIf
        }

        @($result) | Should -BeNullOrEmpty
        @($script:fake.Calls | Where-Object { $_ -like 'Update.Decline:*' }) | Should -BeNullOrEmpty
    }
}
