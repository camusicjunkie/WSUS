# Stub of the WebAdministration module for tests. Bodies throw so an unmocked call fails loudly.
function Get-WebBinding {
    [CmdletBinding()]
    param ([string] $Name, [string] $Protocol, [int] $Port, [string] $IPAddress, [string] $HostHeader)
    throw 'Stub Get-WebBinding called: mock it.'
}
function New-WebBinding {
    [CmdletBinding(SupportsShouldProcess)]
    param ([string] $Name, [string] $Protocol, [int] $Port, [string] $IPAddress, [string] $HostHeader, [int] $SslFlags)
    throw 'Stub New-WebBinding called: mock it.'
}
function Get-WebConfigurationProperty {
    [CmdletBinding()]
    param ([string] $PSPath, [string] $Filter, [string] $Name)
    throw 'Stub Get-WebConfigurationProperty called: mock it.'
}
Export-ModuleMember -Function *
