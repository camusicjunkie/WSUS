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
        # Approval rules as @{ Name = ...; Enabled = ... } hashtables (IInstallApprovalRule fakes).
        [hashtable[]] $Rules = @(),
        # Updates as @{ Title = ...; Kb = @('5001234'); IsDeclined = $false } hashtables (IUpdate fakes);
        # optional IsSuperseded and ArrivalDate (default now UTC).
        [hashtable[]] $Updates = @(),
        [string] $UpstreamName = '',
        [int] $UpstreamPort = 8531,
        [string[]] $ComputerGroups = @('All Computers', 'Unassigned Computers'),
        # Shorthand for enabled rules by name only (appended to -Rules).
        [string[]] $ApprovalRules = @(),
        [int] $ApprovalCount = 0,
        [string[]] $Classifications = @('Critical Updates', 'Security Updates', 'Definition Updates')
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
        [PSCustomObject] @{ StartTime = $LastSyncStart; EndTime = $LastSyncStart.AddMinutes(30); Result = $LastSyncResult; Error = $LastSyncError }
    }

    $subscription = [PSCustomObject] @{
        Calls = $calls; SyncInfo = $syncInfo; PollsPerSync = $SyncPolls; PollsLeft = $(if ($SyncRunning) { $SyncPolls } else { 0 })
        SynchronizeAutomatically = $false
        SynchronizeAutomaticallyTimeOfDay = [timespan]::Zero
        NumberOfSynchronizationsPerDay = 1
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name Save -Value { $this.Calls.Add('Subscription.Save') }
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

    $allRules = @($Rules) + @($ApprovalRules | ForEach-Object { @{ Name = $_; Enabled = $true } })
    $ruleObjects = foreach ($rule in $allRules) {
        $r = [PSCustomObject] @{ Name = $rule.Name; Enabled = [bool] $rule.Enabled; Calls = $calls }
        $r | Add-Member -MemberType ScriptMethod -Name Save -Value { $this.Calls.Add("Rule.Save:$($this.Name)") }
        $r
    }

    $updateObjects = foreach ($update in $Updates) {
        $u = [PSCustomObject] @{
            Title                 = $update.Title
            KnowledgebaseArticles = [string[]] $update.Kb
            IsDeclined            = [bool] $update.IsDeclined
            IsSuperseded          = [bool] $update.IsSuperseded
            ArrivalDate           = $(if ($update.ArrivalDate) { [datetime] $update.ArrivalDate } else { [datetime]::UtcNow })
            Calls                 = $calls
        }
        $u | Add-Member -MemberType ScriptMethod -Name Decline -Value {
            $this.Calls.Add("Update.Decline:$($this.Title)"); $this.IsDeclined = $true
        }
        $u
    }

    $fake = [PSCustomObject] @{
        Name         = $Name
        Calls        = $calls
        Config       = $config
        Subscription = $subscription
        Rules        = @($ruleObjects)
        Classifications = @($Classifications | ForEach-Object { [PSCustomObject] @{ Title = $_ } })
        Updates      = [System.Collections.Generic.List[object]]::new()
        LastScope    = $null
    }
    foreach ($u in $updateObjects) { $fake.Updates.Add($u) }
    $fake | Add-Member -MemberType ScriptMethod -Name GetInstallApprovalRules -Value {
        $this.Calls.Add('GetInstallApprovalRules'); $this.Rules
    }
    $fake | Add-Member -MemberType NoteProperty -Name Groups -Value @($ComputerGroups | ForEach-Object { [PSCustomObject] @{ Name = $_ } })
    $fake | Add-Member -MemberType NoteProperty -Name Approvals -Value @(for ($i = 0; $i -lt $ApprovalCount; $i++) { [PSCustomObject] @{ Id = $i } })
    # Like the real API: SearchUpdates is a substring match on title and KB, which is why
    # Deny-WsusUpdate re-filters to exact KB hits.
    $fake | Add-Member -MemberType ScriptMethod -Name SearchUpdates -Value {
        param ($Text)
        $this.Calls.Add("SearchUpdates:$Text")
        $this.Updates | Where-Object {
            $_.Title -like "*$Text*" -or @($_.KnowledgebaseArticles | Where-Object { $_ -like "*$Text*" }).Count -gt 0
        }
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetComputerTargetGroups -Value { $this.Groups }
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateClassifications -Value { $this.Classifications }
    # Records the scope. Filters only by FromArrivalDate (updates without an ArrivalDate always match);
    # the real server filters by the whole scope.
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdates -Value {
        param ($scope)
        $this.LastScope = $scope
        $this.Updates.ToArray() | Where-Object {
            -not $_.PSObject.Properties['ArrivalDate'] -or -not $scope -or $_.ArrivalDate -ge $scope.FromArrivalDate
        }
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateApprovals -Value { param($scope) $null = $scope; $this.Approvals }
    $fake | Add-Member -MemberType ScriptMethod -Name GetConfiguration -Value {
        $this.Calls.Add('GetConfiguration'); $this.Config
    }
    $fake | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value {
        $this.Calls.Add('GetSubscription'); $this.Subscription
    }
    $fake
}
