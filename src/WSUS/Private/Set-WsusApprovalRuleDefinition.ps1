function Set-WsusApprovalRuleDefinition {
    <#
    .SYNOPSIS
        Creates or updates an auto-approval rule's classifications and target groups and returns the rule.
    .DESCRIPTION
        A new rule is created off. An existing rule keeps its on/off state: turning rules on is
        Enable-WsusApprovalRule. Does not call ShouldProcess; the public caller does.
    .PARAMETER Wsus
        The IUpdateServer returned by Connect-WsusNode.
    .PARAMETER Name
        Rule name.
    .PARAMETER ClassificationTitle
        Titles of the update classifications the rule approves.
    .PARAMETER GroupName
        Names of the computer groups the rule approves for.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper; the public caller wraps it in ShouldProcess.')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Wsus,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string[]] $ClassificationTitle,

        [Parameter(Mandatory)]
        [string[]] $GroupName
    )

    $rule = $Wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq $Name }
    $isNew = -not $rule
    if ($isNew) {
        $rule = $Wsus.CreateInstallApprovalRule($Name)
    }

    $classifications = New-Object -TypeName 'Microsoft.UpdateServices.Administration.UpdateClassificationCollection'
    $Wsus.GetUpdateClassifications() | Where-Object { $_.Title -in $ClassificationTitle } | ForEach-Object { $null = $classifications.Add($_) }
    $rule.SetUpdateClassifications($classifications)

    $targets = New-Object -TypeName 'Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection'
    $Wsus.GetComputerTargetGroups() | Where-Object { $_.Name -in $GroupName } | ForEach-Object { $null = $targets.Add($_) }
    $rule.SetComputerTargetGroups($targets)

    if ($isNew) {
        $rule.Enabled = $false
    }
    $rule.Save()
    $rule
}
