# Stub of the ScheduledTasks module for tests. Bodies throw so an unmocked call fails loudly.
function New-ScheduledTaskAction {
    [CmdletBinding()]
    param ([string] $Execute, [string] $Argument)
    throw 'Stub New-ScheduledTaskAction called: mock it.'
}
function New-ScheduledTaskTrigger {
    [CmdletBinding()]
    param ([switch] $Once, [switch] $Weekly, [datetime] $At, [string[]] $DaysOfWeek, [timespan] $RepetitionInterval, [timespan] $RepetitionDuration)
    throw 'Stub New-ScheduledTaskTrigger called: mock it.'
}
function New-ScheduledTaskPrincipal {
    [CmdletBinding()]
    param ([string] $UserId, [string] $LogonType, [string] $RunLevel)
    throw 'Stub New-ScheduledTaskPrincipal called: mock it.'
}
function New-ScheduledTaskSettingsSet {
    [CmdletBinding()]
    param ([string] $MultipleInstances, [switch] $StartWhenAvailable, [timespan] $ExecutionTimeLimit)
    throw 'Stub New-ScheduledTaskSettingsSet called: mock it.'
}
function Register-ScheduledTask {
    [CmdletBinding()]
    param ([string] $TaskName, $Action, $Trigger, $Principal, $Settings, [string] $Description, [switch] $Force)
    throw 'Stub Register-ScheduledTask called: mock it.'
}
function Get-ScheduledTask {
    [CmdletBinding()]
    param ([string] $TaskName, [string] $ErrorAction)
    throw 'Stub Get-ScheduledTask called: mock it.'
}
function Unregister-ScheduledTask {
    [CmdletBinding()]
    param ([string] $TaskName, [switch] $Confirm)
    throw 'Stub Unregister-ScheduledTask called: mock it.'
}
Export-ModuleMember -Function *
