# Changelog

All notable changes to the WSUS module are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `WSUS` PowerShell module for Windows PowerShell 5.1, with `Get-WsusNodeStatus`, which reports a node's role, last sync, content disk and newest maintenance and decline logs (disk and logs on the local node only).
- `Set-WsusReplicaConfig` and `ConvertTo-WsusUpstream` replace `4-Configure-WsusReplica.ps1`: replica setup with an upstream probe and guards, and a guarded promote for a lost upstream.
- `build.ps1` with `Analyze`, `Test`, `All` and `Release` tasks, and a GitHub Actions workflow that runs it under `pwsh` and Windows PowerShell 5.1.

### Removed

- `7-New-WsusClientGpo.ps1`. Client GPOs are created by hand; there is no replacement function.
