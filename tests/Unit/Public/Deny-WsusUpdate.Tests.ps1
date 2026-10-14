BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Deny-WsusUpdate' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Updates @(
            @{ Title = 'Update for Windows 11 x64 (KB5001234)'; Kb = '5001234' },
            @{ Title = 'Update for Windows 11 ARM64 (KB5001234)'; Kb = '5001234' },
            @{ Title = 'Update for Windows 10 (KB50012345)'; Kb = '50012345' },
            @{ Title = 'Old update (KB5009999)'; Kb = '5009999'; IsDeclined = $true }
        )
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
    }

    It 'declines every exact KB match, including variants, and not look-alike KBs' {
        $result = Deny-WsusUpdate -Kb 'KB5001234'

        @($result).Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'WSUS.DeclineResult'
        $result.Action | Should -Not -Contain 'AlreadyDeclined'
        $result.Action | Should -Be @('Declined', 'Declined')
        $result.Kb | Should -Be @('KB5001234', 'KB5001234')
        $script:fake.Calls | Should -Contain 'Update.Decline:Update for Windows 11 x64 (KB5001234)'
        $script:fake.Calls | Should -Contain 'Update.Decline:Update for Windows 11 ARM64 (KB5001234)'
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Update for Windows 10 (KB50012345)'
    }

    It 'accepts the KB number with or without the KB prefix' {
        $result = Deny-WsusUpdate -Kb '5001234'

        @($result).Count | Should -Be 2
        $result[0].Kb | Should -Be 'KB5001234'
    }

    It 'reports an already declined update without declining it again' {
        $result = Deny-WsusUpdate -Kb 'KB5009999'

        $result.Action | Should -Be 'AlreadyDeclined'
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Old update (KB5009999)'
    }

    It 'writes a non-terminating error for a KB with no match and carries on' {
        $result = Deny-WsusUpdate -Kb 'KB1', 'KB5001234' -ErrorVariable err -ErrorAction SilentlyContinue

        @($result).Count | Should -Be 2
        $err.Count | Should -Be 1
        $err[0].Exception.Message | Should -BeLike '*KB1*'
    }

    It 'points at the DISM removal in the next step' {
        (Deny-WsusUpdate -Kb 'KB5001234')[0].NextStep | Should -BeLike '*DISM*'
    }

    It 'declines nothing under -WhatIf' {
        $result = Deny-WsusUpdate -Kb 'KB5001234' -WhatIf

        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Update for Windows 11 x64 (KB5001234)'
        $result | Should -BeNullOrEmpty
    }

    It 'throws on a replica, naming the node' {
        $script:fake = New-FakeWsusServer -IsReplica $true -Name 'wsus02.contoso.local'

        { Deny-WsusUpdate -Kb 'KB5001234' -WsusServer 'wsus02.contoso.local' } | Should -Throw '*wsus02.contoso.local is a replica*'
    }
}
