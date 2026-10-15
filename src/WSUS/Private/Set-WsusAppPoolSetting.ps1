function Set-WsusAppPoolSetting {
    <#
    .SYNOPSIS
        Sets properties on the WsusPool IIS application pool.
    .DESCRIPTION
        Test seam over the IIS:\AppPools provider (no decisions). The caller owns the settings table
        and ShouldProcess. Mock it by name in tests.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin seam; the public caller owns ShouldProcess.')]
    [CmdletBinding()]
    param (
        # Table of WsusPool property names and the values to set.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Setting
    )

    $poolPath = 'IIS:\AppPools\WsusPool'
    foreach ($entry in $Setting.GetEnumerator()) {
        Set-ItemProperty -Path $poolPath -Name $entry.Key -Value $entry.Value
    }
}
