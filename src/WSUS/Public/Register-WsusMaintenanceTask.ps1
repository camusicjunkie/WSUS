function Register-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Registers the weekly maintenance and 15-minute decline scheduled tasks on this node.
    .DESCRIPTION
        Registers two tasks as SYSTEM with the highest run level, under fixed names:
        'WSUS Maintenance' (runs Invoke-WsusMaintenance weekly) and 'WSUS Decline Unwanted'
        (runs Invoke-WsusDecline on a repeating interval, starting now). Each task runs
        powershell.exe -Command with the function's default parameters.

        Run it on every node, replicas included: Invoke-WsusDecline exits quietly on a replica, so
        promoting a replica needs no re-registration. Re-running replaces both tasks silently, so
        changing the schedule or rebuilding a node is the same command. Stagger the weekly task per
        node explicitly (for example -MaintenanceTime 04:00 on the replica).

        Requires an elevated session and the WSUS module installed for all users (the tasks run as
        SYSTEM and can't see a per-user install); throws before registering anything otherwise.
    .PARAMETER MaintenanceDay
        Day of the week for the maintenance run. Default Sunday.
    .PARAMETER MaintenanceTime
        Time of day (HH:mm) for the maintenance run. Default 02:00.
    .PARAMETER DeclineIntervalMinutes
        Minutes between decline runs. Default 15.
    .EXAMPLE
        Register-WsusMaintenanceTask
        Registers both tasks on this node with the default schedule.
    .EXAMPLE
        Register-WsusMaintenanceTask -MaintenanceTime 04:00
        Staggers the weekly maintenance run on the second node.
    .OUTPUTS
        WSUS.MaintenanceTask
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.MaintenanceTask')]
    param (
        [System.DayOfWeek] $MaintenanceDay = 'Sunday',

        [ValidatePattern('^([01]?\d|2[0-3]):[0-5]\d$')]
        [string] $MaintenanceTime = '02:00',

        [ValidateRange(1, 1440)]
        [int] $DeclineIntervalMinutes = 15
    )

    Assert-WsusPrerequisite -Administrator
    Assert-WsusAllUsersInstall

    $time = [datetime]::ParseExact($MaintenanceTime, 'H:mm', [Globalization.CultureInfo]::InvariantCulture)

    $tasks = @(
        @{
            Name     = 'WSUS Maintenance'
            Function = 'Invoke-WsusMaintenance'
            Schedule = 'Weekly on {0} at {1:HH:mm}' -f $MaintenanceDay, $time
            Trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $MaintenanceDay -At $time
            Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12)
        }
        @{
            Name     = 'WSUS Decline Unwanted'
            Function = 'Invoke-WsusDecline'
            Schedule = "Every $DeclineIntervalMinutes minutes"
            # No -RepetitionDuration: the repetition runs indefinitely (verified on Windows PowerShell 5.1).
            Trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $DeclineIntervalMinutes)
            Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        }
    )

    foreach ($task in $tasks) {
        $argument = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "{0}"' -f $task.Function
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
        $trigger = $task.Trigger
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = $task.Settings
        if (-not $PSCmdlet.ShouldProcess($task.Name, 'Register scheduled task')) {
            continue
        }
        Register-ScheduledTask -TaskName $task.Name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

        [PSCustomObject] @{
            PSTypeName = 'WSUS.MaintenanceTask'
            TaskName   = $task.Name
            Schedule   = $task.Schedule
            RunAs      = 'SYSTEM'
            Command    = 'powershell.exe ' + $argument
        }
    }
}
