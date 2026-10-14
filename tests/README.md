# Test conventions

Design source of truth: issues #8 (test and CI strategy), #9 (helpers), #15 (release).

## Layout

```
src/WSUS/WSUS.psd1          manifest: the only place the version is typed; FunctionsToExport is hand-listed
src/WSUS/WSUS.psm1          dot-sources Private/*.ps1 then Public/*.ps1 (nothing else lives here)
src/WSUS/Public/<Fn>.ps1    one public function per file, file name = function name, comment-based help required
src/WSUS/Private/<Fn>.ps1   one private helper per file
tests/Module.Tests.ps1      contract: manifest valid, export list == Public/ files, help on every public function
tests/Unit/Public/<Fn>.Tests.ps1   one per public function (the main test seam)
tests/Unit/Private/<Fn>.Tests.ps1  only for helpers with decisions no public test reaches yet
tests/helpers/TestSetup.ps1        dot-source in BeforeAll; pair with AfterAll { Remove-WsusTestEnvironment }
tests/helpers/New-FakeWsusServer.ps1   shared fake IUpdateServer
tests/stubs/<Module>/<Module>.psm1     stub modules
```

Adding a public function: create `Public/<Name>.ps1`, add the name to `FunctionsToExport` in the
manifest, add `tests/Unit/Public/<Name>.Tests.ps1`, add a CHANGELOG `Unreleased` line.

## Running

`./build.ps1 -Task Analyze | Test | All | Release`. Pester (5.7.1) and PSScriptAnalyzer (1.24.0) are pinned
in `build.ps1`, which installs them for the current user if missing. Run it under both `powershell.exe`
(5.1, the real target) and `pwsh`; CI does. Results go to `artifacts/` (gitignored). Coverage is reported only.

## Writing a test

```powershell
BeforeAll { . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1') }   # depth: Unit\Public = ..\..
AfterAll  { Remove-WsusTestEnvironment }
```

`TestSetup.ps1` prepends `tests/stubs` to `PSModulePath` (so `Get-Module -ListAvailable` finds the stubs),
imports the stubs and `src/WSUS` globally, and loads `New-FakeWsusServer`.

- Test through the public function, as an operator would: assert the returned typed object, terminating
  errors, `-WhatIf`/`ShouldProcess`, and effects recorded on the fake (`$fake.Calls`). Do not assert helper
  internals or call counts that mirror the implementation.
- Mock from outside the module with `Mock -ModuleName WSUS <Command> { ... }` (and `Should -Invoke -ModuleName WSUS`).
  The usual mocks: `Get-WsusServer` returns the fake; `Get-WsusLocalFqdn` returns a fixed name.
- Stub bodies throw, so an unmocked call fails loudly. Stubs: `UpdateServices` (cmdlets plus an `Add-Type`
  stub of the Administration enums; enum names and values are guessed and unverified), `ActiveDirectory`,
  `WebAdministration`, `ServerManager` (`Get-WindowsFeature`). `Deny-WsusUpdate` is left out of the
  `UpdateServices` stub because the module defines its own. No `GroupPolicy` stub: the GPO function was dropped (#14).
- `New-FakeWsusServer` takes `-Name -IsReplica -ContentPath -LastSyncStart -LastSyncResult`; extend it (and
  record calls from new ScriptMethods) when a function needs more of `IUpdateServer`.
- Wrapper seams (database query, app pool, SSL binding, file access, WSUS utility, service restart; #9) are
  mocked by name; they arrive with the functions that need them.
- Results are `[PSCustomObject]` with a `WSUS.*` `PSTypeName`.

## PSScriptAnalyzer

Settings in `PSScriptAnalyzerSettings.psd1` (default rules plus 5.1 syntax and cmdlet compatibility; fails on
Warning and Error). No blanket exclusions: suppress inline with `SuppressMessageAttribute` inside the function
and a justification. `tests/stubs` is the one excluded location. State-changing functions need `SupportsShouldProcess`.
