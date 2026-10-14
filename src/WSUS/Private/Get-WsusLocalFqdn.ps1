function Get-WsusLocalFqdn {
    <#
    .SYNOPSIS
        Returns this machine's fully qualified domain name.
    .DESCRIPTION
        Default for -WsusServer on every public function. Throws if the name can't be resolved.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    try {
        [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
    }
    catch {
        throw "Cannot resolve the FQDN of '$($env:COMPUTERNAME)': $($_.Exception.Message)"
    }
}
