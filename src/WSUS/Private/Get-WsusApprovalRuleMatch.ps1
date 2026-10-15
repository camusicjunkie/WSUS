function Get-WsusApprovalRuleMatch {
    <#
    .SYNOPSIS
        Returns the approval rules whose name matches any of the wildcard patterns.
    #>
    [CmdletBinding()]
    param (
        # Approval rules to filter.
        [AllowEmptyCollection()]
        [object[]] $Rule = @(),

        # Wildcard patterns matched against the rule names.
        [Parameter(Mandatory)]
        [string[]] $Name
    )

    $Rule | Where-Object { $ruleName = $_.Name; $Name | Where-Object { $ruleName -like $_ } }
}
