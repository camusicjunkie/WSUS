function Start-WsusLog {
    <#
    .SYNOPSIS
        Creates the log folder, starts a transcript and returns a log that remembers its settings.
    .DESCRIPTION
        Used only by Invoke-WsusMaintenance and Invoke-WsusDecline. The returned log holds the file
        prefix, folder and retention count, so the caller passes it to Stop-WsusLog and repeats
        nothing. The caller keeps its own try/finally and calls Stop-WsusLog. Not subject to
        -WhatIf: a log of a -WhatIf run is still wanted.

        The log has Transcript (the transcript file), Prefix, Path (the folder) and Keep.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Writes the run transcript; it must happen under -WhatIf too, so ShouldProcess would defeat it.')]
    [CmdletBinding()]
    [OutputType('WSUS.RunLog')]
    param (
        # Kind of run. Decides the file prefix (see Get-WsusLogLayout).
        [Parameter(Mandatory)]
        [ValidateSet('Maintenance', 'Decline')]
        [string] $Kind,

        # Number of newest logs of this kind to keep when the log is stopped.
        [Parameter(Mandatory)]
        [int] $Keep,

        # Folder for the logs, created if missing. Default the log folder in Get-WsusLogLayout.
        [string] $Path = (Get-WsusLogLayout).Root
    )

    $prefix = (Get-WsusLogLayout).Prefix[$Kind]

    $null = New-Item -ItemType Directory -Path $Path -Force -WhatIf:$false
    $transcript = Join-Path -Path $Path -ChildPath ('{0}_{1:yyyyMMdd_HHmm}.log' -f $prefix, (Get-Date))
    $null = Start-Transcript -Path $transcript -WhatIf:$false

    [PSCustomObject]@{
        PSTypeName = 'WSUS.RunLog'
        Transcript = $transcript
        Prefix     = $prefix
        Path       = $Path
        Keep       = $Keep
    }
}
