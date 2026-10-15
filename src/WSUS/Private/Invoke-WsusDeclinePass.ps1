function Invoke-WsusDeclinePass {
    <#
    .SYNOPSIS
        The single decline loop shared by Invoke-WsusMaintenance and Invoke-WsusDecline.
    .DESCRIPTION
        Declines every not-yet-declined update whose title matches -Pattern, and, when
        -SupersededOlderThan is given, every superseded update that arrived before that moment.
        -ArrivedSince limits the search to recent arrivals. Returns the titles declined. Honours the
        caller's -WhatIf/-Confirm (one ShouldProcess per decline); updates skipped that way are not
        returned.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param (
        # Connected WSUS node (IUpdateServer) to decline on.
        [Parameter(Mandatory)]
        $Wsus,

        # Wildcard pattern matched against update titles; matching updates are declined.
        [Parameter(Mandatory)]
        [string] $Pattern,

        # Only consider updates that arrived on or after this moment.
        [datetime] $ArrivedSince,

        # Also decline superseded updates that arrived before this moment.
        [datetime] $SupersededOlderThan
    )

    $scope = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateScope
    if ($PSBoundParameters.ContainsKey('ArrivedSince')) {
        $scope.FromArrivalDate = $ArrivedSince
    }

    foreach ($update in $Wsus.GetUpdates($scope)) {
        if ($update.IsDeclined) { continue }

        $isOldSuperseded = $PSBoundParameters.ContainsKey('SupersededOlderThan') -and
            $update.IsSuperseded -and $update.ArrivalDate -lt $SupersededOlderThan
        if (($isOldSuperseded -or $update.Title -match $Pattern) -and
            $PSCmdlet.ShouldProcess($update.Title, 'Decline')) {
            $update.Decline()
            $update.Title
        }
    }
}
