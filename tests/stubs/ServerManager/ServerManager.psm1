# Stub of the ServerManager module (Windows Server only) for tests. Body throws so an unmocked
# call fails loudly.
function Get-WindowsFeature {
    [CmdletBinding()]
    param ([Parameter(Position = 0)] [string[]] $Name, [string] $ComputerName)
    throw 'Stub Get-WindowsFeature called: mock it.'
}
Export-ModuleMember -Function *
