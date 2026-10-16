function Stop-WsusLog {
    <#
    .SYNOPSIS
        Applies log retention for a log's kind, then stops the transcript.
    .DESCRIPTION
        Keeps the newest log.Keep logs named '<Prefix>_*.log' in the log's folder and removes the
        rest, then stops the transcript even if retention fails. Call it from the caller's finally
        block. Retention is not subject to -WhatIf.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Closes the run transcript and applies retention; it must happen under -WhatIf too.')]
    [CmdletBinding()]
    param (
        # The log returned by Start-WsusLog.
        [Parameter(Mandatory)]
        $Log
    )

    try {
        Get-ChildItem -Path $Log.Path -Filter ('{0}_*.log' -f $Log.Prefix) -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip $Log.Keep |
            Remove-Item -Force -WhatIf:$false
    }
    finally {
        $null = Stop-Transcript
    }
}
