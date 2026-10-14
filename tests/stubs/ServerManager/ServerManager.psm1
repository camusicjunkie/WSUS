# Stub of the ServerManager module (Windows Server only) for tests. Bodies throw so an unmocked
# call fails loudly.
function Get-WindowsFeature {
    [CmdletBinding()]
    param ([Parameter(Position = 0)] [string[]] $Name, [string] $ComputerName)
    throw 'Stub Get-WindowsFeature called: mock it.'
}
function Install-WindowsFeature {
    [CmdletBinding(SupportsShouldProcess)]
    param ([Parameter(Mandatory, Position = 0)] [string[]] $Name, [switch] $IncludeManagementTools, [switch] $IncludeAllSubFeature, [switch] $Restart)
    throw 'Stub Install-WindowsFeature called: mock it.'
}
Export-ModuleMember -Function *
