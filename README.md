# WSUS (WID, upstream + replica)

Two Server Core WSUS nodes behind the NetScaler VIP `wsus.corp.local`:

- **WSUS01** – upstream. Syncs from Microsoft, holds every approval, decline and computer group.
- **WSUS02** – replica of WSUS01. Copies approvals and content. Takes client traffic only when WSUS01 is down.

Each node has its own Windows Internal Database (WID) and its own content disk. Nothing is shared.

Rings (computer groups): `Packer`, `Pilot`, `Workstations`, `Servers`, `VDI`. The names are a
contract: `Set-WsusUpstreamConfig` creates these groups and the client GPOs (section 7) must use exactly
these `TargetGroup` values. The module defines the rings, the promotion path and the two approval rules in one
place, so `Set-WsusUpstreamConfig` and `Approve-WsusRing` cannot disagree on a name. Terms (node, upstream, replica, promote, ring, approval rule, maintenance run,
decline run, gate) are defined in [GLOSSARY.md](GLOSSARY.md).

Everything is done with the `WSUS` PowerShell module (Windows PowerShell 5.1). Install it once per node and
admin workstation (section 1), then run functions instead of scripts. Every function that changes state
supports `-WhatIf` and `-Confirm`: run with `-WhatIf` first, every time. Every function that takes
`-WsusServer` defaults to this machine's FQDN and `-Port 8531`. Results are typed objects; most carry a
`NextStep` that names the next function to run. Use `Get-Help <function> -Full` for details.

## Functions

| Function | Run on | Run as | When |
|----------|--------|--------|------|
| `New-WsusAdminGroup` | Admin workstation (ActiveDirectory module) | AD admin | Once |
| `Install-WsusNode` | Each node (local only) | Local admin | Build or rebuild a node |
| `Set-WsusNodeConfig` | Each node (local only) | Local admin | After install, after a cert renewal, after any WSUS repair |
| `Set-WsusUpstreamConfig` | Upstream | WSUS admin | Once, and when products, classifications, groups or rules change |
| `Set-WsusReplicaConfig` | Replica | WSUS admin | Once, or to repoint at another upstream |
| `ConvertTo-WsusUpstream` | Replica | WSUS admin | Promote, only if the upstream is lost for good |
| `Start-WsusSync` | Either node | WSUS admin | Kick a sync, or fetch categories only |
| `Enable-WsusApprovalRule` / `Disable-WsusApprovalRule` | Upstream | WSUS admin | Turn approval rules on or off |
| `Deny-WsusUpdate` | Upstream | WSUS admin | Decline a bad update by KB |
| `Approve-WsusRing` | Upstream (or remote) | WSUS admin | Monthly, week 2 |
| `Invoke-WsusMaintenance` | Each node (local only) | SYSTEM, scheduled task | Weekly |
| `Invoke-WsusDecline` | Upstream (or remote) | SYSTEM, scheduled task | Every 15 minutes |
| `Register-WsusMaintenanceTask` / `Unregister-WsusMaintenanceTask` | Each node | Local admin | Once per node |
| `Get-WsusNodeStatus` | Anywhere (disk and logs: local only) | WSUS admin | Health checks |

An upstream always syncs from Microsoft Update (`Set-WsusUpstreamConfig` has no parameter for another source). A
node that syncs from another WSUS node is a replica (`Set-WsusReplicaConfig`).

Not functions: `docs/6-netscaler-wsus.conf` (NetScaler CLI, applied once by a NetScaler admin) and the client
GPOs (section 7, created by hand in GPMC).

`Deny-WsusUpdate` also exists in the Microsoft `UpdateServices` module (it takes an update object). If both
are loaded, call ours as `WSUS\Deny-WsusUpdate`.

---

## 1. Install and update the module

The module comes from the internal NuGet registry, registered on each machine as `LocalGallery`.
Install and update are the same elevated command, on every node and admin workstation:

```powershell
Install-Module WSUS -Repository LocalGallery -Scope AllUsers -Force -Credential (Get-Credential)
```

- The credential is a registry deploy token with `read_package_registry` scope (a personal access token is the
  fallback). Enter it each time; never store it on a node.
- `-Scope AllUsers` is required: the scheduled tasks run as SYSTEM and cannot see a per-user install.
  Use Windows PowerShell 5.1 only: PowerShell 7's all-users module path is not on the 5.1 path the tasks use.
- Open sessions keep the old version; the next task run picks up the new one. Roll out updates to the replica
  first, then the upstream. To go back: `Install-Module WSUS -RequiredVersion <x.y.z> ...`. Check what a node
  runs with `Get-Module WSUS -ListAvailable`.

**Rebuilt node (bootstrap).** A fresh node cannot reach the registry until three pieces are present. Copy them
by hand once (or bake them into the node image): NuGet provider 2.8.5.201 or later, PowerShellGet 2.2.5 and
PackageManagement 1.4.8.1. Then register the repository and install:

```powershell
$repo = @{
    Name               = 'LocalGallery'
    SourceLocation     = '<registry v2 URL>'
    PublishLocation    = '<registry v2 URL>'
    InstallationPolicy = 'Trusted'
}
Register-PSRepository @repo
Install-Module WSUS -Repository LocalGallery -Scope AllUsers -Force -Credential (Get-Credential)
```

The v2 URL is the project-level NuGet v2 feed of the GitLab package registry. It will change when the registry
moves to the self-hosted GitLab: `Unregister-PSRepository LocalGallery`, then register again. No module change.
Only after the module is installed, run `Register-WsusMaintenanceTask`.

## 2. Before the first build

- [ ] Two Server Core VMs, each with a ~100 GB data disk (`D:`).
- [ ] One certificate per node in `Cert:\LocalMachine\My`:
  - WSUS01 SANs: `wsus.corp.local`, `wsus01.corp.local`
  - WSUS02 SANs: `wsus.corp.local`, `wsus02.corp.local`
  - Server Authentication EKU, RSA 2048+, chain trusted by every client.
- [ ] .NET strong crypto on both nodes: `SchUseStrongCrypto=1` and `SystemDefaultTlsVersions=1` under
  `HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319` and its `WOW6432Node` twin.
- [ ] DNS A record `wsus.corp.local` → NetScaler VIP.
- [ ] Firewall: clients → VIP on 8530 and 8531; NetScaler → nodes on 8530 and 8531;
  WSUS02 → WSUS01 on 8530 and 8531; WSUS01 → Microsoft on 443 through the proxy.
- [ ] AD: `id.sa.platforms` exists. Create an `id` group of pilot computers and nest it in
  `res.ent.wsus.pilot` (Domain Local).
- [ ] Pilot holds at least one Windows 11 machine, one Server 2022 and one Server 2025, or `Approve-WsusRing`
  holds back updates nobody tested.
- [ ] Ansible `configure_update` role registers Packer builds with `TargetGroup = Packer`.
- [ ] Citrix admin leaves `wuauserv` at Manual (not Disabled) on the VDA image.
- [ ] The `WSUS` module is installed on both nodes and the admin workstation (section 1).

## 3. Initial build

| Step | Where | Command |
|------|-------|---------|
| 1 | Admin workstation | `New-WsusAdminGroup -WhatIf`, then without `-WhatIf` (add `-GroupPath <OU dn>` to choose the OU) |
| 2 | WSUS01 | `Install-WsusNode -ContentPath D:\WSUS`. If `RestartNeeded` is true, restart before the next step. |
| 3 | WSUS01 | `Set-WsusNodeConfig -SslCertThumbprint <WSUS01 thumb> -VipFqdn wsus.corp.local` |
| 4 | WSUS01 | `Set-WsusUpstreamConfig -ProxyHost <proxy>` (creates the approval rules **off**) |
| 5 | WSUS01 | `Start-WsusSync -Wait`. Nothing downloads yet: nothing is approved. |
| 6 | WSUS01 | `Invoke-WsusMaintenance -SupersededAgeDays 0` (declines every superseded, ARM64, preview and old-Windows-11-version update) |
| 7 | WSUS01 | `Enable-WsusApprovalRule -Name 'Auto - *'`, then `Set-WsusUpstreamConfig -ProxyHost <proxy> -ApplyRulesNow` (approves what's left for Packer and Pilot) |
| 8 | WSUS02 | `Install-WsusNode` |
| 9 | WSUS02 | `Set-WsusNodeConfig -SslCertThumbprint <WSUS02 thumb> -VipFqdn wsus.corp.local` |
| 10 | WSUS02 | `Set-WsusReplicaConfig -UpstreamFqdn wsus01.corp.local -SyncNow` |
| 11 | WSUS01 | `Register-WsusMaintenanceTask` (weekly maintenance Sunday 02:00) |
| 12 | WSUS02 | `Register-WsusMaintenanceTask -MaintenanceTime 04:00` |
| 13 | NetScaler | Apply `docs/6-netscaler-wsus.conf` (edit IPs first) |
| 14 | Admin workstation | Create the client GPOs by hand (section 7) |
| 15 | One client per GPO | `gpupdate /force`, then the client check below. Confirm it shows up in the right group on WSUS01. |

Run the TLS checks before step 14: `https://<node>:8531/ClientWebService/client.asmx` returns 200 on both nodes.

Client check (run on the client, elevated):

```powershell
(New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
```

Then look for the client in the right group in the WSUS console on WSUS01. Allow a few minutes.

Step 4 answers a missing product title with a categories-only sync, and throws before saving anything if the
title is still unknown. To choose products first, run `Start-WsusSync -CategoryOnly -Wait` and list titles
with `Get-WsusProduct`.

## 4. Scheduled tasks

`Register-WsusMaintenanceTask` creates two SYSTEM tasks (highest run level) on the node, under fixed names. Run
it on **every** node, replicas included; it replaces both tasks if they exist.

| Task | Runs | Default schedule | Time limit |
|------|------|------------------|------------|
| `WSUS Maintenance` | `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-WsusMaintenance"` | Weekly, Sunday 02:00 | 12 hours |
| `WSUS Decline Unwanted` | `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-WsusDecline"` | Every 15 minutes, starting at registration | 10 minutes |

```powershell
Register-WsusMaintenanceTask -WhatIf
Register-WsusMaintenanceTask                              # WSUS01
Register-WsusMaintenanceTask -MaintenanceTime 04:00       # WSUS02 (stagger the nodes)
Register-WsusMaintenanceTask -MaintenanceDay Saturday -DeclineIntervalMinutes 30
Unregister-WsusMaintenanceTask                            # decommission a node
```

- Parameters: `-MaintenanceDay`, `-MaintenanceTime` (HH:mm), `-DeclineIntervalMinutes`. The tasks run the
  functions with their defaults.
- It throws before registering anything unless the session is elevated and the module is installed for all users.
- `Invoke-WsusDecline` exits quietly on a replica (`Role = Replica`, `Declined = 0`), so promoting a replica
  needs no re-registration.
- Both write a transcript under `C:\ProgramData\WsusMaintenance` (12 maintenance, 96 decline). A failing step
  throws, so Task Scheduler shows the run as failed.
- Overlapping runs are ignored (`IgnoreNew`).

## 5. Monthly patch cycle

Sync times are UTC: WSUS01 at 02:00 and 14:00, WSUS02 two hours later.
That is 04:00 local in summer, 03:00 in winter.

| When | What happens | You do |
|------|--------------|--------|
| Tue, week 1 (Patch Tuesday) | Microsoft releases ~19:00 local | Nothing |
| Wed, week 1, early morning | WSUS01 syncs; rules approve Critical + Security for Packer and Pilot; decline task removes ARM64/preview; WSUS02 copies it all | Nothing |
| Wed, week 1 | — | Run the Packer build. A clean build is the first gate. |
| Thu, week 1, 19:00 | Pilot installs and restarts (GPO schedule) | Nothing |
| Fri–Mon | Pilot soaks | Watch for tickets |
| Mon, week 2 | — | `Approve-WsusRing -WhatIf \| Format-Table -AutoSize` and review the Held rows |
| Tue, week 2 | — | `Approve-WsusRing \| Format-Table -AutoSize` |
| Wed, week 2, 19:00 | Workstations install and restart | Nothing |
| Thu, week 2, 19:00 | Servers install and restart | Nothing |
| Fri, week 2 | — | Check "Needed" counts on WSUS01 for stragglers (machines that were off) |

Definition updates skip all of this. They approve automatically for Packer, Pilot, Workstations and
VDI as soon as they sync.

**The gate.** `Approve-WsusRing` promotes Critical and Security updates approved for `-From` (Pilot) to `-To`
(Workstations, Servers) only if every rule holds:

- soaked at least `-MinimumSoakDays` (5) since the earliest Pilot approval;
- at least one Pilot computer needed it (it was actually tested);
- at least `-MinimumInstalledPercent` (90) of the Pilot computers that need it have it installed (installed and
  installed-pending-reboot both count);
- no Pilot computer failed to install it.

One `WSUS.RingApproval` row per update: `Update`, `Kb`, `Installed`, `Needed`, `Percent`, `Failed`, `Gate`
(`Passed`, `Held` or `Forced`), `Reason`, `ApprovedTo`. Declined and superseded updates are skipped, and an
update already approved for some groups is approved only for the missing ones. Approval is Install with no
deadline: the GPO schedule decides when it installs. If any update is held, one warning at the end gives the
count and names `-Force` and `-WhatIf`. `-Force` bypasses every rule. `-Confirm` prompts per update and group.
It refuses to run on a replica.

## 6. Out-of-band or zero-day update

1. Make sure it synced: `(Get-WsusServer).SearchUpdates('<KB number>')` on WSUS01. If it's classified as plain
   **Updates**, add that classification for one sync:
   `Set-WsusUpstreamConfig -ProxyHost <proxy> -Classification 'Critical Updates','Security Updates','Definition Updates','Updates'`,
   then run it again without `'Updates'` afterwards.
2. It auto-approves for Pilot (or approve it by hand in the console if step 1 applied).
3. Let Pilot install at the next window, or have Pilot machines run a scan and install now.
4. After 24 hours: `Approve-WsusRing -MinimumSoakDays 1 -Force`.
5. Production installs at its next scheduled window.

## 7. Client GPOs (by hand)

There is no function for client GPOs: create them in GPMC. This keeps the GroupPolicy/RSAT dependency out of
the module. Create one GPO per ring, with **user configuration disabled**, and set the values below under
Computer Configuration → Policies → Administrative Templates → Windows Components → Windows Update (registry
values are under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`, `...\AU` and, for VDI, Defender).

**Common to every GPO**

| Setting (registry value) | Value |
|--------------------------|-------|
| `WUServer`, `WUStatusServer` (string) | `https://wsus.corp.local:8531` |
| `TargetGroupEnabled` | 1 |
| `TargetGroup` (string) | The ring name from the table below |
| `DoNotConnectToWindowsUpdateInternetLocations` | 1 |
| `DisableDualScan` | 1 |
| `SetPolicyDrivenUpdateSourceForQualityUpdates`, `...FeatureUpdates`, `...DriverUpdates`, `...OtherUpdates` | 1 |
| `ExcludeWUDriversInQualityUpdate` | 1 |
| `AU\UseWUServer` | 1 |

**Per ring**

| GPO | TargetGroup | Install day (`ScheduledInstallDay`) | Linked to | Security filter |
|-----|-------------|-------------------------------------|-----------|-----------------|
| WSUS - Workstations | `Workstations` | Wednesday (4) | Workstation OUs | Authenticated Users |
| WSUS - Servers | `Servers` | Thursday (5) | Server OUs | Authenticated Users |
| WSUS - Pilot | `Pilot` | Thursday (5) | Workstation and server OUs, **link order 1** | `res.ent.wsus.pilot` gets Apply; Authenticated Users keeps Read only |
| WSUS - VDI | `VDI` | none (definitions only) | VDA OU | Authenticated Users |

Install days use 1 = Sunday … 7 = Saturday.

**Workstations, Servers and Pilot (scheduled install)**

| Setting (registry value under `AU`) | Value |
|-------------------------------------|-------|
| `NoAutoUpdate` | 0 |
| `AUOptions` | 4 (auto download and schedule the install) |
| `ScheduledInstallDay` | per table above |
| `ScheduledInstallTime` | 19 (19:00 client local time) |
| `ScheduledInstallEveryWeek` | 1 |
| `AlwaysAutoRebootAtScheduledTime` | 1 |
| `AlwaysAutoRebootAtScheduledTimeMinutes` | 15 (restart warning, 15 to 180) |
| `DetectionFrequencyEnabled` | 1 |
| `DetectionFrequency` | 22 (hours; spreads thousands of clients out) |

**VDI (Defender definitions only)**

The OS patches for non-persistent Citrix VDAs come from the golden image, so automatic updates are off and
only Defender pulls security intelligence from WSUS.

| Setting (registry value) | Value |
|--------------------------|-------|
| `AU\NoAutoUpdate` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates\FallbackOrder` (string) | `InternalDefinitionUpdateServer` |
| `...\Signature Updates\SignatureUpdateInterval` | 4 (hours) |
| `...\Signature Updates\UpdateOnStartUp` | 1 |

The VDA image must leave `wuauserv` at Manual, not Disabled, or Defender cannot reach WSUS. Linked at the VDA
OU, this GPO outranks the Workstations GPO even if that OU sits under a workstation OU.

**How rings are assigned.** Every machine gets Workstations or Servers by default. The Pilot GPO has link
order 1 and is security-filtered, so its values win only for computers in `res.ent.wsus.pilot`. Moving a
machine in or out of Pilot is a group membership change; it applies after a reboot. Approvals decide WHAT a
ring installs; the schedule decides WHEN. Packer builds are not covered by a GPO: the Ansible `configure_update`
role registers them with `TargetGroup = Packer`.

## 8. Pilot finds a bad update

1. Don't run `Approve-WsusRing` (or let it hold the update).
2. On WSUS01, decline it: `Deny-WsusUpdate -Kb KB5001234 -WhatIf`, then without `-WhatIf`. It matches the KB
   exactly (all product and architecture variants). WSUS02 picks the decline up on its next sync.
3. Remove it from Pilot machines. A combined SSU+LCU can't be removed with `wusa /uninstall`; use
   `DISM /Online /Get-Packages` to find the LCU package name, then `DISM /Online /Remove-Package /PackageName:<name>`.

## 9. Patching the WSUS servers themselves

Both nodes are in the `Servers` group by default, so they'd restart in the same window. Put
**WSUS02 in Pilot** (add it to the pilot `id` group) so the two never restart in the same week.

If WSUS01 is down during its window, the NetScaler fails clients over to WSUS02 (see section 10).

## 10. WSUS01 goes down (unplanned)

Nothing to run. The NetScaler sends clients to WSUS02. Each client registers there and does one full scan,
then keeps patching with the same approvals.

While WSUS01 is down:
- No new syncs or approvals. `Approve-WsusRing` and the rule and decline functions refuse to run against the replica.
- If WSUS01 won't be back before the next Patch Tuesday, use section 11 instead.

**Failback**, once WSUS01 is healthy and in a quiet period (not during the 19:00–23:00 window):

```
enable lb vserver vs_wsus_8530
enable lb vserver vs_wsus_8531
```

Clients register with WSUS01 again on their next scan.

## 11. WSUS01 is lost for good

| Step | Where | Command |
|------|-------|---------|
| 1 | WSUS02 | `ConvertTo-WsusUpstream -WhatIf`, then `ConvertTo-WsusUpstream` (High impact, so it prompts). It refuses while the old upstream still answers unless `-Force`. |
| 2 | WSUS02 | `Set-WsusUpstreamConfig -ProxyHost <proxy>` |
| 3 | WSUS02 | `Enable-WsusApprovalRule -Name 'Auto - *'` |
| 4 | WSUS02 | `Start-WsusSync -Wait` |
| 5 | NetScaler | Swap the roles: bind `svc_wsus02_*` to `vs_wsus_8530`/`vs_wsus_8531` and `svc_wsus01_*` to the `_bk` vservers |
| 6 | New VM | Build it as the replica: section 12, with `-UpstreamFqdn wsus02.corp.local` |

WSUS02's existing scheduled tasks start declining automatically once it's no longer a replica.
Firewall: open the new replica → WSUS02 on 8530/8531, and WSUS02 → Microsoft through the proxy.

## 12. Build or rebuild the replica

| Step | Where | Command |
|------|-------|---------|
| 1 | Replica | Install the module (section 1) |
| 2 | Replica | `Install-WsusNode` |
| 3 | Replica | `Set-WsusNodeConfig -SslCertThumbprint <thumb> -VipFqdn wsus.corp.local` |
| 4 | Replica | `Set-WsusReplicaConfig -UpstreamFqdn <upstream fqdn> -SyncNow` |
| 5 | Replica | `Register-WsusMaintenanceTask -MaintenanceTime 04:00` |

`Set-WsusReplicaConfig` probes the upstream first and refuses to point a node at itself, or to demote a
configured upstream without `-Force`. The first sync copies every approval and downloads all approved content
from the upstream.

## 13. Repair or reinstall WSUS on a node

Run `Install-WsusNode -Force` (it re-runs postinstall; it never reboots, so check `RestartNeeded`), then
`Set-WsusNodeConfig`. On the replica, also run `Set-WsusReplicaConfig -UpstreamFqdn <upstream fqdn> -SyncNow`.

## 14. Certificate renewal

1. Install the new certificate on the node (same SANs).
2. `Set-WsusNodeConfig -SslCertThumbprint <new thumb> -VipFqdn wsus.corp.local`
3. Check: `netsh http show sslcert ipport=0.0.0.0:8531` shows the new hash.

`Set-WsusNodeConfig` refuses certificates within 30 days of expiry, so renew before then. It always restarts
IIS and WSUS.

## 15. Day-to-day changes

| Change | Do |
|--------|-----|
| Machine into or out of Pilot | Change its membership in the pilot `id` group; it applies after a reboot |
| New workstation/server/VDA OU | Link the matching client GPO (section 7) to it |
| Change an install day or time | Edit the `ScheduledInstallDay` / `ScheduledInstallTime` values in the GPO |
| Change the maintenance or decline schedule | Re-run `Register-WsusMaintenanceTask` with new `-MaintenanceDay`, `-MaintenanceTime` or `-DeclineIntervalMinutes` |
| Add a product | Section 18. The next sync brings in that product's whole history, so treat it like a first build |
| Remove a product or classification | `Set-WsusUpstreamConfig` with the shorter `-Product` or `-Classification` list, then `Invoke-WsusMaintenance` |
| Change which groups auto-approve | `Set-WsusUpstreamConfig` with `-CritSecGroup` or `-DefinitionGroup` (rules keep their on/off state) |
| Turn approval rules on or off | `Enable-WsusApprovalRule -Name 'Auto - *'` / `Disable-WsusApprovalRule` |

## 16. Health checks

| Check | Command |
|-------|---------|
| Role, last sync and its error, whether a sync is running (phase and progress), update, approved and declined counts, content disk, newest maintenance and decline logs | `Get-WsusNodeStatus` (on the node) |
| Several nodes | `'wsus01.corp.local','wsus02.corp.local' \| Get-WsusNodeStatus` (disk and logs are `$null` for a remote node) |
| Little free content disk | `Get-WsusNodeStatus \| Where-Object ContentFreePercent -lt 15` |
| A sync that failed or is still running | `Get-WsusNodeStatus \| Where-Object { $_.LastSyncResult -eq 'Failed' -or $_.SyncStatus -eq 'Running' }` |
| Scheduled tasks | `Get-ScheduledTask -TaskName 'WSUS*' \| Get-ScheduledTaskInfo` |
| Maintenance results | Newest `C:\ProgramData\WsusMaintenance\maint_*.log` and `decline_*.log` |
| NetScaler state | `show lb vserver vs_wsus_8531` (primary UP, backup not in use) |
| Client side | `Get-WindowsUpdateLog` on the client, then search for `wsus.corp.local` |
| Client scan | `(New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()` on the client |
| VDA definitions | `Get-MpComputerStatus` → `AntivirusSignatureLastUpdated` is recent |

`Get-WsusNodeStatus` reports facts only; it has no "healthy" verdict. Filter its output yourself.

## 17. Content disk full

Usually caused by approval rules firing on a full sync: every update that arrived in that sync gets approved,
superseded ones included, and WSUS downloads all of them.

| Step | Where | Command |
|------|-------|---------|
| 1 | Upstream | Stop new approvals: `Disable-WsusApprovalRule` |
| 2 | Upstream | `Invoke-WsusMaintenance -SupersededAgeDays 0` (declines, then deletes unneeded content; the first run can take hours) |
| 3 | Upstream | `Get-WsusNodeStatus` and confirm the space came back |
| 4 | Upstream | `Enable-WsusApprovalRule -Name 'Auto - *'` |
| 5 | Replica | After its next sync picks up the declines: `Invoke-WsusMaintenance` |

## 18. Adding a product (without filling the disk)

| Step | Where | Command |
|------|-------|---------|
| 1 | Upstream | Turn the rules off: `Disable-WsusApprovalRule` |
| 2 | Upstream | `Set-WsusUpstreamConfig -ProxyHost <proxy> -Product <full list, including the new one>` |
| 3 | Upstream | `Start-WsusSync -Wait` |
| 4 | Upstream | `Invoke-WsusMaintenance -SupersededAgeDays 0` |
| 5 | Upstream | `Enable-WsusApprovalRule -Name 'Auto - *'`, then `Set-WsusUpstreamConfig -ProxyHost <proxy> -Product <same list> -ApplyRulesNow` |

## 19. Releasing the module (maintainers)

Versioning is SemVer. The manifest `ModuleVersion` (`src/WSUS/WSUS.psd1`) is the only place the version is
typed. Stay on `0.x` until a full run on a real upstream and replica passes the manual verification checklist;
then `1.0.0`. After that: MAJOR breaks a scheduled task or calling script (renamed functions or parameters,
removed result properties, changed task names or defaults), MINOR adds functions, parameters or result
properties, PATCH fixes. While on `0.x`, MINOR may break. Record changes in `CHANGELOG.md` (Keep a Changelog;
entries describe what an operator sees, with a "Breaking" subsection when needed).

Local checks: `./build.ps1 -Task All` runs PSScriptAnalyzer and the Pester tests. CI only calls the same script.

Publish runbook (manual; CI never publishes):

1. Merge to `main` with CI green.
2. Run the manual verification checklist on a real node: everything for a MINOR or MAJOR, the touched areas for
   a PATCH.
3. Release commit: move `Unreleased` under a dated `## [X.Y.Z] - date` heading and bump `ModuleVersion`.
4. Tag and push: `git tag -a vX.Y.Z -m vX.Y.Z`, then `git push origin vX.Y.Z`.
5. `./build.ps1 -Task Release`. It fails unless the manifest version equals the tag on `HEAD`, the changelog has
   a section for it and the tree is clean. It stages `src/WSUS/` only, with the release notes filled in.
6. `Publish-Module -Path <staged folder> -Repository LocalGallery -NuGetApiKey <write token>`. Enter the
   write-scoped token at publish time; never store it.
7. Verify: `Find-Module WSUS -Repository LocalGallery -RequiredVersion X.Y.Z`.
8. Roll out (section 1), replica first, then the upstream.

There are no pre-release versions: test a candidate by importing from `src/WSUS` on a test node. A bad release
is never overwritten or deleted: fix forward with a PATCH, add `### Known issues` to the bad version's
changelog entry, and nodes can pin back with `-RequiredVersion`.
