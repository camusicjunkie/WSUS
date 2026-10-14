function New-FakeWsusServer {
    <#
    .SYNOPSIS
        Builds a fake IUpdateServer for tests. Calls are recorded on the fake itself ($fake.Calls).
    .DESCRIPTION
        Only the members the module uses are faked; extend this helper when a function needs more.
        Add state (for example a rules list) as properties, and record every state change by adding
        a line to $fake.Calls from the ScriptMethod, so tests assert effects on the fake.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds an in-memory object.')]
    param (
        [string] $Name = 'wsus01.contoso.local',
        [bool] $IsReplica = $false,
        [string] $ContentPath = 'D:\WSUS',
        [Nullable[datetime]] $LastSyncStart = [datetime] '2026-10-12T02:00:00',
        [string] $LastSyncResult = 'Succeeded',
        [switch] $SyncRunning,
        [int] $SyncPolls = 1,
        [string] $LastSyncError,
        [string[]] $Groups = @('Pilot', 'Workstations', 'Servers'),
        [string[]] $Classifications = @('Critical Updates', 'Security Updates', 'Definition Updates')
    )

    $calls = [System.Collections.Generic.List[string]]::new()

    $config = [PSCustomObject] @{
        IsReplicaServer       = $IsReplica
        LocalContentCachePath = $ContentPath
    }

    $syncInfo = if ($null -ne $LastSyncStart) {
        [PSCustomObject] @{ StartTime = $LastSyncStart; EndTime = $LastSyncStart.AddMinutes(30); Result = $LastSyncResult; Error = $LastSyncError }
    }

    $subscription = [PSCustomObject] @{ Calls = $calls; SyncInfo = $syncInfo; PollsPerSync = $SyncPolls; PollsLeft = $(if ($SyncRunning) { $SyncPolls } else { 0 }) }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetLastSynchronizationInfo -Value {
        $this.Calls.Add('GetLastSynchronizationInfo'); $this.SyncInfo
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name StartSynchronization -Value {
        $this.Calls.Add('StartSynchronization'); $this.PollsLeft = $this.PollsPerSync
    }

    $subscription | Add-Member -MemberType ScriptMethod -Name StartSynchronizationForCategoryOnly -Value {
        $this.Calls.Add('StartSynchronizationForCategoryOnly'); $this.PollsLeft = $this.PollsPerSync
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetSynchronizationStatus -Value {
        if ($this.PollsLeft -gt 0) { $this.PollsLeft--; 'Running' } else { 'NotProcessing' }
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetSynchronizationProgress -Value {
        [PSCustomObject] @{ ProcessedItems = 5; TotalItems = 10 }
    }

    $fake = [PSCustomObject] @{
        Name         = $Name
        Calls        = $calls
        Config       = $config
        Subscription = $subscription
        Groups       = @($Groups | ForEach-Object { [PSCustomObject] @{ Name = $_ } })
        Classifications = @($Classifications | ForEach-Object { [PSCustomObject] @{ Title = $_ } })
        Updates      = [System.Collections.Generic.List[object]]::new()
        LastScope    = $null
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetConfiguration -Value {
        $this.Calls.Add('GetConfiguration'); $this.Config
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value {
        $this.Calls.Add('GetSubscription'); $this.Subscription
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetComputerTargetGroups -Value { $this.Groups }
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateClassifications -Value { $this.Classifications }
    # Returns every update in $fake.Updates; the real server filters by scope, the fake only records it.
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdates -Value {
        param ($scope)
        $this.LastScope = $scope
        $this.Updates.ToArray()
    }
    $fake
}
