function Set-WsusApprovalRuleState {
    <#
    .SYNOPSIS
        Turns the approval rules whose name matches on or off and returns one result per matching rule.
    .DESCRIPTION
        The shared body of Enable-WsusApprovalRule and Disable-WsusApprovalRule. A rule already in the
        state is skipped (no save) and reported with Changed = $false. Honours the caller's
        -WhatIf/-Confirm (one ShouldProcess per rule); a rule skipped that way is reported unchanged.
        The caller connects, checks the node is an Upstream and passes the rules it fetched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.ApprovalRule')]
    param (
        # IInstallApprovalRule objects, from GetInstallApprovalRules().
        [AllowEmptyCollection()]
        [object[]] $Rule = @(),

        # Rule names; wildcards allowed. A rule matching any of them is changed.
        [Parameter(Mandatory)]
        [string[]] $Name,

        # The state to put the rules in.
        [Parameter(Mandatory)]
        [bool] $Enabled,

        # Node name, used in the prompt and the result.
        [Parameter(Mandatory)]
        [string] $Server
    )

    $action = if ($Enabled) { 'Enable approval rule' } else { 'Disable approval rule' }

    $matching = $Rule | Where-Object { $ruleName = $_.Name; $Name | Where-Object { $ruleName -like $_ } }
    foreach ($item in $matching) {
        $changed = $false
        if ($item.Enabled -ne $Enabled -and $PSCmdlet.ShouldProcess("$($item.Name) on $Server", $action)) {
            $item.Enabled = $Enabled
            $item.Save()
            $changed = $true
        }

        [PSCustomObject]@{
            PSTypeName = 'WSUS.ApprovalRule'
            Server     = $Server
            Name       = $item.Name
            Enabled    = $item.Enabled
            Changed    = $changed
        }
    }
}
