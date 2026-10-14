BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Unregister-WsusMaintenanceTask' {
    BeforeEach {
        $script:existing = [System.Collections.Generic.List[string]]::new()
        $script:removed = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName WSUS Assert-WsusPrerequisite { }
        Mock -ModuleName WSUS Get-ScheduledTask {
            if ($script:existing -contains $TaskName) { [PSCustomObject] @{ TaskName = $TaskName } }
        }
        Mock -ModuleName WSUS Unregister-ScheduledTask { $script:removed.Add($TaskName) }
    }

    It 'removes both tasks and returns nothing' {
        $script:existing.AddRange([string[]] ('WSUS Maintenance', 'WSUS Decline Unwanted'))

        $result = Unregister-WsusMaintenanceTask

        $result | Should -BeNullOrEmpty
        $script:removed | Should -Be @('WSUS Maintenance', 'WSUS Decline Unwanted')
    }

    It 'does nothing and does not error when the tasks are absent' {
        { Unregister-WsusMaintenanceTask -ErrorAction Stop } | Should -Not -Throw
        $script:removed.Count | Should -Be 0
    }

    It 'removes only the task that exists' {
        $script:existing.Add('WSUS Decline Unwanted')

        Unregister-WsusMaintenanceTask

        $script:removed | Should -Be @('WSUS Decline Unwanted')
    }

    It 'removes nothing under -WhatIf' {
        $script:existing.AddRange([string[]] ('WSUS Maintenance', 'WSUS Decline Unwanted'))

        Unregister-WsusMaintenanceTask -WhatIf

        $script:removed.Count | Should -Be 0
    }
}
