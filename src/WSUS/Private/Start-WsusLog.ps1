function Start-WsusLog {
    <#
    .SYNOPSIS
        Creates the log folder, starts a transcript and returns the transcript path.
    .DESCRIPTION
        Used only by Invoke-WsusMaintenance ('maint') and Invoke-WsusDecline ('decline'). The caller
        keeps its own try/finally and calls Stop-WsusLog. Not subject to -WhatIf: a log of a
        -WhatIf run is still wanted.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Writes the run transcript; it must happen under -WhatIf too, so ShouldProcess would defeat it.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Log name prefix; the transcript is named <Prefix>_<timestamp>.log.
        [Parameter(Mandatory)]
        [string] $Prefix,

        # Folder for the logs, created if missing. Default C:\ProgramData\WsusMaintenance.
        [string] $Path = 'C:\ProgramData\WsusMaintenance'
    )

    $null = New-Item -ItemType Directory -Path $Path -Force -WhatIf:$false
    $transcript = Join-Path -Path $Path -ChildPath ('{0}_{1:yyyyMMdd_HHmm}.log' -f $Prefix, (Get-Date))
    $null = Start-Transcript -Path $transcript -WhatIf:$false
    $transcript
}
