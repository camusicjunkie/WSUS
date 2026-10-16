function Approve-WsusRing {
    <#
    .SYNOPSIS
        Promotes approved updates from one ring to the next, only when they pass the gate.
    .DESCRIPTION
        Upstream only; works locally or remotely. The replica copies the approvals on its next sync.

        For every update in -Classification approved for install to -From, the gate is checked:
          - the earliest -From approval is at least -MinimumSoakDays old
          - at least one -From computer needed the update (so it was actually tested)
          - at least -MinimumInstalledPercent of the -From computers that need it have it installed
            (installed and installed-pending-reboot both count; the percent is floored)
          - no -From computer failed to install it
        Updates that pass are approved for install, with no deadline, for each -To group that does not
        have an approval yet. Updates that fail are held. -Force approves held updates anyway and the
        row shows Gate = Forced. Declined and superseded updates are skipped. Definition updates skip
        the rings: the approval rule sends them straight to their groups.

        One row per candidate update is returned. If any update was held, a single warning at the end
        gives the count and names -Force and -WhatIf. -WhatIf returns the full gate table without
        approving anything; -Confirm prompts for each update and group.

        Approve on the Tuesday of week 2: Workstations install Wednesday and Servers Thursday, as set
        by the client GPO schedule.
    .EXAMPLE
        Approve-WsusRing -WhatIf
        Shows the gate result for every candidate update without approving anything.
    .EXAMPLE
        Approve-WsusRing | Format-Table -AutoSize
        Promotes Pilot approvals to Workstations and Servers (week 2 Tuesday) and shows the outcome.
    .EXAMPLE
        Approve-WsusRing -MinimumSoakDays 1 -Force
        Out-of-band update: promote everything Pilot has after one day, bypassing the gate.
    .OUTPUTS
        WSUS.RingApproval
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.RingApproval')]
    param (
        # Group whose approvals are promoted. Default Pilot.
        [string] $From = (Get-WsusRingPlan).Promotion.From,

        # Group or groups that receive the approvals. Default Workstations and Servers.
        [string[]] $To = (Get-WsusRingPlan).Promotion.To,

        # Update classifications to promote. Default Critical Updates and Security Updates (those the
        # Critical and Security approval rule approves).
        [string[]] $Classification = (Get-WsusRingPlan).Promotion.ClassificationTitle,

        # Days an update must have been approved for -From before it can be promoted. Default 5.
        [ValidateRange(0, 60)]
        [int] $MinimumSoakDays = 5,

        # Percent of the -From computers that need the update that must have it installed. Default 90.
        [ValidateRange(0, 100)]
        [int] $MinimumInstalledPercent = 90,

        # Approve updates that fail the gate.
        [switch] $Force,

        # Upstream to connect to. Defaults to this node's FQDN.
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531
    )

    Assert-WsusPrerequisite -Module UpdateServices
    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port

    Assert-WsusUpstream -Wsus $wsus -Instead 'Approve on the upstream; the replica copies the approvals.'

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

    $scope = New-Object -TypeName 'Microsoft.UpdateServices.Administration.UpdateScope'
    $scope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved
    $scope.UpdateApprovalActions = [Microsoft.UpdateServices.Administration.UpdateApprovalActions]::Install
    $null = $scope.ApprovedComputerTargetGroups.Add($fromGroup)
    $wsus.GetUpdateClassifications() |
        Where-Object { $_.Title -in $Classification } |
        ForEach-Object { $null = $scope.Classifications.Add($_) }
    if ($scope.Classifications.Count -eq 0) {
        throw "None of the classifications were found: $($Classification -join ', ')"
    }

    $soakCutoff = [datetime]::Now.AddDays(-$MinimumSoakDays)
    $held = 0
    $installAction = [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install

    foreach ($update in $wsus.GetUpdates($scope)) {
        if ($update.IsDeclined -or $update.IsSuperseded) {
            continue
        }

        $pendingGroups = @($toGroups | Where-Object { @($update.GetUpdateApprovals($_)).Count -eq 0 })
        if ($pendingGroups.Count -eq 0) {
            continue
        }

        $summary = $update.GetSummaryForComputerTargetGroup($fromGroup)
        $installed = $summary.InstalledCount + $summary.InstalledPendingRebootCount
        $needed = $installed + $summary.NotInstalledCount + $summary.DownloadedCount + $summary.FailedCount
        $percent = if ($needed -gt 0) { [int] [math]::Floor(100 * $installed / $needed) } else { 0 }

        $approvedOn = ($update.GetUpdateApprovals($fromGroup) | Sort-Object -Property CreationDate |
            Select-Object -First 1).CreationDate

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($approvedOn -gt $soakCutoff) {
            $reasons.Add(('approved for {0} on {1:yyyy-MM-dd}, soak not finished' -f $From, $approvedOn))
        }
        if ($needed -eq 0) {
            $reasons.Add("no $From computer needed it, so it was never tested")
        }
        elseif ($percent -lt $MinimumInstalledPercent) {
            $reasons.Add("only $percent% installed in $From")
        }
        if ($summary.FailedCount -gt 0) {
            $reasons.Add("$($summary.FailedCount) failed in $From")
        }

        $gate = if ($reasons.Count -eq 0) { 'Passed' } elseif ($Force) { 'Forced' } else { 'Held' }
        if ($gate -eq 'Held') { $held++ }

        $approvedTo = [System.Collections.Generic.List[string]]::new()
        foreach ($group in $pendingGroups) {
            if ($gate -ne 'Held' -and $PSCmdlet.ShouldProcess($update.Title, "Approve for install to $($group.Name)")) {
                if ($update.RequiresLicenseAgreementAcceptance) {
                    $update.AcceptLicenseAgreement()
                }
                $null = $update.Approve($installAction, $group)
                $approvedTo.Add($group.Name)
            }
        }

        [PSCustomObject] @{
            PSTypeName = 'WSUS.RingApproval'
            Update     = $update.Title
            Kb         = @($update.KnowledgebaseArticles) -join ', '
            Installed  = $installed
            Needed     = $needed
            Percent    = $percent
            Failed     = [int] $summary.FailedCount
            Gate       = $gate
            Reason     = $reasons.ToArray()
            ApprovedTo = $approvedTo.ToArray()
        }
    }

    if ($held -gt 0) {
        Write-Warning "$held update(s) were held by the gate and not approved. Re-run with -Force to approve them anyway, or use -WhatIf to review the gate table first."
    }
}
