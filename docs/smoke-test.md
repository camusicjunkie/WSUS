# Smoke test

Run it before a MINOR or MAJOR release (README section 19, step 2) and for the 1.0.0 gate (issue #30). It runs the
module against a real WSUS upstream and replica and checks that each function does what the runbook says.
The unit tests cannot do this: their fake WSUS server accepts values the real API rejects (a port of 0, any
argument type, a content path without `WsusContent`), and three bugs were found that way.

## Scope

**In:** every function in the module, the runbook sections that use them (3, 4, 5, 10, 11, 12, 18), and a
client scan, install and report round trip through the registry policy.

**Out:** anything outside the module. `New-WsusAdminGroup` (needs Active Directory), the NetScaler
configuration, the client GPOs, a real multi-client fleet and the proxy. Test those where they live.

## Environment

Two Windows Server 2022 machines, each with 4 GB of memory or more (2 GB stalls WSUS during a sync) and a 100 GB
disk, with internet access to Microsoft Update. Workgroup machines are enough. Install the module under
`C:\Program Files\WindowsPowerShell\Modules\WSUS` (the all-users path the scheduled tasks use) and run everything in
Windows PowerShell 5.1 as a local administrator.

Lab stand-ins for what Active Directory and a CA give you in production:

| Need | Lab stand-in |
|------|--------------|
| Name resolution | A `hosts` entry on each machine for the other and for the VIP name |
| Certificate | A self-signed one per node with SANs for the VIP name, the machine's short name (a workgroup machine's FQDN is its short name) and `<name>.<suffix>`; import it into `LocalMachine\Root` on **both** nodes |
| `res.srv.wsus.admin` | A local group of that name. `Set-WsusNodeConfig` still reports one `Add-LocalGroupMember` error, because a local group cannot be nested here. Expected. |

## Clients without Group Policy

The two machines are their own clients. Set the policy values from README section 7 under
`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` (and `\AU`) to point at the upstream, with `TargetGroup`
set to a ring name (`Pilot` on one machine, `Servers` on the other), then restart `wuauserv`. `AUOptions = 3`
(download, notify) lets the test install on demand.

Two Windows Update API limits to plan for: scanning works from a remote session, but downloading and installing do
not (`Access is denied`). Run the install as a one-shot SYSTEM scheduled task. And a client only lists an update
once the server has finished downloading its content.

## Checklist

Run each with `-WhatIf` first where the function supports it. Record the result against each line.

### Build the upstream (README section 3)

- [ ] `Install-WsusNode -ContentPath C:\WSUS`; running it again skips postinstall and returns normally.
- [ ] `Set-WsusNodeConfig`: `SelfTest` is `Passed`; a certificate within 30 days of expiry is refused.
- [ ] `Set-WsusUpstreamConfig`: products, classifications, five ring groups and two rules (off) are created.
- [ ] `Start-WsusSync -Wait`: succeeds. The database grows, the content folder stays empty (nothing is approved).
- [ ] `Invoke-WsusMaintenance -SupersededAgeDays 0`: declines the superseded and preview updates, `Database` is `Completed`.
- [ ] `Enable-WsusApprovalRule -Name 'Auto - *'` then `Set-WsusUpstreamConfig -ApplyRulesNow`: Critical and Security are
      approved for Packer and Pilot only; definitions for Packer, Pilot, Workstations and VDI. Content downloads, and the
      disk has room for it.

### Build the replica (sections 3 and 12)

- [ ] `Install-WsusNode`, `Set-WsusNodeConfig` as above.
- [ ] `Set-WsusReplicaConfig -UpstreamFqdn <upstream> -SyncNow`: the replica copies every update, approval and ring
      group; `Get-WsusNodeStatus` reports `Role = Replica`. The upstream's approval rules are not copied.
- [ ] `Register-WsusMaintenanceTask` on both (`-MaintenanceTime 04:00` on the replica): both tasks run as SYSTEM, and
      `Start-ScheduledTask 'WSUS Decline Unwanted'` exits 0 and writes a transcript.

### Guard rails (sections 10 and 11)

On the replica, each of these throws a message naming the replica and the upstream: `Approve-WsusRing`,
`Enable-WsusApprovalRule`, `Disable-WsusApprovalRule`, `Deny-WsusUpdate`, `Set-WsusUpstreamConfig`.
`Invoke-WsusDecline` returns `Declined = 0` and no log.

- [ ] `Set-WsusReplicaConfig` pointed at the node itself throws.
- [ ] `ConvertTo-WsusUpstream` throws while the upstream still answers, and the node stays a replica.
- [ ] `Set-WsusReplicaConfig` on an upstream that holds approvals throws and lists them; with `-Force` it converts.

### Failover (section 11)

Shut the upstream down cleanly (`Stop-Computer`), then on the replica:

- [ ] `ConvertTo-WsusUpstream`: role becomes `Upstream`, `SyncFromMicrosoftUpdate` is true.
- [ ] `Set-WsusUpstreamConfig`, `Enable-WsusApprovalRule`, `Start-WsusSync -Wait`: succeed, and the approvals that were
      copied while it was a replica are still there.
- [ ] Bring the old upstream back and run `Set-WsusReplicaConfig -UpstreamFqdn <new upstream> -Force -SyncNow`.

### Adding a product (section 18)

- [ ] `Disable-WsusApprovalRule`, `Set-WsusUpstreamConfig -Product <existing + new>`, `Start-WsusSync -Wait`,
      `Invoke-WsusMaintenance -SupersededAgeDays 0`, `Enable-WsusApprovalRule`,
      `Set-WsusUpstreamConfig ... -ApplyRulesNow`: the content folder stays small (a few GB) and the disk does not fill.

### Clients and the monthly gate (sections 5 and 7)

- [ ] Both clients register on the upstream in the groups their policy names.
- [ ] A `Pilot` client lists the updates approved for Pilot, and a `Servers` client lists none of them.
- [ ] The `Pilot` client downloads and installs an update from the node, and the server's per-update summary shows it
      as installed.
- [ ] `Approve-WsusRing -WhatIf` before the install: every row is `Held`, with a reason (soak, not tested or not
      installed).
- [ ] After the install and a report (`wuauclt /reportnow`): the installed update reads `Passed` (installed 1 of
      needed 1, 100%, none failed), approves for the next ring, and skips the rings it already has. A second run
      approves nothing more. `-Force` turns a held row into `Forced`.

Use a small update for the install. The Defender platform update (about 40 MB, classification Definition Updates) works
with `Approve-WsusRing -Classification 'Definition Updates' -MinimumSoakDays 0`. An OS cumulative update tests Windows,
not the module, and on a 4 GB VM it took hours to install and left the guest unresponsive until it shut down and
rebooted. If you do install one, leave the machine alone until it has rebooted, and wait for the servicing to finish
before syncing a downstream node from it (a sync against a node still servicing fails with `UssInternalError` or
`UssCommunicationError`).

### Swapping back

- [ ] After the failover, reverse the roles: `ConvertTo-WsusUpstream -Force` on the old upstream, `Set-WsusUpstreamConfig`,
      `Enable-WsusApprovalRule`, `Start-WsusSync -Wait`, then `Set-WsusReplicaConfig -UpstreamFqdn <it> -Force -SyncNow`
      on the other node. Every step succeeds, a warning says to compare approval counts, `DisabledRules` lists the
      demoted node's rules and they are off. Update and declined counts match on both nodes.
- [ ] Compare `Get-WsusNodeStatus` `ApprovedUpdateCount` on both and record the counts. Before #37, the demoted
      node held 6 approvals against the upstream's 13 (the Server 2022 and several Defender updates), and
      `-ApplyRulesNow`, extra syncs and a direct re-approval did not change it. If they still differ, list the
      missing approvals with their group IDs on each node and add them to #37.
- [ ] Remove the WSUS role and WID database on the demoted node, rebuild it as a clean replica (README section 12),
      and check that `ApprovedUpdateCount` now matches the upstream's.

## Checking on a node

`Get-WsusNodeStatus` shows whether a sync is running (`SyncStatus`, `SyncPhase`, `SyncProcessedItems` of
`SyncTotalItems`), why the last one failed (`LastSyncError`) and the update, approved and declined counts. In the VmLab
lab, `Get-LabVmHealth -Service WinRM,WsusService,W3SVC` shows guest memory, a pending reboot and whether Windows
servicing is busy. Check both before blaming the module for a stall.

## Known lab noise

- `Add-LocalGroupMember` error from `Set-WsusNodeConfig` (see Environment).
- `-WhatIf` on several functions prints many `Retrieve the value for property 'Title'` lines.
- `Get-WsusNodeStatus` against the other node returns 401: two workgroup machines have different local accounts.
  Test it where nodes share an identity.
- A node under memory pressure drops WinRM for seconds at a time. Retry the connection, not the command.
