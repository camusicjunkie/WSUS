BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Invoke-WsusDecline' {
    BeforeEach {
        $now = [datetime]::UtcNow
        $script:fake = New-FakeWsusServer -Updates @(
            @{ Title = 'Cumulative Update for Windows 11 ARM64 (KB1)'; Kb = '1'; ArrivalDate = $now.AddHours(-3) },
            @{ Title = 'Cumulative Update for Windows 11 x64 (KB2)'; Kb = '2'; ArrivalDate = $now.AddHours(-3) }
        )
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Start-WsusLog { 'C:\logs\decline_20261015_0200.log' }
        Mock -ModuleName WSUS Stop-WsusLog { }
    }

    It 'declines recent arrivals that match the pattern and returns a WSUS.DeclineRun' {
        $result = Invoke-WsusDecline

        $result.PSObject.TypeNames | Should -Contain 'WSUS.DeclineRun'
        $result.Server | Should -Be 'wsus01.contoso.local'
        $result.Role | Should -Be 'Upstream'
        $result.Declined | Should -Be 1
        $result.DeclinedUpdates | Should -Be @('Cumulative Update for Windows 11 ARM64 (KB1)')
        $result.Log | Should -Be 'C:\logs\decline_20261015_0200.log'
        $script:fake.Calls | Should -Contain 'Update.Decline:Cumulative Update for Windows 11 ARM64 (KB1)'
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Cumulative Update for Windows 11 x64 (KB2)'
    }

    It 'leaves updates that are already declined, older than -RecentDays, or do not match alone' {
        $now = [datetime]::UtcNow
        $script:fake = New-FakeWsusServer -Updates @(
            @{ Title = 'Old ARM64 update'; Kb = '1'; ArrivalDate = $now.AddDays(-5) },
            @{ Title = 'Declined ARM64 update'; Kb = '2'; IsDeclined = $true },
            @{ Title = 'Recent preview update'; Kb = '3'; ArrivalDate = $now.AddDays(-1) }
        )

        $result = Invoke-WsusDecline -RecentDays 2

        $result.DeclinedUpdates | Should -Be @('Recent preview update')
    }

    It 'uses -DeclinePattern instead of the default' {
        $result = Invoke-WsusDecline -DeclinePattern 'x64'

        $result.DeclinedUpdates | Should -Be @('Cumulative Update for Windows 11 x64 (KB2)')
    }

    It 'does nothing on a replica: no declines, no log, no transcript' {
        $script:fake = New-FakeWsusServer -IsReplica $true -Name 'wsus02.contoso.local'

        $result = Invoke-WsusDecline -WsusServer 'wsus02.contoso.local'

        $result.Role | Should -Be 'Replica'
        $result.Declined | Should -Be 0
        $result.Log | Should -BeNullOrEmpty
        Should -Invoke -ModuleName WSUS Start-WsusLog -Times 0 -Exactly
        $script:fake.Calls | Should -Not -Contain 'GetUpdates'
    }

    It 'declines nothing under -WhatIf' {
        $result = Invoke-WsusDecline -WhatIf

        $result.Declined | Should -Be 0
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Cumulative Update for Windows 11 ARM64 (KB1)'
    }

    It 'logs with the decline prefix and keeps 96 logs by default' {
        $null = Invoke-WsusDecline -LogPath 'C:\logs'

        Should -Invoke -ModuleName WSUS Start-WsusLog -Times 1 -Exactly -ParameterFilter { $Prefix -eq 'decline' -and $Path -eq 'C:\logs' }
        Should -Invoke -ModuleName WSUS Stop-WsusLog -Times 1 -Exactly -ParameterFilter { $Prefix -eq 'decline' -and $Keep -eq 96 }
    }

    It 'throws at the first failure and still closes the log' {
        $script:fake | Add-Member -MemberType ScriptMethod -Name GetUpdates -Force -Value { throw 'API went away' }

        { Invoke-WsusDecline } | Should -Throw '*API went away*'
        Should -Invoke -ModuleName WSUS Stop-WsusLog -Times 1 -Exactly
    }

    It 'throws naming the node when the connection fails' {
        Mock -ModuleName WSUS Get-WsusServer { throw 'refused' }

        { Invoke-WsusDecline } | Should -Throw "*wsus01.contoso.local*8531*"
        Should -Invoke -ModuleName WSUS Start-WsusLog -Times 0 -Exactly
    }
}
