# Changelog

All notable changes to the WSUS module are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `Set-WsusUpstreamConfig`: configures the upstream (sync source, products, classifications, schedule, groups, approval rules created off; `-ApplyRulesNow` applies only rules that are on). `-EnableRules` is replaced by `Enable-WsusApprovalRule`; a missing product title now throws.
- `New-WsusAdminGroup`: creates the res.srv.wsus.admin resource group and nests the identity group into it (idempotent, `-WhatIf` aware).
- `WSUS` PowerShell module for Windows PowerShell 5.1, with `Get-WsusNodeStatus`, which reports a node's role, last sync, content disk and newest maintenance and decline logs (disk and logs on the local node only).
- `Start-WsusSync`, which starts a full or `-CategoryOnly` (upstream-only) sync, joins one already running, and with `-Wait` polls with progress and a timeout.
- `Disable-WsusApprovalRule`, `Enable-WsusApprovalRule` and `Deny-WsusUpdate -Kb` for turning approval rules off and on and declining updates by exact KB (upstream only).
- `build.ps1` with `Analyze`, `Test`, `All` and `Release` tasks, and a GitHub Actions workflow that runs it under `pwsh` and Windows PowerShell 5.1.

### Removed

- `3-Configure-WsusUpstream.ps1`, replaced by `Set-WsusUpstreamConfig`.
- `0-New-WsusAdminGroup.ps1`, replaced by `New-WsusAdminGroup`.
- `7-New-WsusClientGpo.ps1`. Client GPOs are created by hand; there is no replacement function.
