function Enable-WsusApprovalRule {
    <#
    .SYNOPSIS
        Turns approval rules on, on the upstream.
    .DESCRIPTION
        Upstream only. A rule that is already on is skipped (no save). One WSUS.ApprovalRule object
        is returned per matching rule, with Changed telling whether it was switched.
    .PARAMETER Name
        Rule names; wildcards allowed. Mandatory. Accepts pipeline input and a property named Name.
    .PARAMETER WsusServer
        The upstream node. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
    .EXAMPLE
        Enable-WsusApprovalRule -Name 'Critical*'
        Turns the named rule on (the stock Default rule is never touched unless named).
    .OUTPUTS
        WSUS.ApprovalRule
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.ApprovalRule')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]] $Name,

        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices
        $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
        Assert-WsusUpstream -Wsus $wsus -Server $WsusServer
        $rules = @($wsus.GetInstallApprovalRules())
    }

    process {
        $matching = $rules | Where-Object { $ruleName = $_.Name; $Name | Where-Object { $ruleName -like $_ } }
        foreach ($rule in $matching) {
            $changed = $false
            if (-not $rule.Enabled -and $PSCmdlet.ShouldProcess("$($rule.Name) on $WsusServer", 'Enable approval rule')) {
                $rule.Enabled = $true
                $rule.Save()
                $changed = $true
            }
            [PSCustomObject]@{
                PSTypeName = 'WSUS.ApprovalRule'
                Server     = $WsusServer
                Name       = $rule.Name
                Enabled    = $rule.Enabled
                Changed    = $changed
            }
        }
    }
}
