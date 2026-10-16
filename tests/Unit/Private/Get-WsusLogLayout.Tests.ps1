BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusLogLayout' {
    BeforeAll {
        $script:layout = InModuleScope WSUS { Get-WsusLogLayout }
    }

    It 'puts the run logs under ProgramData' {
        $script:layout.Root | Should -Be 'C:\ProgramData\WsusMaintenance'
    }

    It 'names the log files of each kind of run' {
        $script:layout.Prefix.Maintenance | Should -Be 'maint'
        $script:layout.Prefix.Decline | Should -Be 'decline'
    }

    It 'gives every kind a different prefix, so retention for one never removes another' {
        @($script:layout.Prefix.Values | Select-Object -Unique).Count | Should -Be $script:layout.Prefix.Count
    }
}
