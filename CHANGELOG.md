# Changelog

All notable changes to the WSUS module are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `Install-WsusNode` and `Set-WsusNodeConfig` (local-only node install and configuration), replacing scripts 1 and 2.
- `New-WsusAdminGroup`: creates the res.srv.wsus.admin resource group and nests the identity group into it (idempotent, `-WhatIf` aware).
- `WSUS` PowerShell module for Windows PowerShell 5.1, with `Get-WsusNodeStatus`, which reports a node's role, last sync, content disk and newest maintenance and decline logs (disk and logs on the local node only).
- `Start-WsusSync`, which starts a full or `-CategoryOnly` (upstream-only) sync, joins one already running, and with `-Wait` polls with progress and a timeout.
- `Disable-WsusApprovalRule`, `Enable-WsusApprovalRule` and `Deny-WsusUpdate -Kb` for turning approval rules off and on and declining updates by exact KB (upstream only).
- `Set-WsusReplicaConfig` and `ConvertTo-WsusUpstream` replace `4-Configure-WsusReplica.ps1`: replica setup with an upstream probe and guards, and a guarded promote for a lost upstream.
- `build.ps1` with `Analyze`, `Test`, `All` and `Release` tasks, and a GitHub Actions workflow that runs it under `pwsh` and Windows PowerShell 5.1.
- `Approve-WsusRing` promotes updates from one ring to the next only when they pass the gate, returning one `WSUS.RingApproval` row per update; replaces `8-Approve-WsusRing.ps1`.
- `Register-WsusMaintenanceTask` and `Unregister-WsusMaintenanceTask`: create or remove the fixed-name SYSTEM `WSUS Maintenance` and `WSUS Decline Unwanted` tasks (replace on re-register, all-users install preflight).

### Removed

- `1-Install-WsusNode.ps1` and `2-Set-WsusNodeConfig.ps1`, replaced by `Install-WsusNode` and `Set-WsusNodeConfig`.
- `0-New-WsusAdminGroup.ps1`, replaced by `New-WsusAdminGroup`.
- `7-New-WsusClientGpo.ps1`. Client GPOs are created by hand; there is no replacement function.
