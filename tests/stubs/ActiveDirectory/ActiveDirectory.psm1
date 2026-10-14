# Stub of the ActiveDirectory module for tests. Bodies throw so an unmocked call fails loudly.
function Get-ADGroup {
    [CmdletBinding()]
    param ([Parameter(Position = 0)] $Identity, [string] $Filter, [string[]] $Properties, [string] $Server)
    throw 'Stub Get-ADGroup called: mock it.'
}
function New-ADGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] $GroupScope,
        $GroupCategory, [string] $Path, [string] $Description, [string] $SamAccountName, [switch] $PassThru
    )
    throw 'Stub New-ADGroup called: mock it.'
}
function Add-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param ([Parameter(Mandatory, Position = 0)] $Identity, [Parameter(Mandatory, Position = 1)] $Members)
    throw 'Stub Add-ADGroupMember called: mock it.'
}

function Get-ADGroupMember {
    [CmdletBinding()]
    param ([Parameter(Mandatory, Position = 0)] $Identity)
    throw 'Stub Get-ADGroupMember called: mock it.'
}
Export-ModuleMember -Function *
