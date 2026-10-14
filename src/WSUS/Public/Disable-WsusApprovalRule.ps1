function Disable-WsusApprovalRule {
    <#
    .SYNOPSIS
        Turns approval rules off on the upstream.
    .DESCRIPTION
        Upstream only. A rule that is already off is skipped (no save). One WSUS.ApprovalRule object
        is returned per matching rule, with Changed telling whether it was switched.
    .PARAMETER Name
        Rule names; wildcards allowed. Accepts pipeline input and a property named Name. Default '*'.
    .PARAMETER WsusServer
        The upstream node. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
    .EXAMPLE
        Disable-WsusApprovalRule
        Turns every approval rule off on the local upstream.
    .OUTPUTS
        WSUS.ApprovalRule
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.ApprovalRule')]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]] $Name = '*',

        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices
        $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
        Assert-WsusUpstream -Wsus $wsus
        $rules = @($wsus.GetInstallApprovalRules())
    }

    process {
        $matching = $rules | Where-Object { $ruleName = $_.Name; $Name | Where-Object { $ruleName -like $_ } }
        foreach ($rule in $matching) {
            $changed = $false
            if ($rule.Enabled -and $PSCmdlet.ShouldProcess("$($rule.Name) on $WsusServer", 'Disable approval rule')) {
                $rule.Enabled = $false
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
