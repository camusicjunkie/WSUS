<#
.SYNOPSIS
    Configures WSUS01 as the upstream (autonomous) server: sync source, products, classifications,
    languages, schedule, client-side targeting, computer groups and auto-approval rules.

.DESCRIPTION
    Run on WSUS01 only. Everything set here (groups, approvals, declines) replicates to WSUS02 on
    its next sync, so this is the only server where approvals are ever made.

    Auto-approval rules fire at the END of each sync, for every update that arrived in that sync.
    On the first full sync that is every update Microsoft ever released for the selected products,
    so new rules are created OFF. Turn them on with -EnableRules after the first sync and a
    cleanup run of 5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0. Re-running this script
    without -EnableRules keeps each rule's current on/off state.

    Use -ApplyRulesNow to also approve the existing backlog. Only do that after the cleanup run,
    or it approves (and downloads) piles of superseded updates.

    Also used after a promotion: run it against WSUS02 once 4-Configure-WsusReplica.ps1 -Promote
    has made WSUS02 autonomous.

.EXAMPLE
    .\3-Configure-WsusUpstream.ps1 -ProxyHost proxy.corp.local -WhatIf

.EXAMPLE
    .\3-Configure-WsusUpstream.ps1 -ProxyHost proxy.corp.local -EnableRules -ApplyRulesNow
    After the first sync and cleanup: turn the rules on and approve the current updates.
#>
#Requires -Version 5.1
#Requires -Modules UpdateServices
[CmdletBinding(SupportsShouldProcess)]
param (
    # Node FQDN to connect to. Defaults to this node.
    [string] $WsusServer = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName,

    # WSUS API port on the node.
    [int] $Port = 8531,

    # Leave empty to sync from Microsoft Update. Set a server to chain downstream (e.g. DISA).
    [string] $UpstreamServer,

    # Port on the upstream server. 8531 turns on SSL.
    [int] $UpstreamPort = 8531,

    # Proxy for Microsoft Update. Leave empty for a direct connection.
    [string] $ProxyHost,

    # Proxy port.
    [int] $ProxyPort = 8080,

    # Product titles to sync. Must match the console titles exactly.
    [string[]] $Product = @(
        'Windows 11'
        'Microsoft Server Operating System-21H2'   # Server 2022
        'Microsoft Server Operating System-24H2'   # Server 2025
        'Microsoft Defender Antivirus'             # Definition updates
    ),

    # Update classifications to sync.
    [string[]] $Classification = @('Critical Updates', 'Security Updates', 'Definition Updates'),

    # WSUS computer groups to create. Must match client TargetGroup values exactly.
    [string[]] $ComputerGroup = @('Packer', 'Pilot', 'Workstations', 'Servers', 'VDI-Definitions'),

    # Groups that auto-approve Critical and Security updates at sync. Workstations and Servers are
    # approved later with 8-Approve-WsusRing.ps1, once Pilot passes its gate.
    [string[]] $CritSecGroup = @('Packer', 'Pilot'),

    # Groups that auto-approve Definition Updates. Servers are left out: definitions are for Windows 11.
    [string[]] $DefinitionGroup = @('Packer', 'Pilot', 'Workstations', 'VDI-Definitions'),

    # Automatic syncs per day.
    [ValidateRange(1, 24)]
    [int] $SyncsPerDay = 2,

    # Hour of the first daily sync, in UTC. The replica syncs two hours later.
    [ValidateRange(0, 23)]
    [int] $FirstSyncUtcHour = 2,

    # Turn the auto-approval rules on. Leave off for the first full sync.
    [switch] $EnableRules,

    # Also approve the existing backlog. Run 5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0 first.
    [switch] $ApplyRulesNow
)

begin {
    $ErrorActionPreference = 'Stop'
    $adminNamespace = 'Microsoft.UpdateServices.Administration'


    function Get-ClassificationCollection {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            $Server,

            [Parameter(Mandatory)]
            [string[]] $Title
        )

        $collection = New-Object -TypeName "$adminNamespace.UpdateClassificationCollection"
        $Server.GetUpdateClassifications() |
            Where-Object { $_.Title -in $Title } |
            ForEach-Object { $null = $collection.Add($_) }
        Write-Output -InputObject $collection -NoEnumerate
    }


    function Set-WsusApprovalRule {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory)]
            $Server,

            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string[]] $ClassificationTitle,

            [Parameter(Mandatory)]
            [string[]] $GroupName,

            # Turn the rule on. Without it, a new rule is created off and an existing rule keeps its state.
            [switch] $Enable
        )

        if (-not $PSCmdlet.ShouldProcess($Name, 'Create or update auto-approval rule')) {
            return
        }

        $rule = $Server.GetInstallApprovalRules() | Where-Object { $_.Name -eq $Name }
        $isNew = -not $rule
        if ($isNew) {
            $rule = $Server.CreateInstallApprovalRule($Name)
        }
        $rule.SetUpdateClassifications((Get-ClassificationCollection -Server $Server -Title $ClassificationTitle))

        $targets = New-Object -TypeName "$adminNamespace.ComputerTargetGroupCollection"
        $Server.GetComputerTargetGroups() |
            Where-Object { $_.Name -in $GroupName } |
            ForEach-Object { $null = $targets.Add($_) }
        $rule.SetComputerTargetGroups($targets)
        if ($isNew -or $Enable) {
            $rule.Enabled = [bool]$Enable
        }
        $rule.Save()
        $rule
    }
}

end {
    $wsus = Get-WsusServer -Name $WsusServer -PortNumber $Port -UseSsl
    $config = $wsus.GetConfiguration()

    if ($config.IsReplicaServer) {
        throw "$WsusServer is a replica. Promote it first with 4-Configure-WsusReplica.ps1 -Promote."
    }

    # --- Sync source, proxy and storage behaviour --------------------------------------------
    if ($UpstreamServer) {
        $config.SyncFromMicrosoftUpdate = $false
        $config.UpstreamWsusServerName = $UpstreamServer
        $config.UpstreamWsusServerPortNumber = $UpstreamPort
        $config.UpstreamWsusServerUseSsl = ($UpstreamPort -eq 8531)
    } else {
        $config.SyncFromMicrosoftUpdate = $true
    }
    $config.UseProxy = [bool]$ProxyHost
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

    # --- Categories-only sync so the product list is populated -------------------------------
    $subscription = $wsus.GetSubscription()
    if ($PSCmdlet.ShouldProcess($WsusServer, 'Run categories-only sync')) {
        Write-Verbose -Message 'Running categories-only sync'
        $subscription.StartSynchronizationForCategoryOnly()
        $deadline = (Get-Date).AddMinutes(30)
        do {
            Start-Sleep -Seconds 15
            if ((Get-Date) -gt $deadline) {
                throw 'Categories-only sync did not finish within 30 minutes.'
            }
        } while ($subscription.GetSynchronizationStatus() -ne 'NotProcessing')
    }

    # --- Products and classifications -------------------------------------------------------
    $allCategories = $wsus.GetUpdateCategories()
    $products = New-Object -TypeName "$adminNamespace.UpdateCategoryCollection"
    foreach ($title in $Product) {
        $match = $allCategories | Where-Object { $_.Title -eq $title }
        if ($match) {
            $null = $products.Add($match)
        } else {
            Write-Warning -Message "Product not found: '$title'. Check the title with Get-WsusProduct."
        }
    }

    $subscription.SetUpdateCategories($products)
    $subscription.SetUpdateClassifications((Get-ClassificationCollection -Server $wsus -Title $Classification))
    $subscription.SynchronizeAutomatically = $true
    $subscription.SynchronizeAutomaticallyTimeOfDay = New-TimeSpan -Hours $FirstSyncUtcHour
    $subscription.NumberOfSynchronizationsPerDay = $SyncsPerDay
    if ($PSCmdlet.ShouldProcess($WsusServer, 'Save products, classifications and sync schedule')) {
        $subscription.Save()
    }

    # --- Computer groups (names must EXACTLY match the client TargetGroup) --------------------
    $existingGroups = $wsus.GetComputerTargetGroups().Name
    foreach ($group in $ComputerGroup) {
        if ($existingGroups -notcontains $group -and $PSCmdlet.ShouldProcess($group, 'Create computer group')) {
            $null = $wsus.CreateComputerTargetGroup($group)
        }
    }

    # --- Auto-approval rules ------------------------------------------------------------------
    $defaultRule = $wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq 'Default Automatic Approval Rule' }
    if ($defaultRule -and $PSCmdlet.ShouldProcess($defaultRule.Name, 'Disable')) {
        $defaultRule.Enabled = $false
        $defaultRule.Save()
    }

    $critSecParams = @{
        Server              = $wsus
        Name                = 'Auto - Critical and Security'
        ClassificationTitle = 'Critical Updates', 'Security Updates'
        GroupName           = $CritSecGroup
        Enable              = $EnableRules
    }
    $definitionParams = @{
        Server              = $wsus
        Name                = 'Auto - Definition Updates'
        ClassificationTitle = 'Definition Updates'
        GroupName           = $DefinitionGroup
        Enable              = $EnableRules
    }
    $rules = @(
        Set-WsusApprovalRule @critSecParams
        Set-WsusApprovalRule @definitionParams
    )

    if ($ApplyRulesNow -and $PSCmdlet.ShouldProcess('Existing updates', 'Apply auto-approval rules')) {
        Write-Verbose -Message 'Applying rules to existing updates; this can take a while'
        foreach ($rule in $rules) {
            $rule.ApplyRule()
        }
    }

    $ruleState = $rules | ForEach-Object { '{0} ({1})' -f $_.Name, ('Off', 'On')[[int]$_.Enabled] }

    [PSCustomObject]@{
        Server         = $WsusServer
        Upstream       = if ($UpstreamServer) { $UpstreamServer } else { 'Microsoft Update' }
        Products       = $products.Count
        Classification = $Classification -join ', '
        Groups         = $ComputerGroup -join ', '
        Rules          = $ruleState -join '; '
        NextStep       = 'Start a full sync: (Get-WsusServer).GetSubscription().StartSynchronization()'
    }
}
