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
        [string] $UpstreamName = '',
        [int] $UpstreamPort = 8531,
        [string[]] $ComputerGroups = @('All Computers', 'Unassigned Computers'),
        [string[]] $ApprovalRules = @('Default Automatic Approval Rule'),
        [int] $ApprovalCount = 0
    )

    $calls = [System.Collections.Generic.List[string]]::new()

    $config = [PSCustomObject] @{
        IsReplicaServer       = $IsReplica
        LocalContentCachePath = $ContentPath
        SyncFromMicrosoftUpdate = -not $IsReplica
        UpstreamWsusServerName = $UpstreamName
        UpstreamWsusServerPortNumber = $UpstreamPort
        UpstreamWsusServerUseSsl = $true
        GetContentFromMU = -not $IsReplica
        DownloadExpressPackages = $false
        DownloadUpdateBinariesAsNeeded = $true
        HostBinariesOnMicrosoftUpdate = $false
        TargetingMode = 'Server'
        UseProxy = $false
        Calls = $calls
    }
    $config | Add-Member -MemberType ScriptMethod -Name Save -Value { $this.Calls.Add('Config.Save') }

    $syncInfo = if ($null -ne $LastSyncStart) {
        [PSCustomObject] @{ StartTime = $LastSyncStart; EndTime = $LastSyncStart.AddMinutes(30); Result = $LastSyncResult }
    }

    $subscription = [PSCustomObject] @{
        Calls = $calls; SyncInfo = $syncInfo
        SynchronizeAutomatically = $false
        SynchronizeAutomaticallyTimeOfDay = [timespan]::Zero
        NumberOfSynchronizationsPerDay = 1
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name Save -Value { $this.Calls.Add('Subscription.Save') }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetLastSynchronizationInfo -Value {
        $this.Calls.Add('GetLastSynchronizationInfo'); $this.SyncInfo
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name StartSynchronization -Value {
        $this.Calls.Add('StartSynchronization')
    }

    $fake = [PSCustomObject] @{
        Name         = $Name
        Calls        = $calls
        Config       = $config
        Subscription = $subscription
        Groups       = @($ComputerGroups | ForEach-Object { [PSCustomObject] @{ Name = $_ } })
        Rules        = @($ApprovalRules | ForEach-Object { [PSCustomObject] @{ Name = $_ } })
        Approvals    = @(for ($i = 0; $i -lt $ApprovalCount; $i++) { [PSCustomObject] @{ Id = $i } })
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetComputerTargetGroups -Value { $this.Groups }
    $fake | Add-Member -MemberType ScriptMethod -Name GetInstallApprovalRules -Value { $this.Rules }
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateApprovals -Value { param($scope) $this.Approvals }
    $fake | Add-Member -MemberType ScriptMethod -Name GetConfiguration -Value {
        $this.Calls.Add('GetConfiguration'); $this.Config
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value {
        $this.Calls.Add('GetSubscription'); $this.Subscription
    }
    $fake
}
