function Get-WsusRingPlan {
    <#
    .SYNOPSIS
        Returns the rollout plan: the rings in order, the promotion path between them and the approval rules.
    .DESCRIPTION
        The one place that names the rings (see GLOSSARY.md). Returns data only and never touches a
        node, so callers keep their own server calls. Each call returns a new object.

        Ring       Rings in rollout order. VDI only gets definitions and is never promoted to or from.
        Promotion  Where Approve-WsusRing promotes from and to, and which classifications. These are
                   the classifications of the Critical and Security rule, so the two cannot drift apart.
        Rule       The approval rules keyed CritSec and Definition. Each is a hashtable with the keys
                   Set-WsusApprovalRuleDefinition takes: Name, ClassificationTitle and GroupName.
    #>
    [CmdletBinding()]
    [OutputType('WSUS.RingPlan')]
    param ()

    $critSecClassification = 'Critical Updates', 'Security Updates'

    [PSCustomObject]@{
        PSTypeName = 'WSUS.RingPlan'
        Ring       = @('Packer', 'Pilot', 'Workstations', 'Servers', 'VDI')
        Promotion  = [PSCustomObject]@{
            From                = 'Pilot'
            To                  = @('Workstations', 'Servers')
            ClassificationTitle = $critSecClassification
        }
        Rule       = @{
            CritSec    = @{
                Name                = 'Auto - Critical and Security'
                ClassificationTitle = $critSecClassification
                GroupName           = @('Packer', 'Pilot')
            }
            Definition = @{
                Name                = 'Auto - Definition Updates'
                ClassificationTitle = @('Definition Updates')
                GroupName           = @('Packer', 'Pilot', 'Workstations', 'VDI')
            }
        }
    }
}
