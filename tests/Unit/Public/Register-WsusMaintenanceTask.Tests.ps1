BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Register-WsusMaintenanceTask' {
    BeforeEach {
        $script:registered = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName WSUS Assert-WsusPrerequisite { }
        Mock -ModuleName WSUS Assert-WsusAllUsersInstall { }
        Mock -ModuleName WSUS New-ScheduledTaskAction { [PSCustomObject] @{ Execute = $Execute; Arguments = $Argument } }
        Mock -ModuleName WSUS New-ScheduledTaskTrigger { [PSCustomObject] @{ Bound = @{} + $PesterBoundParameters } }
        Mock -ModuleName WSUS New-ScheduledTaskPrincipal { [PSCustomObject] @{ UserId = $UserId; RunLevel = $RunLevel } }
        Mock -ModuleName WSUS New-ScheduledTaskSettingsSet { [PSCustomObject] @{ Bound = @{} + $PesterBoundParameters } }
        Mock -ModuleName WSUS Register-ScheduledTask {
            $script:registered.Add([PSCustomObject] @{
                    TaskName = $TaskName; Action = $Action; Trigger = $Trigger
                    Principal = $Principal; Settings = $Settings; Force = [bool] $Force
                })
        }
    }

    It 'registers both fixed-name tasks and returns one WSUS.MaintenanceTask for each' {
        $result = @(Register-WsusMaintenanceTask)

        $result.Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'WSUS.MaintenanceTask'
        $result.TaskName | Should -Be @('WSUS Maintenance', 'WSUS Decline Unwanted')
        $script:registered.TaskName | Should -Be @('WSUS Maintenance', 'WSUS Decline Unwanted')
    }

    It 'runs each task as SYSTEM through powershell.exe -Command with default schedules' {
        $result = @(Register-WsusMaintenanceTask)

        $weekly, $decline = $result
        $weekly.RunAs | Should -Be 'SYSTEM'
        $weekly.Schedule | Should -Be 'Weekly on Sunday at 02:00'
        $weekly.Command | Should -Be 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-WsusMaintenance"'
        $decline.RunAs | Should -Be 'SYSTEM'
        $decline.Schedule | Should -Be 'Every 15 minutes'
        $decline.Command | Should -Be 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-WsusDecline"'
    }

    It 'applies day, time and interval parameters to the triggers' {
        $result = @(Register-WsusMaintenanceTask -MaintenanceDay Wednesday -MaintenanceTime 04:00 -DeclineIntervalMinutes 30)

        $result[0].Schedule | Should -Be 'Weekly on Wednesday at 04:00'
        $result[1].Schedule | Should -Be 'Every 30 minutes'

        $weekly = $script:registered | Where-Object TaskName -eq 'WSUS Maintenance'
        $weekly.Trigger.Bound.ContainsKey('Weekly') | Should -BeTrue
        $weekly.Trigger.Bound.DaysOfWeek | Should -Be 'Wednesday'
        $weekly.Trigger.Bound.At.TimeOfDay | Should -Be ([timespan] '04:00:00')

        $decline = $script:registered | Where-Object TaskName -eq 'WSUS Decline Unwanted'
        $decline.Trigger.Bound.ContainsKey('Once') | Should -BeTrue
        $decline.Trigger.Bound.RepetitionInterval | Should -Be ([timespan]::FromMinutes(30))
        $decline.Trigger.Bound.ContainsKey('RepetitionDuration') | Should -BeFalse -Because 'omitted means repeat indefinitely'
    }

    It 'registers with the highest run level, replacing an existing task, and the fixed task settings' {
        Register-WsusMaintenanceTask | Out-Null

        $weekly = $script:registered | Where-Object TaskName -eq 'WSUS Maintenance'
        $decline = $script:registered | Where-Object TaskName -eq 'WSUS Decline Unwanted'

        foreach ($task in $weekly, $decline) {
            $task.Force | Should -BeTrue
            $task.Principal.UserId | Should -Be 'SYSTEM'
            $task.Principal.RunLevel | Should -Be 'Highest'
            $task.Settings.Bound.MultipleInstances | Should -Be 'IgnoreNew'
        }
        $weekly.Settings.Bound.StartWhenAvailable.IsPresent | Should -BeTrue
        $weekly.Settings.Bound.ExecutionTimeLimit | Should -Be ([timespan]::FromHours(12))
        $decline.Settings.Bound.ContainsKey('StartWhenAvailable') | Should -BeFalse
        $decline.Settings.Bound.ExecutionTimeLimit | Should -Be ([timespan]::FromMinutes(10))
    }

    It 'registers nothing when the session is not elevated' {
        Mock -ModuleName WSUS Assert-WsusPrerequisite { throw 'Prerequisites not met: PowerShell is not elevated' }

        { Register-WsusMaintenanceTask } | Should -Throw '*not elevated*'
        $script:registered.Count | Should -Be 0
    }

    It 'registers nothing when the module is not installed for all users' {
        Mock -ModuleName WSUS Assert-WsusAllUsersInstall { throw 'WSUS module is not installed for all users' }

        { Register-WsusMaintenanceTask } | Should -Throw '*all users*'
        $script:registered.Count | Should -Be 0
    }

    It 'registers nothing under -WhatIf' {
        $result = @(Register-WsusMaintenanceTask -WhatIf)

        $result.Count | Should -Be 0
        $script:registered.Count | Should -Be 0
    }
}
