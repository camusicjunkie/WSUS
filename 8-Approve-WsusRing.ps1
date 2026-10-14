<#
.SYNOPSIS
    Promotes approved updates from one WSUS computer group to the next: by default Pilot to
    Workstations and Servers.

.DESCRIPTION
    Run on the upstream (WSUS01) only; the replica copies the approvals on its next sync.

    For every Critical or Security update approved for install to -From and not yet approved for
    a -To group, the script checks the gate:
      - the update has been approved for -From for at least -MinimumSoakDays
      - at least one -From computer needed it (so the pilot actually tested it)
      - at least -MinimumInstalledPercent of the -From computers that need it have it installed
        (installed and installed-pending-reboot both count)
      - no -From computer failed to install it
    Updates that pass are approved for each -To group. Updates that fail are held and reported
    with the reason. -Force approves held updates anyway.

    Declined and superseded updates are never promoted. Definition updates skip the rings; the
    auto-approval rule sends them straight to their groups.

    Approve on the Tuesday of week 2: Workstations install Wednesday 19:00 and Servers Thursday
    19:00, per the GPO schedule.

.EXAMPLE
    .\8-Approve-WsusRing.ps1 -WhatIf
    Shows the gate result for every candidate update without approving anything.

.EXAMPLE
    .\8-Approve-WsusRing.ps1 | Format-Table -AutoSize

.EXAMPLE
    .\8-Approve-WsusRing.ps1 -MinimumSoakDays 1 -Force
    Out-of-band update: promote everything Pilot has, after one day.
#>
#Requires -Version 5.1
#Requires -Modules UpdateServices
[CmdletBinding(SupportsShouldProcess)]
param (
    # Group whose approvals are promoted.
    [string] $From = 'Pilot',

    # Group(s) that receive the approvals.
    [string[]] $To = @('Workstations', 'Servers'),

    # Classifications to promote.
    [string[]] $Classification = @('Critical Updates', 'Security Updates'),

    # Days an update must have been approved for -From before it can be promoted.
    [ValidateRange(0, 60)]
    [int] $MinimumSoakDays = 5,

    # Percent of the -From computers that need the update that must have it installed.
    [ValidateRange(0, 100)]
    [int] $MinimumInstalledPercent = 90,

    # Approve updates that fail the gate.
    [switch] $Force,

    # Node FQDN to connect to. Defaults to this node.
    [string] $WsusServer = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName,

    # WSUS API port on the node.
    [int] $Port = 8531
)

begin {
    $ErrorActionPreference = 'Stop'
    $adminNamespace = 'Microsoft.UpdateServices.Administration'
}

end {
    $wsus = Get-WsusServer -Name $WsusServer -PortNumber $Port -UseSsl
    if ($wsus.GetConfiguration().IsReplicaServer) {
        throw "$WsusServer is a replica. Approve on the upstream; the replica copies the approvals."
    }

    # --- Resolve groups and classifications --------------------------------------------------
    $allGroups = $wsus.GetComputerTargetGroups()
    $fromGroup = $allGroups | Where-Object { $_.Name -eq $From }
    if (-not $fromGroup) {
        throw "Computer group '$From' not found."
    }
    $toGroups = foreach ($name in $To) {
        $match = $allGroups | Where-Object { $_.Name -eq $name }
        if (-not $match) {
            throw "Computer group '$name' not found."
        }
        $match
    }

    $scope = New-Object -TypeName "$adminNamespace.UpdateScope"
    $scope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved
    $scope.UpdateApprovalActions = [Microsoft.UpdateServices.Administration.UpdateApprovalActions]::Install
    $null = $scope.ApprovedComputerTargetGroups.Add($fromGroup)
    $wsus.GetUpdateClassifications() |
        Where-Object { $_.Title -in $Classification } |
        ForEach-Object { $null = $scope.Classifications.Add($_) }
    if ($scope.Classifications.Count -eq 0) {
        throw "None of the classifications were found: $($Classification -join ', ')"
    }

    # --- Gate and promote --------------------------------------------------------------------
    $soakCutoff = [datetime]::UtcNow.AddDays(-$MinimumSoakDays)
    $installAction = [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install

    foreach ($update in $wsus.GetUpdates($scope)) {
        if ($update.IsDeclined -or $update.IsSuperseded) {
            continue
        }

        $pendingGroups = @($toGroups | Where-Object { $update.GetUpdateApprovals($_).Count -eq 0 })
        if ($pendingGroups.Count -eq 0) {
            continue
        }

        $approvedOn = ($update.GetUpdateApprovals($fromGroup) | Sort-Object -Property CreationDate |
            Select-Object -First 1).CreationDate
        $summary = $update.GetSummaryForComputerTargetGroup($fromGroup)
        $installed = $summary.InstalledCount + $summary.InstalledPendingRebootCount
        $needed = $installed + $summary.NotInstalledCount + $summary.DownloadedCount + $summary.FailedCount
        $percent = if ($needed -gt 0) { [math]::Floor(100 * $installed / $needed) } else { 0 }

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($approvedOn -gt $soakCutoff) {
            $reasons.Add(('approved for {0} on {1:yyyy-MM-dd}, soak not finished' -f $From, $approvedOn))
        }
        if ($needed -eq 0) {
            $reasons.Add("no $From computer needed it, so it was never tested")
        } elseif ($percent -lt $MinimumInstalledPercent) {
            $reasons.Add("only $percent% installed in $From")
        }
        if ($summary.FailedCount -gt 0) {
            $reasons.Add("$($summary.FailedCount) failed in $From")
        }

        $gate = if ($reasons.Count -eq 0) { 'Passed' } elseif ($Force) { 'Forced' } else { 'Held' }
        $approvedTo = [System.Collections.Generic.List[string]]::new()

        if ($gate -ne 'Held') {
            foreach ($group in $pendingGroups) {
                if ($PSCmdlet.ShouldProcess($update.Title, "Approve for install to $($group.Name)")) {
                    if ($update.RequiresLicenseAgreementAcceptance) {
                        $update.AcceptLicenseAgreement()
                    }
                    $null = $update.Approve($installAction, $group)
                    $approvedTo.Add($group.Name)
                }
            }
        }

        [PSCustomObject]@{
            Update     = $update.Title
            Kb         = $update.KnowledgebaseArticles -join ', '
            Installed  = '{0}/{1}' -f $installed, $needed
            Failed     = $summary.FailedCount
            Gate       = $gate
            Reason     = $reasons -join '; '
            ApprovedTo = $approvedTo -join ', '
        }
    }
}
