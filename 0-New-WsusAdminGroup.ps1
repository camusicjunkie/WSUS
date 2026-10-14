<#
.SYNOPSIS
    Creates the resource group that grants WSUS admin rights on both nodes.

.DESCRIPTION
    Follows the security group naming convention (AGDLP). Creates res.srv.wsus.admin (Domain Local)
    and nests the existing team identity group into it. Script 2 then adds the resource group to
    the local 'WSUS Administrators' group on each node.

    Idempotent: an existing group or membership is left in place.

.EXAMPLE
    .\0-New-WsusAdminGroup.ps1 -GroupPath 'OU=Groups,DC=corp,DC=local' -WhatIf

.NOTES
    Run once as an AD administrator, before script 2.
#>
#Requires -Version 5.1
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param (
    # Resource group added to the local 'WSUS Administrators' group on each node.
    [string] $AdminResourceGroup = 'res.srv.wsus.admin',

    # Existing identity group of the server admins who manage WSUS. Not created by this script.
    [string] $AdminIdentityGroup = 'id.sa.platforms',

    # OU distinguished name for the new group. Defaults to the domain's Users container.
    [string] $GroupPath
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    if (-not (Get-ADGroup -Filter "Name -eq '$AdminIdentityGroup'")) {
        throw "Identity group '$AdminIdentityGroup' not found. Pass the right one with -AdminIdentityGroup."
    }

    if (Get-ADGroup -Filter "Name -eq '$AdminResourceGroup'") {
        Write-Verbose -Message "Group '$AdminResourceGroup' already exists"
    } elseif ($PSCmdlet.ShouldProcess($AdminResourceGroup, 'Create DomainLocal security group')) {
        $groupParams = @{
            Name           = $AdminResourceGroup
            SamAccountName = $AdminResourceGroup
            GroupScope     = 'DomainLocal'
            GroupCategory  = 'Security'
            Description    = 'Local WSUS Administrators on WSUS nodes'
        }
        if ($GroupPath) {
            $groupParams['Path'] = $GroupPath
        }
        New-ADGroup @groupParams
    }

    if ($PSCmdlet.ShouldProcess($AdminResourceGroup, "Add member '$AdminIdentityGroup'")) {
        $current = (Get-ADGroupMember -Identity $AdminResourceGroup).SamAccountName
        if ($current -notcontains $AdminIdentityGroup) {
            Add-ADGroupMember -Identity $AdminResourceGroup -Members $AdminIdentityGroup
        }
    }

    [PSCustomObject]@{
        ResourceGroup = $AdminResourceGroup
        Member        = $AdminIdentityGroup
        NextStep      = 'Build both nodes with scripts 1 and 2.'
    }
}
