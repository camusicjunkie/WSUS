function Start-WsusSync {
    <#
    .SYNOPSIS
        Starts a WSUS synchronisation, optionally waiting for it to finish.
    .DESCRIPTION
        Starts a full sync (upstream or replica) or, with -CategoryOnly, a categories-only sync
        (upstream only; throws on a replica). If a sync is already running a warning is written and
        no second sync is started; with -Wait the running sync is joined.

        -Wait polls every 15 seconds and shows progress. The timeout defaults to 30 minutes for
        -CategoryOnly and 480 minutes for a full sync. A timeout throws, but the sync keeps running
        on the server. A Failed result throws.
    .EXAMPLE
        Start-WsusSync -CategoryOnly -Wait
        Fetches categories so products can be chosen, and waits.
    .OUTPUTS
        WSUS.SyncResult
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.SyncResult')]
    param (
        # Node to sync. Defaults to this machine's FQDN.
        [string] $WsusServer = (Get-WsusLocalFqdn),

        # WSUS SSL port. Default 8531.
        [int] $Port = 8531,

        # Fetch categories only, without the full update catalog. Upstream only.
        [switch] $CategoryOnly,

        # Wait for the sync to finish and report its outcome.
        [switch] $Wait,

        # How long -Wait polls. Default 30 with -CategoryOnly, otherwise 480.
        [ValidateRange(1, 10080)]
        [int] $TimeoutMinutes = $(if ($CategoryOnly) { 30 } else { 480 })
    )

    Assert-WsusPrerequisite -Module UpdateServices

    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
    if ($CategoryOnly) {
        Assert-WsusRole -Wsus $wsus -Role Upstream -Instead 'A categories-only sync fetches from Microsoft; use Start-WsusSync without -CategoryOnly on a replica.'
    }

    $mode = if ($CategoryOnly) { 'CategoryOnly' } else { 'Full' }
    $subscription = $wsus.GetSubscription()
    $started = Get-Date
    $status = 'Started'
    # Start time of the last finished sync, to tell the sync started here from the one before it.
    $previousStart = $subscription.GetLastSynchronizationInfo().StartTime

    if ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
        Write-Warning "A sync is already running on '$WsusServer'; not starting another."
        $status = 'AlreadyRunning'
    }
    elseif ($PSCmdlet.ShouldProcess($WsusServer, "Start $mode sync")) {
        if ($CategoryOnly) { $subscription.StartSynchronizationForCategoryOnly() }
        else { $subscription.StartSynchronization() }
    }
    else {
        return
    }

    $result = [ordered]@{
        PSTypeName = 'WSUS.SyncResult'
        Server     = $WsusServer
        Mode       = $mode
        Started    = $started
        Status     = $status
    }

    if ($Wait) {
        $maxPolls = $TimeoutMinutes * 4
        $polls = 0
        # StartSynchronization returns before the server reports the sync as running, so a status of
        # NotProcessing straight after the start is not a finished sync. Wait up to a minute to see it begin.
        $maxStartChecks = 12
        $startChecks = 0
        $seenRunning = $false
        while ($true) {
            if ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
                $seenRunning = $true
                if (++$polls -gt $maxPolls) {
                    throw "$mode sync on '$WsusServer' did not finish within $TimeoutMinutes minutes. The sync keeps running on the server; check it with Get-WsusNodeStatus."
                }
                $progress = $subscription.GetSynchronizationProgress()
                $percent = if ($progress.TotalItems -gt 0) { [int] [math]::Min(100, $progress.ProcessedItems / $progress.TotalItems * 100) } else { 0 }
                Write-Progress -Activity "WSUS $mode sync on $WsusServer" -Status "$($progress.ProcessedItems) of $($progress.TotalItems) items" -PercentComplete $percent
                Start-Sleep -Seconds 15
                continue
            }

            if ($seenRunning) { break }

            # Not seen running yet: it may already have finished, which shows as a newer last-sync start time.
            $lastStart = $subscription.GetLastSynchronizationInfo().StartTime
            if ($lastStart -and $lastStart -ne $previousStart) { break }
            if (++$startChecks -gt $maxStartChecks) {
                throw "$mode sync on '$WsusServer' did not start within a minute, so its result cannot be reported. Check it with Get-WsusNodeStatus."
            }
            Start-Sleep -Seconds 5
        }
        Write-Progress -Activity "WSUS $mode sync on $WsusServer" -Completed

        $last = $subscription.GetLastSynchronizationInfo()
        $result.Status = 'Finished'
        $result.Finished = $last.EndTime
        $result.Result = [string] $last.Result
        $result.Error = $last.Error
        if ($result.Result -eq 'Failed') {
            throw "$mode sync on '$WsusServer' failed: $($last.Error)"
        }
    }

    $result.NextStep = 'Check the outcome with Get-WsusNodeStatus.'
    [PSCustomObject] $result
}
