function Deny-WsusUpdate {
    <#
    .SYNOPSIS
        Declines updates on the upstream by exact KB number.
    .DESCRIPTION
        Upstream only (replicas copy declines). Every update whose KnowledgebaseArticles contains the
        KB exactly is declined, including per-product and per-architecture variants; look-alike
        numbers (KB5001234 vs KB50012345) are not touched. An update that is already declined is
        reported as AlreadyDeclined and left alone. A KB with no match writes a non-terminating error.
        Under -WhatIf nothing is declined and no result is returned for the skipped updates.

        The real UpdateServices module has its own Deny-WsusUpdate (it takes an update object).
        If both modules are loaded, call this one as WSUS\Deny-WsusUpdate.
    .PARAMETER Kb
        One or more KB numbers, with or without the KB prefix (KB5001234 or 5001234).
    .PARAMETER WsusServer
        The upstream node. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
    .EXAMPLE
        Deny-WsusUpdate -Kb KB5001234
        Declines every update for KB5001234 on the local upstream.
    .OUTPUTS
        WSUS.DeclineResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('WSUS.DeclineResult')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^(KB)?\d+$')]
        [string[]] $Kb,

        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531
    )

    begin {
        Assert-WsusPrerequisite -Module UpdateServices
        $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
        Assert-WsusUpstream -Wsus $wsus -Server $WsusServer
    }

    process {
        foreach ($article in $Kb) {
            $number = $article -replace '^KB', ''
            # SearchUpdates is a substring match; keep only exact KB hits.
            $hits = @($wsus.SearchUpdates($number) | Where-Object { $number -in $_.KnowledgebaseArticles })

            if ($hits.Count -eq 0) {
                Write-Error -Message "No update found for KB$number on $WsusServer." -Category ObjectNotFound `
                    -TargetObject "KB$number" -ErrorId 'WsusUpdateNotFound'
                continue
            }

            foreach ($update in $hits) {
                $action = 'AlreadyDeclined'
                if (-not $update.IsDeclined) {
                    if (-not $PSCmdlet.ShouldProcess("$($update.Title) on $WsusServer", 'Decline update')) { continue }
                    $update.Decline()
                    $action = 'Declined'
                }
                [PSCustomObject]@{
                    PSTypeName = 'WSUS.DeclineResult'
                    Kb         = "KB$number"
                    Update     = $update.Title
                    Action     = $action
                    NextStep   = 'Remove the update from machines that already installed it with DISM (README section 5).'
                }
            }
        }
    }
}
