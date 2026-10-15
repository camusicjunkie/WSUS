function Invoke-WsusUtil {
    <#
    .SYNOPSIS
        Runs wsusutil.exe with the given arguments and throws on a non-zero exit code.
    .DESCRIPTION
        Test seam over the native call (no decisions beyond the exit-code check). Mock it by name.
    #>
    [CmdletBinding()]
    param (
        # Arguments passed to wsusutil.exe.
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $wsusUtil = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\Tools\wsusutil.exe'
    if (-not (Test-Path -LiteralPath $wsusUtil)) {
        throw "wsusutil.exe not found at '$wsusUtil'. Is the WSUS role installed?"
    }

    & $wsusUtil @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "wsusutil $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE"
    }
}
