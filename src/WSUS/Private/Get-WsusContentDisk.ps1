function Get-WsusContentDisk {
    <#
    .SYNOPSIS
        Returns free and total space (GB) and free percent of the drive holding a content path.
    .DESCRIPTION
        Local only. Returns $null when the path has no drive letter or the drive is not found.
    #>
    [CmdletBinding()]
    param (
        [string] $ContentPath
    )

    if ($ContentPath -notmatch '^([A-Za-z]):') { return }
    $drive = Get-PSDrive -Name $Matches[1] -PSProvider FileSystem -ErrorAction SilentlyContinue
    if (-not $drive) { return }

    $total = [double] $drive.Used + [double] $drive.Free
    [PSCustomObject]@{
        FreeGB      = [math]::Round($drive.Free / 1GB, 2)
        TotalGB     = [math]::Round($total / 1GB, 2)
        FreePercent = if ($total -gt 0) { [math]::Round($drive.Free / $total * 100, 1) }
    }
}
