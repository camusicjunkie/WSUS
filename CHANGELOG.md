# Changelog

All notable changes to the WSUS module are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `Start-WsusSync -Wait` no longer returns before a sync that was just requested has started; it waits for the sync to begin (or throws after a minute) and then for it to finish.
- `Approve-WsusRing` counts clients that have not reported on an update as not yet installed, so a ring with many silent machines no longer passes the install-percentage gate. The output gains an `Unknown` column.
- `Set-WsusUpstreamConfig` and the approval rule helper throw on a classification or computer group name that matches nothing, instead of saving an empty list. The rule is validated before it is created.
- `Set-WsusNodeConfig` throws when `-Domain` is empty or is this machine's name (for example when signed in with a local account), instead of adding `MACHINE\group` to `WSUS Administrators`.

### Changed

- Internal: backtick line continuations replaced with splatting, `StartsWith` replaced with `-like`, and the `Invoke-WsusDeclinePass` pattern comment now says regular expression. Added tests for `Invoke-WsusDeclinePass`, `Set-WsusApprovalRuleDefinition` and `Set-WsusSyncSchedule`.

## [1.0.0] - 2026-10-19

### Added

- `Install-WsusNode` and `Set-WsusNodeConfig` (local-only node install and configuration), replacing scripts 1 and 2.
- `Set-WsusUpstreamConfig`: configures the upstream (sync source, products, classifications, schedule, groups, approval rules created off; `-ApplyRulesNow` applies only rules that are on). `-EnableRules` is replaced by `Enable-WsusApprovalRule`; a missing product title now throws.
- `New-WsusAdminGroup`: creates the res.srv.wsus.admin resource group and nests the identity group into it (idempotent, `-WhatIf` aware).
- `WSUS` PowerShell module for Windows PowerShell 5.1, with `Get-WsusNodeStatus`, which reports a node's role, last sync and its error, whether a sync is running (phase and progress), update, approved and declined counts, content disk and newest maintenance and decline logs (disk and logs on the local node only).
- `Start-WsusSync`, which starts a full or `-CategoryOnly` (upstream-only) sync, joins one already running, and with `-Wait` polls with progress and a timeout.
- `Disable-WsusApprovalRule`, `Enable-WsusApprovalRule` and `Deny-WsusUpdate -Kb` for turning approval rules off and on and declining updates by exact KB (upstream only).
- `Invoke-WsusMaintenance` (weekly maintenance run on the local node: declines on an upstream, cleanup, WID reindex) and `Invoke-WsusDecline` (15-minute decline run on the upstream, remote-capable), both with transcripts and retention, replacing `-DeclineOnly`.
- `Set-WsusReplicaConfig` and `ConvertTo-WsusUpstream` replace `4-Configure-WsusReplica.ps1`: replica setup with an upstream probe and guards, and a guarded promote for a lost upstream.
- `build.ps1` with `Analyze`, `Test`, `All` and `Release` tasks, and a GitHub Actions workflow that runs it under `pwsh` and Windows PowerShell 5.1.
- `Approve-WsusRing` promotes updates from one ring to the next only when they pass the gate, returning one `WSUS.RingApproval` row per update; replaces `8-Approve-WsusRing.ps1`.
- `Register-WsusMaintenanceTask` and `Unregister-WsusMaintenanceTask`: create or remove the fixed-name SYSTEM `WSUS Maintenance` and `WSUS Decline Unwanted` tasks (replace on re-register, all-users install preflight).

- README runbook rewritten around function calls: initial build, scheduled tasks, monthly cycle, per-ring client GPO settings table, module install and release runbook.

### Changed

- `Set-WsusReplicaConfig -Force` on an upstream that has its own state now turns its approval rules off first and reports them in `DisabledRules` (#37).
- `Get-WsusNodeStatus` reports `DownloadPendingMB` and `DownloadFailedCount`. A replica only receives an approved update once the upstream has its content, so the runbook now waits for the upstream's downloads before comparing approval counts (#37).
- `Approve-WsusRing`: the default `-Classification` is now taken from the Critical and Security approval rule, so the two cannot drift apart. No change in value.
- `Set-WsusUpstreamConfig` now also sets `GetContentFromMU = $true`, as a promoted node already had it. `ConvertTo-WsusUpstream` and `Set-WsusReplicaConfig` set the same content flags as `Set-WsusUpstreamConfig`.
- Internal: shared helpers for the sync source, sync schedule, endpoint, ring plan, run log, approval rule state and role check replace code repeated across public functions. Parameters and output are unchanged except as listed under Removed.

### Removed

- `1-Install-WsusNode.ps1` and `2-Set-WsusNodeConfig.ps1`, replaced by `Install-WsusNode` and `Set-WsusNodeConfig`.
- `3-Configure-WsusUpstream.ps1`, replaced by `Set-WsusUpstreamConfig`.
- `0-New-WsusAdminGroup.ps1`, replaced by `New-WsusAdminGroup`.
- `5-Invoke-WsusMaintenance.ps1`, replaced by `Invoke-WsusMaintenance` and `Invoke-WsusDecline`. Register the tasks with `Register-WsusMaintenanceTask` (the script's task snippet is gone).
- `7-New-WsusClientGpo.ps1`. Client GPOs are created by hand; there is no replacement function.
- `Set-WsusUpstreamConfig -UpstreamServer` and `-UpstreamPort`, and the `Upstream` property of its `WSUS.UpstreamConfig` output. An Upstream always syncs from Microsoft Update; a node that syncs from another Upstream is a Replica (`Set-WsusReplicaConfig`).
