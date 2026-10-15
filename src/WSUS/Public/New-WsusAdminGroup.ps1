function New-WsusAdminGroup {
    <#
    .SYNOPSIS
        Creates the resource group that grants WSUS admin rights on both nodes.
    .DESCRIPTION
        Creates the Domain Local resource group and nests the existing team identity group into it
        (AGDLP). Set-WsusNodeConfig later adds the resource group to the local 'WSUS Administrators'
        group on each node.

        Idempotent: an existing group or membership is left in place. Run once as an AD administrator,
        anywhere the ActiveDirectory module is available.
    .EXAMPLE
        New-WsusAdminGroup -GroupPath 'OU=Groups,DC=corp,DC=local' -WhatIf
        Shows what would be created without changing AD.
    .OUTPUTS
        WSUS.AdminGroup
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.AdminGroup')]
    param (
        # Resource group to create. Default res.srv.wsus.admin.
        [string] $AdminResourceGroup = 'res.srv.wsus.admin',

        # Existing identity group of the admins who manage WSUS. Not created. Default id.sa.platforms.
        [string] $AdminIdentityGroup = 'id.sa.platforms',

        # OU distinguished name for the new group. Defaults to the domain's Users container.
        [string] $GroupPath
    )

    Assert-WsusPrerequisite -Module ActiveDirectory

    if (-not (Get-ADGroup -Filter "Name -eq '$AdminIdentityGroup'")) {
        throw "Identity group '$AdminIdentityGroup' not found. Pass the right one with -AdminIdentityGroup."
    }

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
    $created = $false
    $groupExists = $true
    if (Get-ADGroup -Filter "Name -eq '$AdminResourceGroup'") {
        Write-Verbose -Message "Group '$AdminResourceGroup' already exists"
    } elseif ($PSCmdlet.ShouldProcess($AdminResourceGroup, 'Create DomainLocal security group')) {
        New-ADGroup @groupParams
        $created = $true
    } else {
        $groupExists = $false
    }

    # A group that was not created (-WhatIf on a missing group) has no members to query or add to.
    if ($groupExists) {
        $current = (Get-ADGroupMember -Identity $AdminResourceGroup).SamAccountName
        if ($current -notcontains $AdminIdentityGroup -and
            $PSCmdlet.ShouldProcess($AdminResourceGroup, "Add member '$AdminIdentityGroup'")) {
            Add-ADGroupMember -Identity $AdminResourceGroup -Members $AdminIdentityGroup
        }
    }

    [PSCustomObject] @{
        PSTypeName    = 'WSUS.AdminGroup'
        ResourceGroup = $AdminResourceGroup
        Member        = $AdminIdentityGroup
        Created       = $created
        NextStep      = 'Install-WsusNode, then Set-WsusNodeConfig, on both nodes'
    }
}
