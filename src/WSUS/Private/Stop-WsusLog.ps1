function Stop-WsusLog {
    <#
    .SYNOPSIS
        Applies log retention for a prefix, then stops the transcript.
    .DESCRIPTION
        Keeps the newest -Keep logs named '<Prefix>_*.log' in -Path and removes the rest, then stops
        the transcript even if retention fails. Call it from the caller's finally block. Retention
        is not subject to -WhatIf.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Closes the run transcript and applies retention; it must happen under -WhatIf too.')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Prefix,

        [string] $Path = 'C:\ProgramData\WsusMaintenance',

        [int] $Keep = 12
    )

    try {
        Get-ChildItem -Path $Path -Filter ('{0}_*.log' -f $Prefix) -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip $Keep |
            Remove-Item -Force -WhatIf:$false
    }
    finally {
        $null = Stop-Transcript
    }
}
