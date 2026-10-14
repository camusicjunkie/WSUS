<#
.SYNOPSIS
    Creates or updates the WSUS client GPOs: Workstations, Servers, Pilot and (optionally) VDI.

.DESCRIPTION
    Run from an admin workstation with the GroupPolicy RSAT module. Idempotent: existing GPOs,
    values and links are updated in place.

        WSUS - Workstations   linked to -WorkstationOU   TargetGroup Workstations   Wednesday 19:00
        WSUS - Servers        linked to -ServerOU        TargetGroup Servers        Thursday 19:00
        WSUS - Pilot          linked to both, order 1    TargetGroup Pilot          Thursday 19:00
                              filtered to -PilotGroup
        WSUS - VDI            linked to -VdiOU           TargetGroup VDI-Definitions  definitions only

    Every machine gets Workstations or Servers by default. The Pilot GPO has the highest link order
    and is security-filtered, so its values win only for computers in -PilotGroup. Moving a machine
    in or out of Pilot is just a group membership change (the computer picks it up after a reboot).

    Clients download approved updates in the background and install them at the scheduled time,
    then restart after -RestartWarningMinutes even if a user is signed in. Approvals decide WHAT a
    group installs; the schedule decides WHEN.

    The VDI GPO is for non-persistent Citrix VDAs. Their OS patches come from the golden image, so
    automatic updates are turned off and only Defender pulls security intelligence from WSUS. Linked
    at the VDA OU, it outranks the Workstations GPO even if that OU sits under a workstation OU.
    The VDA image must leave the Windows Update service (wuauserv) at Manual, not Disabled, or
    Defender can't reach WSUS.

    Packer builds are not covered here: the Ansible configure_update role registers them with
    TargetGroup 'Packer' during the build.

.EXAMPLE
    $params = @{
        WorkstationOU = 'OU=Workstations,DC=corp,DC=local'
        ServerOU      = 'OU=Servers,DC=corp,DC=local'
    }
    .\7-New-WsusClientGpo.ps1 @params -WhatIf
#>
#Requires -Version 5.1
#Requires -Modules GroupPolicy
[CmdletBinding(SupportsShouldProcess)]
param (
    # Distinguished names of the OUs that hold workstations.
    [Parameter(Mandatory)]
    [string[]] $WorkstationOU,

    # Distinguished names of the OUs that hold servers.
    [Parameter(Mandatory)]
    [string[]] $ServerOU,

    # Distinguished names of the OUs that hold non-persistent Citrix VDAs. Leave out to skip the VDI GPO.
    [string[]] $VdiOU,

    # WSUS computer group for the VDAs. Only definition updates are approved for it.
    [string] $VdiTargetGroup = 'VDI-Definitions',

    # Hours between Defender security intelligence checks on the VDAs.
    [ValidateRange(1, 24)]
    [int] $VdiSignatureIntervalHours = 4,

    # Resource group that the Pilot GPO is filtered to. It holds the id group(s) of pilot computers.
    [string] $PilotGroup = 'res.ent.wsus.pilot',

    # WSUS URL through the NetScaler VIP.
    [ValidatePattern('^https://[^/]+:\d+$')]
    [string] $WsusUrl = 'https://wsus.corp.local:8531',

    # Prefix for the GPO names.
    [string] $GpoPrefix = 'WSUS - ',

    # Install day for the Workstations GPO.
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string] $WorkstationInstallDay = 'Wednesday',

    # Install day for the Servers GPO.
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string] $ServerInstallDay = 'Thursday',

    # Install day for the Pilot GPO.
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string] $PilotInstallDay = 'Thursday',

    # Install hour (0-23, client local time). The start of the maintenance window.
    [ValidateRange(0, 23)]
    [int] $InstallHour = 19,

    # Minutes of warning before the restart that follows a scheduled install.
    [ValidateRange(15, 180)]
    [int] $RestartWarningMinutes = 15,

    # Hours between scans. 22 spreads a few thousand clients out.
    [ValidateRange(1, 22)]
    [int] $DetectionFrequencyHours = 22
)

begin {
    $ErrorActionPreference = 'Stop'

    $policyKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auKey = '{0}\AU' -f $policyKey
    $defenderKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'
    $dayNumber = @{
        Sunday    = 1
        Monday    = 2
        Tuesday   = 3
        Wednesday = 4
        Thursday  = 5
        Friday    = 6
        Saturday  = 7
    }

    $gpoDefinitions = @(
        @{
            Name        = '{0}Workstations' -f $GpoPrefix
            TargetGroup = 'Workstations'
            Day         = $WorkstationInstallDay
            Links       = $WorkstationOU
            LinkOrder   = $null
            FilterGroup = $null
            Definitions = $false
        }
        @{
            Name        = '{0}Servers' -f $GpoPrefix
            TargetGroup = 'Servers'
            Day         = $ServerInstallDay
            Links       = $ServerOU
            LinkOrder   = $null
            FilterGroup = $null
            Definitions = $false
        }
        @{
            Name        = '{0}Pilot' -f $GpoPrefix
            TargetGroup = 'Pilot'
            Day         = $PilotInstallDay
            Links       = $WorkstationOU + $ServerOU
            LinkOrder   = 1
            FilterGroup = $PilotGroup
            Definitions = $false
        }
    )
    if ($VdiOU) {
        $gpoDefinitions += @{
            Name        = '{0}VDI' -f $GpoPrefix
            TargetGroup = $VdiTargetGroup
            Day         = $null
            Links       = $VdiOU
            LinkOrder   = $null
            FilterGroup = $null
            Definitions = $true
        }
    }


    function Get-WsusPolicyValue {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string] $TargetGroup,

            # Scheduled install day (1 = Sunday ... 7 = Saturday). Ignored with -DefinitionsOnly.
            [int] $InstallDay,

            # Turn off automatic updates and let Defender pull security intelligence from WSUS.
            [switch] $DefinitionsOnly
        )

        # Short local names keep each policy value on one line
        $wu = $policyKey
        $au = $auKey
        $df = $defenderKey
        $sz = 'String'
        $dw = 'DWord'
        $warn = $RestartWarningMinutes
        $sigHours = $VdiSignatureIntervalHours

        # Common to every GPO: where WSUS is, which group, and never Windows Update directly
        @(
            @{ Key = $wu; ValueName = 'WUServer'; Value = $WsusUrl; Type = $sz }
            @{ Key = $wu; ValueName = 'WUStatusServer'; Value = $WsusUrl; Type = $sz }
            @{ Key = $wu; ValueName = 'TargetGroupEnabled'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'TargetGroup'; Value = $TargetGroup; Type = $sz }
            @{ Key = $wu; ValueName = 'DoNotConnectToWindowsUpdateInternetLocations'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'DisableDualScan'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'SetPolicyDrivenUpdateSourceForQualityUpdates'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'SetPolicyDrivenUpdateSourceForFeatureUpdates'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'SetPolicyDrivenUpdateSourceForDriverUpdates'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'SetPolicyDrivenUpdateSourceForOtherUpdates'; Value = 1; Type = $dw }
            @{ Key = $wu; ValueName = 'ExcludeWUDriversInQualityUpdate'; Value = 1; Type = $dw }
            @{ Key = $au; ValueName = 'UseWUServer'; Value = 1; Type = $dw }
        )

        if ($DefinitionsOnly) {
            @(
                @{ Key = $au; ValueName = 'NoAutoUpdate'; Value = 1; Type = $dw }
                @{ Key = $df; ValueName = 'FallbackOrder'; Value = 'InternalDefinitionUpdateServer'; Type = $sz }
                @{ Key = $df; ValueName = 'SignatureUpdateInterval'; Value = $sigHours; Type = $dw }
                @{ Key = $df; ValueName = 'UpdateOnStartUp'; Value = 1; Type = $dw }
            )
            return
        }

        @(
            @{ Key = $au; ValueName = 'NoAutoUpdate'; Value = 0; Type = $dw }
            @{ Key = $au; ValueName = 'AUOptions'; Value = 4; Type = $dw }
            @{ Key = $au; ValueName = 'ScheduledInstallDay'; Value = $InstallDay; Type = $dw }
            @{ Key = $au; ValueName = 'ScheduledInstallTime'; Value = $InstallHour; Type = $dw }
            @{ Key = $au; ValueName = 'ScheduledInstallEveryWeek'; Value = 1; Type = $dw }
            @{ Key = $au; ValueName = 'AlwaysAutoRebootAtScheduledTime'; Value = 1; Type = $dw }
            @{ Key = $au; ValueName = 'AlwaysAutoRebootAtScheduledTimeMinutes'; Value = $warn; Type = $dw }
            @{ Key = $au; ValueName = 'DetectionFrequencyEnabled'; Value = 1; Type = $dw }
            @{ Key = $au; ValueName = 'DetectionFrequency'; Value = $DetectionFrequencyHours; Type = $dw }
        )
    }
}

end {
    foreach ($definition in $gpoDefinitions) {
        $gpoName = $definition.Name

        # --- GPO ---------------------------------------------------------------------------------
        $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if (-not $gpo -and $PSCmdlet.ShouldProcess($gpoName, 'Create GPO')) {
            $gpo = New-GPO -Name $gpoName -Comment 'WSUS client settings. Managed by 7-New-WsusClientGpo.ps1.'
        }
        if (-not $gpo) {
            Write-Verbose -Message "WhatIf: $gpoName does not exist yet, skipping its settings"
            continue
        }
        if ($gpo.GpoStatus -ne 'UserSettingsDisabled' -and
            $PSCmdlet.ShouldProcess($gpoName, 'Disable user settings')) {
            $gpo.GpoStatus = 'UserSettingsDisabled'
        }

        # --- Policy values -----------------------------------------------------------------------
        $policyParams = @{ TargetGroup = $definition.TargetGroup }
        if ($definition.Definitions) {
            $policyParams['DefinitionsOnly'] = $true
        } else {
            $policyParams['InstallDay'] = $dayNumber[$definition.Day]
        }
        $values = @(Get-WsusPolicyValue @policyParams)
        if ($PSCmdlet.ShouldProcess($gpoName, "Write $($values.Count) Windows Update policy values")) {
            foreach ($value in $values) {
                $null = Set-GPRegistryValue -Name $gpoName @value
            }
        }

        # --- Security filtering (Pilot only) ----------------------------------------------------
        if ($definition.FilterGroup -and
            $PSCmdlet.ShouldProcess($gpoName, "Filter to $($definition.FilterGroup)")) {
            $applyParams = @{
                Name            = $gpoName
                TargetName      = $definition.FilterGroup
                TargetType      = 'Group'
                PermissionLevel = 'GpoApply'
            }
            $null = Set-GPPermission @applyParams

            # Authenticated Users keeps Read (needed since MS16-072) but loses Apply
            $readParams = @{
                Name            = $gpoName
                TargetName      = 'Authenticated Users'
                TargetType      = 'Group'
                PermissionLevel = 'GpoRead'
                Replace         = $true
            }
            $null = Set-GPPermission @readParams
        }

        # --- Links -------------------------------------------------------------------------------
        foreach ($ou in $definition.Links) {
            $link = (Get-GPInheritance -Target $ou).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
            if (-not $link) {
                if ($PSCmdlet.ShouldProcess($ou, "Link $gpoName")) {
                    $linkParams = @{
                        Name        = $gpoName
                        Target      = $ou
                        LinkEnabled = 'Yes'
                    }
                    if ($definition.LinkOrder) {
                        $linkParams['Order'] = $definition.LinkOrder
                    }
                    $null = New-GPLink @linkParams
                }
            } elseif ($definition.LinkOrder -and $link.Order -ne $definition.LinkOrder -and
                $PSCmdlet.ShouldProcess($ou, "Move $gpoName to link order $($definition.LinkOrder)")) {
                $null = Set-GPLink -Name $gpoName -Target $ou -Order $definition.LinkOrder
            }
        }

        [PSCustomObject]@{
            Gpo         = $gpoName
            TargetGroup = $definition.TargetGroup
            Install     = if ($definition.Definitions) {
                'Definitions only, every {0} h and at startup' -f $VdiSignatureIntervalHours
            } else {
                '{0} {1:00}:00' -f $definition.Day, $InstallHour
            }
            FilteredTo  = if ($definition.FilterGroup) { $definition.FilterGroup } else { 'Authenticated Users' }
            LinkedTo    = $definition.Links -join '; '
        }
    }
}
