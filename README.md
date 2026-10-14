# WSUS (WID, upstream + replica)

Two Server Core WSUS nodes behind the NetScaler VIP `wsus.corp.local`:

- **WSUS01** – upstream. Syncs from Microsoft, holds every approval, decline and computer group.
- **WSUS02** – replica of WSUS01. Copies approvals and content. Takes client traffic only when WSUS01 is down.

Each node has its own Windows Internal Database (WID) and its own content disk. Nothing is shared.

Computer groups: `Packer`, `Pilot`, `Workstations`, `Servers`, `VDI-Definitions`.

## Scripts

| # | Script | Run on | Run as | When |
|---|--------|--------|--------|------|
| 0 | `0-New-WsusAdminGroup.ps1` | Admin workstation | AD admin | Once |
| 1 | `1-Install-WsusNode.ps1` | Each node | Local admin | Build or rebuild a node |
| 2 | `2-Set-WsusNodeConfig.ps1` | Each node | Local admin | After 1, after a cert renewal, after any WSUS repair |
| 3 | `3-Configure-WsusUpstream.ps1` | WSUS01 (the upstream) | WSUS admin | Once, and when products, classifications, groups or rules change |
| 4 | `4-Configure-WsusReplica.ps1` | WSUS02 (the replica) | WSUS admin | Once, or `-Promote` if WSUS01 is lost |
| 5 | `5-Invoke-WsusMaintenance.ps1` | Both nodes | SYSTEM, scheduled task | Weekly, plus `-DeclineOnly` every 15 minutes |
| 6 | `6-netscaler-wsus.conf` | NetScaler CLI | NetScaler admin | Once |
| 7 | `7-New-WsusClientGpo.ps1` | Admin workstation | GPO admin | Once, and when OUs, days or the WSUS URL change |
| 8 | `8-Approve-WsusRing.ps1` | WSUS01 (the upstream) | WSUS admin | Monthly, week 2 |

Every PowerShell script supports `-WhatIf`. Run that first, every time.

---

## 1. Before the first build

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
- [ ] Pilot holds at least one Windows 11 machine, one Server 2022 and one Server 2025, or script 8
  holds back updates nobody tested.
- [ ] Ansible `configure_update` role registers Packer builds with `TargetGroup = Packer`.
- [ ] Citrix admin leaves `wuauserv` at Manual (not Disabled) on the VDA image.

## 2. Initial build

| Step | Where | Command |
|------|-------|---------|
| 1 | Admin workstation | `.\0-New-WsusAdminGroup.ps1` |
| 2 | WSUS01 | `.\1-Install-WsusNode.ps1` |
| 3 | WSUS01 | `.\2-Set-WsusNodeConfig.ps1 -SslCertThumbprint <WSUS01 thumb> -VipFqdn wsus.corp.local` |
| 4 | WSUS01 | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy>` (creates the approval rules **off**) |
| 5 | WSUS01 | `(Get-WsusServer).GetSubscription().StartSynchronization()` and wait for it to finish. Nothing downloads yet: nothing is approved. |
| 6 | WSUS01 | `.\5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0` (declines every superseded, ARM64, preview and old-Windows-11-version update) |
| 7 | WSUS01 | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy> -EnableRules -ApplyRulesNow` (turns the rules on and approves what's left for Packer and Pilot) |
| 8 | WSUS02 | `.\1-Install-WsusNode.ps1` |
| 9 | WSUS02 | `.\2-Set-WsusNodeConfig.ps1 -SslCertThumbprint <WSUS02 thumb> -VipFqdn wsus.corp.local` |
| 10 | WSUS02 | `.\4-Configure-WsusReplica.ps1 -UpstreamFqdn wsus01.corp.local -SyncNow` |
| 11 | Both nodes | Register the two scheduled tasks (commands in the help of script 5). Weekly at 02:00 on WSUS01, 04:00 on WSUS02. |
| 12 | NetScaler | Apply `6-netscaler-wsus.conf` (edit IPs first) |
| 13 | Admin workstation | `.\7-New-WsusClientGpo.ps1 -WorkstationOU <dn> -ServerOU <dn> -VdiOU <dn>` |
| 14 | One client per GPO | `gpupdate /force`, then `(New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()`. Confirm it shows up in the right group on WSUS01. |

Run the TLS checks from the certificate notes before step 13: `https://<node>:8531/selfupdate/wuident.cab` returns 200 on both nodes.

## 3. Monthly patch cycle

Sync times are UTC: WSUS01 at 02:00 and 14:00, WSUS02 two hours later.
That is 04:00 local in summer, 03:00 in winter.

| When | What happens | You do |
|------|--------------|--------|
| Tue, week 1 (Patch Tuesday) | Microsoft releases ~19:00 local | Nothing |
| Wed, week 1, early morning | WSUS01 syncs; rules approve Critical + Security for Packer and Pilot; decline task removes ARM64/preview; WSUS02 copies it all | Nothing |
| Wed, week 1 | — | Run the Packer build. A clean build is the first gate. |
| Thu, week 1, 19:00 | Pilot installs and restarts (GPO schedule) | Nothing |
| Fri–Mon | Pilot soaks | Watch for tickets |
| Mon, week 2 | — | `.\8-Approve-WsusRing.ps1 -WhatIf \| Format-Table -AutoSize` and review Held updates |
| Tue, week 2 | — | `.\8-Approve-WsusRing.ps1` |
| Wed, week 2, 19:00 | Workstations install and restart | Nothing |
| Thu, week 2, 19:00 | Servers install and restart | Nothing |
| Fri, week 2 | — | Check "Needed" counts on WSUS01 for stragglers (machines that were off) |

Definition updates skip all of this. They approve automatically for Packer, Pilot, Workstations and
VDI-Definitions as soon as they sync.

## 4. Out-of-band or zero-day update

1. Make sure it synced: `(Get-WsusServer).SearchUpdates('<KB number>')` on WSUS01. If it's classified
   as plain **Updates**, add that classification for one sync:
   `.\3-Configure-WsusUpstream.ps1 -Classification 'Critical Updates','Security Updates','Definition Updates','Updates'`,
   then run it again without `'Updates'` afterwards.
2. It auto-approves for Pilot (or approve it by hand if step 1 applied).
3. Let Pilot install at the next window, or have Pilot machines run a scan and install now.
4. After 24 hours: `.\8-Approve-WsusRing.ps1 -MinimumSoakDays 1 -Force`.
5. Production installs at its next scheduled window.

## 5. Pilot finds a bad update

1. Don't run script 8 (or let it hold the update).
2. On WSUS01, decline it:
   `(Get-WsusServer).SearchUpdates('<KB number>') | ForEach-Object { $_.Decline() }`.
   WSUS02 picks the decline up on its next sync.
3. Remove it from Pilot machines. A combined SSU+LCU can't be removed with `wusa /uninstall`; use
   `DISM /Online /Get-Packages` to find the LCU package name, then `DISM /Online /Remove-Package /PackageName:<name>`.

## 6. Patching the WSUS servers themselves

Both nodes are in the `Servers` group by default, so they'd restart in the same window. Put
**WSUS02 in Pilot** (add it to the pilot `id` group) so the two never restart in the same week.

If WSUS01 is down during its window, the NetScaler fails clients over to WSUS02 (see section 7).

## 7. WSUS01 goes down (unplanned)

Nothing to run. The NetScaler sends clients to WSUS02. Each client registers there and does one full
scan, then keeps patching with the same approvals.

While WSUS01 is down:
- No new syncs or approvals. Script 8 refuses to run against the replica.
- If WSUS01 won't be back before the next Patch Tuesday, use section 8 instead.

**Failback**, once WSUS01 is healthy and in a quiet period (not during the 19:00–23:00 window):

```
enable lb vserver vs_wsus_8530
enable lb vserver vs_wsus_8531
```

Clients register with WSUS01 again on their next scan.

## 8. WSUS01 is lost for good

| Step | Where | Command |
|------|-------|---------|
| 1 | WSUS02 | `.\4-Configure-WsusReplica.ps1 -Promote` |
| 2 | WSUS02 | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy> -EnableRules` |
| 3 | WSUS02 | Start a sync: `(Get-WsusServer).GetSubscription().StartSynchronization()` |
| 4 | NetScaler | Swap the roles: bind `svc_wsus02_*` to `vs_wsus_8530`/`vs_wsus_8531` and `svc_wsus01_*` to the `_bk` vservers |
| 5 | New VM | Build it as the replica: section 9, with `-UpstreamFqdn wsus02.corp.local` |

WSUS02's existing scheduled tasks start declining automatically once it's no longer a replica.
Firewall: open the new replica → WSUS02 on 8530/8531, and WSUS02 → Microsoft through the proxy.

## 9. Build or rebuild the replica

| Step | Where | Command |
|------|-------|---------|
| 1 | Replica | `.\1-Install-WsusNode.ps1` |
| 2 | Replica | `.\2-Set-WsusNodeConfig.ps1 -SslCertThumbprint <thumb> -VipFqdn wsus.corp.local` |
| 3 | Replica | `.\4-Configure-WsusReplica.ps1 -UpstreamFqdn <upstream fqdn> -SyncNow` |
| 4 | Replica | Register the two scheduled tasks from the help of script 5 |

The first sync copies every approval and downloads all approved content from the upstream.

## 10. Repair or reinstall WSUS on a node

Run `1-Install-WsusNode.ps1` (it re-runs postinstall), then `2-Set-WsusNodeConfig.ps1`. On the replica,
also run `4-Configure-WsusReplica.ps1 -UpstreamFqdn <upstream fqdn> -SyncNow`.

## 11. Certificate renewal

1. Install the new certificate on the node (same SANs).
2. `.\2-Set-WsusNodeConfig.ps1 -SslCertThumbprint <new thumb> -VipFqdn wsus.corp.local`
3. Check: `netsh http show sslcert ipport=0.0.0.0:8531` shows the new hash.

Script 2 refuses certificates within 30 days of expiry, so renew before then.

## 12. Day-to-day changes

| Change | Do |
|--------|-----|
| Machine into or out of Pilot | Change its membership in the pilot `id` group; it applies after a reboot |
| New workstation/server/VDA OU | Re-run script 7 with the extra OU added |
| Change an install day or time | Re-run script 7 with `-WorkstationInstallDay`, `-ServerInstallDay`, `-PilotInstallDay` or `-InstallHour` |
| Add a product | Section 15. The next sync brings in that product's whole history, so treat it like a first build |
| Remove a product or classification | Re-run script 3 with the shorter `-Product` or `-Classification` list, then run script 5 |
| Change which groups auto-approve | Re-run script 3 with `-CritSecGroup` or `-DefinitionGroup` (rules keep their on/off state) |
| Turn the approval rules on | Re-run script 3 with `-EnableRules` |

## 13. Health checks

| Check | Command (on the node) |
|-------|-----------------------|
| Last sync | `(Get-WsusServer).GetSubscription().GetLastSynchronizationInfo()` |
| Role | `(Get-WsusServer).GetConfiguration().IsReplicaServer` |
| Maintenance results | Newest `C:\ProgramData\WsusMaintenance\maint_*.log` and `decline_*.log` |
| Content disk | `Get-Volume -DriveLetter D` |
| NetScaler state | `show lb vserver vs_wsus_8531` (primary UP, backup not in use) |
| Client side | `Get-WindowsUpdateLog` on the client, then search for `wsus.corp.local` |
| VDA definitions | `Get-MpComputerStatus` → `AntivirusSignatureLastUpdated` is recent |

## 14. Content disk full

Usually caused by approval rules firing on a full sync: every update that arrived in that sync gets
approved, superseded ones included, and WSUS downloads all of them.

| Step | Where | Command |
|------|-------|---------|
| 1 | Upstream | Stop new approvals: `(Get-WsusServer).GetInstallApprovalRules() \| ForEach-Object { $_.Enabled = $false; $_.Save() }` |
| 2 | Upstream | `.\5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0` (declines, then deletes unneeded content; the first run can take hours) |
| 3 | Upstream | `Get-Volume -DriveLetter D` and confirm the space came back |
| 4 | Upstream | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy> -EnableRules` |
| 5 | Replica | After its next sync picks up the declines: `.\5-Invoke-WsusMaintenance.ps1` |

## 15. Adding a product (without filling the disk)

| Step | Where | Command |
|------|-------|---------|
| 1 | Upstream | Turn the rules off: `(Get-WsusServer).GetInstallApprovalRules() \| ForEach-Object { $_.Enabled = $false; $_.Save() }` |
| 2 | Upstream | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy> -Product <full list, including the new one>` |
| 3 | Upstream | `(Get-WsusServer).GetSubscription().StartSynchronization()` and wait for it to finish |
| 4 | Upstream | `.\5-Invoke-WsusMaintenance.ps1 -SupersededAgeDays 0` |
| 5 | Upstream | `.\3-Configure-WsusUpstream.ps1 -ProxyHost <proxy> -Product <same list> -EnableRules -ApplyRulesNow` |
