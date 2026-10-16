function Set-WsusSyncSchedule {
    <#
    .SYNOPSIS
        Turns automatic sync on and sets the first sync hour and the number of syncs per day.
    .DESCRIPTION
        Changes the subscription object in memory only. The caller saves it, under its own
        ShouldProcess. The hour is UTC.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper; the public caller wraps it in ShouldProcess and saves.')]
    [CmdletBinding()]
    param (
        # ISubscription of the node, from GetSubscription().
        [Parameter(Mandatory)]
        $Subscription,

        # Automatic syncs per day (1-24).
        [Parameter(Mandatory)]
        [ValidateRange(1, 24)]
        [int] $SyncsPerDay,

        # Hour (UTC) of the first daily sync (0-23).
        [Parameter(Mandatory)]
        [ValidateRange(0, 23)]
        [int] $FirstSyncUtcHour
    )

    $Subscription.SynchronizeAutomatically = $true
    $Subscription.SynchronizeAutomaticallyTimeOfDay = New-TimeSpan -Hours $FirstSyncUtcHour
    $Subscription.NumberOfSynchronizationsPerDay = $SyncsPerDay
}
