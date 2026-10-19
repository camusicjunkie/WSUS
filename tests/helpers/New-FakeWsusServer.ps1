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
        # Plain updates for decline tests (Approve-WsusRing tests use New-FakeWsusUpdate instead, which models
        # approvals and summaries). Hashtables: @{ Title = ...; Kb = @('5001234'); IsDeclined = $false } (IUpdate fakes);
        # optional IsSuperseded and ArrivalDate (default now UTC).
        [hashtable[]] $Updates = @(),
        [string] $UpstreamName = '',
        [int] $UpstreamPort = 8531,
        [string[]] $ComputerGroups = @('All Computers', 'Unassigned Computers'),
        [int] $ApprovalCount = 0,
        # Update category titles the server already knows, and ones that appear after a categories-only sync.
        [string[]] $Categories = @(),
        [string[]] $CategoriesAfterSync = @(),
        [string[]] $Classifications = @('Critical Updates', 'Security Updates', 'Definition Updates', 'Updates')
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
        UseProxy = $false
        ProxyName = $null
        ProxyServerPort = 0
        AllUpdateLanguagesEnabled = $true
        EnabledUpdateLanguages = @()
        DownloadExpressPackages = $true
        HostBinariesOnMicrosoftUpdate = $true
        DownloadUpdateBinariesAsNeeded = $false
        TargetingMode = 'Server'
        AutoApproveWsusInfrastructureUpdates = $false
        AutoRefreshUpdateApprovals = $false
        AutoRefreshUpdateApprovalsDeclineExpired = $false
        Calls = $calls
    }
    $config | Add-Member -MemberType ScriptMethod -Name SetEnabledUpdateLanguages -Value {
        param ($Language) $this.EnabledUpdateLanguages = @($Language)
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
        foreach ($title in $this.Owner.CategoriesAfterSync) { $this.Owner.CategoryList.Add([PSCustomObject] @{ Title = $title }) }
    }
    $subscription | Add-Member -NotePropertyName UpdateCategories -NotePropertyValue @()
    $subscription | Add-Member -NotePropertyName UpdateClassifications -NotePropertyValue @()
    $subscription | Add-Member -MemberType ScriptMethod -Name SetUpdateCategories -Value {
        param ($Collection) $this.UpdateCategories = @($Collection | ForEach-Object Title)
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name SetUpdateClassifications -Value {
        param ($Collection) $this.UpdateClassifications = @($Collection | ForEach-Object Title)
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetSynchronizationStatus -Value {
        if ($this.PollsLeft -gt 0) { $this.PollsLeft--; 'Running' } else { 'NotProcessing' }
    }
    $subscription | Add-Member -MemberType ScriptMethod -Name GetSynchronizationProgress -Value {
        [PSCustomObject] @{ ProcessedItems = 5; TotalItems = 10; Phase = 'Updates' }
    }

    $newRule = {
        param ($Calls, $RuleName, $RuleEnabled)
        $r = [PSCustomObject] @{
            Name = $RuleName; Enabled = $RuleEnabled; Calls = $Calls
            Classifications = @(); Groups = @()
        }
        $r | Add-Member -MemberType ScriptMethod -Name Save -Value { $this.Calls.Add("Rule.Save:$($this.Name)") }
        $r | Add-Member -MemberType ScriptMethod -Name ApplyRule -Value { $this.Calls.Add("Rule.Apply:$($this.Name)") }
        $r | Add-Member -MemberType ScriptMethod -Name SetUpdateClassifications -Value {
            param ($Collection) $this.Classifications = @($Collection | ForEach-Object Title)
        }
        $r | Add-Member -MemberType ScriptMethod -Name SetComputerTargetGroups -Value {
            param ($Collection) $this.Groups = @($Collection | ForEach-Object Name)
        }
        $r
    }

    $ruleObjects = foreach ($rule in $Rules) {
        & $newRule $calls $rule.Name ([bool] $rule.Enabled)
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
        Updates      = [System.Collections.Generic.List[object]]::new()
        LastScope    = $null
        RuleFactory  = $newRule
        CategoryList = [System.Collections.Generic.List[object]]::new()
        CategoriesAfterSync = $CategoriesAfterSync
        Groups       = [System.Collections.Generic.List[object]]::new()
        Classifications = @($Classifications | ForEach-Object { [PSCustomObject] @{ Title = $_ } })
    }
    foreach ($title in $Categories) { $fake.CategoryList.Add([PSCustomObject] @{ Title = $title }) }
    foreach ($group in $ComputerGroups) { $fake.Groups.Add([PSCustomObject] @{ Name = $group }) }
    $subscription | Add-Member -NotePropertyName Owner -NotePropertyValue $fake
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateCategories -Value { $this.CategoryList.ToArray() }
    $fake | Add-Member -MemberType ScriptMethod -Name GetUpdateClassifications -Value { $this.Classifications }
    $fake | Add-Member -MemberType ScriptMethod -Name GetComputerTargetGroups -Value { $this.Groups.ToArray() }
    $fake | Add-Member -MemberType ScriptMethod -Name CreateComputerTargetGroup -Value {
        param ($GroupName)
        $this.Calls.Add("CreateGroup:$GroupName")
        $group = [PSCustomObject] @{ Name = $GroupName }
        $this.Groups.Add($group)
        $group
    }
    $fake | Add-Member -MemberType ScriptMethod -Name CreateInstallApprovalRule -Value {
        param ($RuleName)
        $this.Calls.Add("CreateRule:$RuleName")
        $rule = & $this.RuleFactory $this.Calls $RuleName $true
        $this.Rules = @($this.Rules) + $rule
        $rule
    }
    foreach ($u in $updateObjects) { $fake.Updates.Add($u) }
    $fake | Add-Member -MemberType ScriptMethod -Name GetInstallApprovalRules -Value {
        $this.Calls.Add('GetInstallApprovalRules'); $this.Rules
    }
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
    # IUpdateServer.GetStatus: server-wide counts. Tests set the numbers on $fake.Status.
    $fake | Add-Member -NotePropertyName Status -NotePropertyValue ([PSCustomObject] @{
        UpdateCount = 0; ApprovedUpdateCount = 0; DeclinedUpdateCount = 0
    })
    $fake | Add-Member -MemberType ScriptMethod -Name GetStatus -Value { $this.Calls.Add('GetStatus'); $this.Status }
    $fake
}
