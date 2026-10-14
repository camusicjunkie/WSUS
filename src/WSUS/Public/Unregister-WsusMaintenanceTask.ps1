function Unregister-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Removes the WSUS maintenance and decline scheduled tasks from this node.
    .DESCRIPTION
        Removes 'WSUS Maintenance' and 'WSUS Decline Unwanted'. A task that is already absent is
        skipped without an error, so it is safe to run when decommissioning a node or to re-run.
        Returns nothing.
    .EXAMPLE
        Unregister-WsusMaintenanceTask
        Removes both scheduled tasks from this node.
    .EXAMPLE
        Unregister-WsusMaintenanceTask -WhatIf
        Shows which tasks would be removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    Assert-WsusPrerequisite -Administrator

    foreach ($name in 'WSUS Maintenance', 'WSUS Decline Unwanted') {
        if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($name, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
        }
    }
}
