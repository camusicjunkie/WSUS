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
    .PARAMETER WsusServer
        Node to sync. Defaults to this machine's FQDN.
    .PARAMETER Port
        WSUS SSL port. Default 8531.
    .PARAMETER CategoryOnly
        Fetch categories only, without the full update catalog. Upstream only.
    .PARAMETER Wait
        Wait for the sync to finish and report its outcome.
    .PARAMETER TimeoutMinutes
        How long -Wait polls. Default 30 with -CategoryOnly, otherwise 480.
    .EXAMPLE
        Start-WsusSync -CategoryOnly -Wait
        Fetches categories so products can be chosen, and waits.
    .OUTPUTS
        WSUS.SyncResult
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WSUS.SyncResult')]
    param (
        [string] $WsusServer = (Get-WsusLocalFqdn),

        [int] $Port = 8531,

        [switch] $CategoryOnly,

        [switch] $Wait,

        [ValidateRange(1, 10080)]
        [int] $TimeoutMinutes = $(if ($CategoryOnly) { 30 } else { 480 })
    )

    Assert-WsusPrerequisite -Module UpdateServices

    $wsus = Connect-WsusNode -Server $WsusServer -Port $Port
    if ($CategoryOnly) {
        Assert-WsusUpstream -Wsus $wsus -Instead 'A categories-only sync fetches from Microsoft; use Start-WsusSync without -CategoryOnly on a replica.'
    }

    $mode = if ($CategoryOnly) { 'CategoryOnly' } else { 'Full' }
    $subscription = $wsus.GetSubscription()
    $started = Get-Date
    $status = 'Started'

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
        while ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
            if (++$polls -gt $maxPolls) {
                throw "$mode sync on '$WsusServer' did not finish within $TimeoutMinutes minutes. The sync keeps running on the server; check it with Get-WsusNodeStatus."
            }
            $progress = $subscription.GetSynchronizationProgress()
            $percent = if ($progress.TotalItems -gt 0) { [int] [math]::Min(100, $progress.ProcessedItems / $progress.TotalItems * 100) } else { 0 }
            Write-Progress -Activity "WSUS $mode sync on $WsusServer" -Status "$($progress.ProcessedItems) of $($progress.TotalItems) items" -PercentComplete $percent
            Start-Sleep -Seconds 15
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
