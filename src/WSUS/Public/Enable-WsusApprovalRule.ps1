function Enable-WsusApprovalRule {
    <#
    .SYNOPSIS
        Turns approval rules on, on the upstream.
    .DESCRIPTION
        Upstream only. A rule that is already on is skipped (no save). One WSUS.ApprovalRule object
        is returned per matching rule, with Changed telling whether it was switched.
    .EXAMPLE
        Enable-WsusApprovalRule -Name 'Critical*'
        Turns the named rule on (the stock Default rule is never touched unless named).
    .OUTPUTS
        WSUS.ApprovalRule
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is called per rule by Set-WsusApprovalRuleState, which inherits the -WhatIf and -Confirm.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.ApprovalRule')]
    param (
        # Rule names; wildcards allowed. Mandatory. Accepts pipeline input and a property named Name.
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]] $Name,

        # The upstream node. Defaults to this machine's FQDN.
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices
        $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
        Assert-WsusRole -Wsus $wsus -Role Upstream
        $rules = @($wsus.GetInstallApprovalRules())
    }

    process {
        Set-WsusApprovalRuleState -Rule $rules -Name $Name -Enabled $true -Server $WsusServer
    }
}
