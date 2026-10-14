function Set-WsusUpstreamConfig {
    <#
    .SYNOPSIS
        Configures the upstream node: sync source, products, classifications, schedule, computer groups and approval rules.
    .DESCRIPTION
        Upstream only (a replica is pointed at ConvertTo-WsusUpstream). Everything set here replicates
        to the replica on its next sync. Also used on a freshly promoted node. Safe to repeat.
    .PARAMETER WsusServer
        Node to configure. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
    .PARAMETER UpstreamServer
        Sync from this WSUS server instead of Microsoft Update (for example to chain downstream of DISA).
    .PARAMETER UpstreamPort
        Port on the upstream server. 8531 turns on SSL. Default 8531.
    .PARAMETER ProxyHost
        Proxy for Microsoft Update. Leave empty for a direct connection.
    .PARAMETER ProxyPort
        Proxy port. Default 8080.
    .PARAMETER Product
        Product titles to sync. Must match the console titles exactly. A title the server does not
        know triggers a categories-only sync; one still missing afterwards throws.
    .PARAMETER Classification
        Update classifications to sync.
    .PARAMETER SyncsPerDay
        Automatic syncs per day (1 to 24). Default 2.
    .PARAMETER ComputerGroup
        Computer groups to create. Names must match the client TargetGroup values exactly.
    .PARAMETER CritSecGroup
        Groups the 'Auto - Critical and Security' rule approves for. Workstations and Servers are approved
        later with Approve-WsusRing, once Pilot passes its gate.
    .PARAMETER DefinitionGroup
        Groups the 'Auto - Definition Updates' rule approves for.
    .PARAMETER ApplyRulesNow
        Also approve the existing backlog through the rules that are currently on (warns when none is).
        Run Invoke-WsusMaintenance -SupersededAgeDays 0 and Enable-WsusApprovalRule first, or it
        approves and downloads piles of superseded updates.
    .PARAMETER FirstSyncUtcHour
        Hour of the first daily sync, in UTC (0 to 23). Default 2. The replica syncs two hours later.
    .EXAMPLE
        Set-WsusUpstreamConfig -WhatIf
        Shows what would be configured without changing the node.
    .OUTPUTS
        WSUS.UpstreamConfig
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.UpstreamConfig')]
    param (
        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531,

        [string] $UpstreamServer,

        [int] $UpstreamPort = 8531,

        [string] $ProxyHost,

        [int] $ProxyPort = 8080,

        [string[]] $Product = @(
            'Windows 11'
            'Microsoft Server Operating System-21H2'   # Server 2022
            'Microsoft Server Operating System-24H2'   # Server 2025
            'Microsoft Defender Antivirus'             # Definition updates
        ),

        [string[]] $Classification = @('Critical Updates', 'Security Updates', 'Definition Updates'),

        [ValidateRange(1, 24)]
        [int] $SyncsPerDay = 2,

        [ValidateRange(0, 23)]
        [int] $FirstSyncUtcHour = 2,

        [string[]] $ComputerGroup = @('Packer', 'Pilot', 'Workstations', 'Servers', 'VDI-Definitions'),

        [string[]] $CritSecGroup = @('Packer', 'Pilot'),

        [string[]] $DefinitionGroup = @('Packer', 'Pilot', 'Workstations', 'VDI-Definitions'),

        [switch] $ApplyRulesNow
    )

    Assert-WsusPrerequisite -Module UpdateServices -Administrator

    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
    Assert-WsusUpstream -Wsus $wsus -Instead 'Promote it first with ConvertTo-WsusUpstream.'

    $config = $wsus.GetConfiguration()
    if ($UpstreamServer) {
        $config.SyncFromMicrosoftUpdate = $false
        $config.UpstreamWsusServerName = $UpstreamServer
        $config.UpstreamWsusServerPortNumber = $UpstreamPort
        $config.UpstreamWsusServerUseSsl = ($UpstreamPort -eq 8531)
    }
    else {
        $config.SyncFromMicrosoftUpdate = $true
    }
    $config.UseProxy = [bool] $ProxyHost
    if ($ProxyHost) {
        $config.ProxyName = $ProxyHost
        $config.ProxyServerPort = $ProxyPort
    }

    $config.AllUpdateLanguagesEnabled = $false
    $config.SetEnabledUpdateLanguages('en')
    $config.DownloadExpressPackages = $false          # express files balloon content size
    $config.HostBinariesOnMicrosoftUpdate = $false    # clients pull content from WSUS
    $config.DownloadUpdateBinariesAsNeeded = $true    # download content only once approved
    $config.TargetingMode = 'Client'                  # groups come from client policy
    $config.AutoApproveWsusInfrastructureUpdates = $true
    $config.AutoRefreshUpdateApprovals = $true        # approve new revisions of approved updates
    $config.AutoRefreshUpdateApprovalsDeclineExpired = $true
    if ($PSCmdlet.ShouldProcess($WsusServer, 'Save server configuration')) {
        $config.Save()
    }

    # Categories are only known after a categories-only sync, so run one when a title is unknown.
    $known = @($wsus.GetUpdateCategories() | ForEach-Object Title)
    $missing = @($Product | Where-Object { $_ -notin $known })
    if ($known.Count -eq 0 -or $missing.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($WsusServer, 'Run categories-only sync')) {
            Write-Verbose -Message 'Running categories-only sync'
            $null = Start-WsusSync -WsusServer $WsusServer -Port $Port -CategoryOnly -Wait
            $known = @($wsus.GetUpdateCategories() | ForEach-Object Title)
            $missing = @($Product | Where-Object { $_ -notin $known })
            if ($missing.Count -gt 0) {
                throw "Product not found after the category sync: $($missing -join ', '). Check the titles with Get-WsusProduct."
            }
        }
    }

    $subscription = $wsus.GetSubscription()
    $products = New-Object -TypeName 'Microsoft.UpdateServices.Administration.UpdateCategoryCollection'
    $wsus.GetUpdateCategories() | Where-Object { $_.Title -in $Product } | ForEach-Object { $null = $products.Add($_) }
    $classifications = New-Object -TypeName 'Microsoft.UpdateServices.Administration.UpdateClassificationCollection'
    $wsus.GetUpdateClassifications() | Where-Object { $_.Title -in $Classification } | ForEach-Object { $null = $classifications.Add($_) }

    $subscription.SetUpdateCategories($products)
    $subscription.SetUpdateClassifications($classifications)
    $subscription.SynchronizeAutomatically = $true
    $subscription.SynchronizeAutomaticallyTimeOfDay = New-TimeSpan -Hours $FirstSyncUtcHour
    $subscription.NumberOfSynchronizationsPerDay = $SyncsPerDay
    if ($PSCmdlet.ShouldProcess($WsusServer, 'Save products, classifications and sync schedule')) {
        $subscription.Save()
    }

    # Group names must EXACTLY match the client TargetGroup.
    $existingGroups = @($wsus.GetComputerTargetGroups() | ForEach-Object Name)
    foreach ($group in $ComputerGroup) {
        if ($existingGroups -notcontains $group -and $PSCmdlet.ShouldProcess($group, 'Create computer group')) {
            $null = $wsus.CreateComputerTargetGroup($group)
        }
    }

    # Rules are created off and an existing rule keeps its state; Enable-WsusApprovalRule turns them on.
    $defaultRule = $wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq 'Default Automatic Approval Rule' }
    if ($defaultRule -and $defaultRule.Enabled -and $PSCmdlet.ShouldProcess($defaultRule.Name, 'Disable')) {
        $defaultRule.Enabled = $false
        $defaultRule.Save()
    }

    $ruleDefinitions = @(
        @{ Name = 'Auto - Critical and Security'; ClassificationTitle = 'Critical Updates', 'Security Updates'; GroupName = $CritSecGroup }
        @{ Name = 'Auto - Definition Updates'; ClassificationTitle = 'Definition Updates'; GroupName = $DefinitionGroup }
    )
    $rules = foreach ($definition in $ruleDefinitions) {
        if ($PSCmdlet.ShouldProcess($definition.Name, 'Create or update auto-approval rule')) {
            Set-WsusApprovalRuleDefinition -Wsus $wsus @definition
        }
    }
    $rules = @($rules)

    if ($ApplyRulesNow -and $rules.Count -gt 0) {
        $enabledRules = @($rules | Where-Object Enabled)
        if ($enabledRules.Count -eq 0) {
            Write-Warning -Message 'No approval rule is on, so nothing was approved. Turn rules on with Enable-WsusApprovalRule, then run again.'
        }
        elseif ($PSCmdlet.ShouldProcess('Existing updates', 'Apply auto-approval rules')) {
            Write-Verbose -Message 'Applying rules to existing updates; this can take a while'
            foreach ($rule in $enabledRules) {
                $rule.ApplyRule()
            }
        }
    }

    $nextStep = if (@($rules | Where-Object Enabled).Count -eq 0) {
        'Start-WsusSync -Wait, then Invoke-WsusMaintenance -SupersededAgeDays 0, then Enable-WsusApprovalRule'
    }
    else {
        'Start-WsusSync -Wait'
    }

    [PSCustomObject]@{
        PSTypeName = 'WSUS.UpstreamConfig'
        Server     = $WsusServer
        Upstream   = if ($UpstreamServer) { $UpstreamServer } else { 'Microsoft Update' }
        Products   = @($products | ForEach-Object Title)
        Classification = $Classification -join ', '
        Groups     = $ComputerGroup -join ', '
        Rules      = @($rules | ForEach-Object { '{0} ({1})' -f $_.Name, $(if ($_.Enabled) { 'On' } else { 'Off' }) }) -join '; '
        NextStep   = $nextStep
    }
}
