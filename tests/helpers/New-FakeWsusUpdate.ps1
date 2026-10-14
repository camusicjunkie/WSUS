function New-FakeWsusUpdate {
    <#
    .SYNOPSIS
        Builds a fake IUpdate for Approve-WsusRing tests and adds it to a fake server's Updates.
    .DESCRIPTION
        -ApprovedFor maps a group name to the date the update was approved for that group. The summary
        counts describe the -From group. Approve() records 'Approve <title> -> <group>' on the server's
        Calls and adds an approval, so tests assert effects on the fake.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds an in-memory object.')]
    param (
        [Parameter(Mandatory)]
        $Server,

        [string] $Title = 'Security Update for Windows (KB5000001)',
        [string[]] $Kb = @('5000001'),
        [hashtable] $ApprovedFor = @{ Pilot = (Get-Date).AddDays(-10) },
        [int] $Installed = 9,
        [int] $InstalledPendingReboot = 0,
        [int] $NotInstalled = 0,
        [int] $Downloaded = 0,
        [int] $Failed = 0,
        [bool] $IsDeclined = $false,
        [bool] $IsSuperseded = $false,
        [bool] $RequiresLicense = $false
    )

    $approvals = @{}
    foreach ($name in $ApprovedFor.Keys) {
        $approvals[$name] = [System.Collections.Generic.List[object]]::new()
        $approvals[$name].Add([PSCustomObject] @{ CreationDate = [datetime] $ApprovedFor[$name] })
    }

    $update = [PSCustomObject] @{
        Title                              = $Title
        KnowledgebaseArticles              = $Kb
        IsDeclined                         = $IsDeclined
        IsSuperseded                       = $IsSuperseded
        RequiresLicenseAgreementAcceptance = $RequiresLicense
        Approvals                          = $approvals
        Calls                              = $Server.Calls
        Summary                            = [PSCustomObject] @{
            InstalledCount              = $Installed
            InstalledPendingRebootCount = $InstalledPendingReboot
            NotInstalledCount           = $NotInstalled
            DownloadedCount             = $Downloaded
            FailedCount                 = $Failed
        }
    }
    $update | Add-Member -MemberType ScriptMethod -Name GetUpdateApprovals -Value {
        param ($group)
        if ($this.Approvals.ContainsKey($group.Name)) { $this.Approvals[$group.Name].ToArray() }
    }
    $update | Add-Member -MemberType ScriptMethod -Name GetSummaryForComputerTargetGroup -Value {
        param ($group) $this.Summary
    }
    $update | Add-Member -MemberType ScriptMethod -Name AcceptLicenseAgreement -Value {
        $this.Calls.Add("AcceptLicenseAgreement $($this.Title)")
    }
    $update | Add-Member -MemberType ScriptMethod -Name Approve -Value {
        param ($action, $group)
        $this.Calls.Add("Approve $($this.Title) -> $($group.Name) ($action)")
        if (-not $this.Approvals.ContainsKey($group.Name)) {
            $this.Approvals[$group.Name] = [System.Collections.Generic.List[object]]::new()
        }
        $this.Approvals[$group.Name].Add([PSCustomObject] @{ CreationDate = Get-Date })
    }

    $Server.Updates.Add($update)
    $update
}
