# Research: mocking UpdateServices in Pester on a CI runner (issue #6)

Question: can the `UpdateServices` cmdlets and the `Microsoft.UpdateServices.Administration` object
model be mocked in Pester 5 on a GitHub Actions `windows-latest` runner without WSUS? Parent map: #1.
Blocks #8.

## Verdict

Feasible for the logic of scripts 0, 3, 4, 5, 7 and 8 (everything except the real WSUS, IIS and AD
effects). Pester cannot mock a command that does not exist, so every missing module needs a **stub
module**, and the Administration types need a **stub type** (`Add-Type`). A stub cannot give
fidelity: it proves the script's branching, never that the real API accepts the call. Keep a manual
smoke test on a real WSUS node.

Verified empirically (prototype below) with Pester 5.7.1, under both PowerShell 7.6 and Windows
PowerShell 5.1, on a machine with no WSUS, ActiveDirectory, GroupPolicy or WebAdministration.

## Primary-source facts

| Claim | Source |
|---|---|
| `Get-WsusServer` returns `Microsoft.UpdateServices.Administration.IUpdateServer`; params `-Name -PortNumber [-UseSsl]` | Microsoft Learn, Get-WsusServer: https://learn.microsoft.com/en-us/powershell/module/updateservices/get-wsusserver |
| `windows-latest` is Windows Server 2025 (10.0.26100), PowerShell 7.6.6, Pester 3.4.0 and 5.9.0 installed | actions/runner-images, Windows2025-Readme.md: https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md |
| That readme lists no WSUS role, RSAT, ActiveDirectory, GroupPolicy or IIS (absence from a readme, not an explicit statement they are unavailable) | same |
| `Mock` creates behaviour for an "existing" command; `-ModuleName` injects a mock into a module's scope | Pester docs, Mock: https://pester.dev/docs/commands/Mock |

Windows PowerShell 5.1 is still on the runner and every script says `#Requires -Version 5.1`, so run
the suite under both `pwsh` and `powershell` if 5.1 parity matters.

## What the scripts touch

From grepping the repo scripts (commit d05157f):

- UpdateServices cmdlets: `Get-WsusServer`, `Invoke-WsusServerCleanup`, `Get-WsusProduct`.
- Object model, via `$wsus` methods: `GetConfiguration().IsReplicaServer`, `GetSubscription()`
  (`StartSynchronization`, `StartSynchronizationForCategoryOnly`, `GetSynchronizationStatus`,
  `SetUpdateCategories`, `SetUpdateClassifications`, `Save`), `GetComputerTargetGroups`,
  `CreateComputerTargetGroup`, `GetInstallApprovalRules`, `CreateInstallApprovalRule`,
  `GetUpdateClassifications`, `GetUpdateCategories`, `GetUpdates($scope)`; per update `Decline`,
  `Approve`, `GetUpdateApprovals`, `GetSummaryForComputerTargetGroup`, `AcceptLicenseAgreement`.
- Types named directly in script text (scripts 3, 5, 8): `UpdateScope`,
  `UpdateClassificationCollection`, `ComputerTargetGroupCollection` (via `New-Object`) and enums
  `ApprovedStates`, `UpdateApprovalActions`, `UpdateApprovalAction` (via `[type]::Value`).
- Other modules: ActiveDirectory (`Get-ADGroup`, `New-ADGroup`, `Get-ADGroupMember`,
  `Add-ADGroupMember`), GroupPolicy (`Get-GPO`, `New-GPO`, `Set-GPRegistryValue`, `Set-GPLink`,
  `New-GPLink`, `Set-GPPermission`, `Get-GPInheritance`), WebAdministration (`Get-WebBinding`,
  `New-WebBinding`, `Set-WebConfigurationProperty`, and the `IIS:\AppPools\WsusPool` provider path).

## Technique

### 1. Stub modules for missing cmdlets

Each script has `#Requires -Modules X`. With X absent from `PSModulePath` the script fails before
running any code ("cannot be run because the following modules ... are missing"; observed). So put a
stub module named exactly `UpdateServices` (likewise `ActiveDirectory`, `GroupPolicy`,
`WebAdministration`) in `tests/stubs/<Name>/` with a `.psd1` and `.psm1`, prepend `tests/stubs` to
`$env:PSModulePath` in `BeforeAll`, and `Import-Module` it. Stub functions need only the parameters
the scripts pass (so splats like `@cleanupParams` and `-ParameterFilter` bind); bodies can
`throw 'stub'` so an unmocked call fails loudly. Then `Mock Get-WsusServer { $fake }` works. Mocking
a command that does not exist throws (observed), so the stub is mandatory.

Caveat: a stub missing a parameter the script passes fails to bind, which is a harness bug and not a
script bug. Derive signatures from the Learn cmdlet pages.

### 2. Stub types for the Administration object model

`Microsoft.UpdateServices.Administration.dll` comes with the WSUS Administration Console feature and
is loaded by the UpdateServices module. It is absent on a machine without WSUS (`Add-Type
-AssemblyName Microsoft.UpdateServices.Administration` fails; observed). Scripts 3, 5 and 8 need
things a PSCustomObject cannot supply:

- `New-Object Microsoft.UpdateServices.Administration.UpdateScope` and the two collection classes.
- `[Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved` and the other
  enum literals, which resolve by type name at run time, so a missing type is a hard error.

What worked: `Add-Type -TypeDefinition` of a small C# stub inside the stub module's `.psm1`, guarded
by `if (-not ('...UpdateScope' -as [type]))` so re-import is safe. Minimum surface for script 8:
enums `ApprovedStates`, `UpdateApprovalActions`, `UpdateApprovalAction`; class `UpdateScope` with
`ApprovedStates`, `UpdateApprovalActions`, `FromArrivalDate`, `ApprovedComputerTargetGroups`,
`Classifications`; collections exposing `Add` and `Count` (a `List<object>` subclass is enough).
Enum numeric values in the prototype were guessed, so only the names are trustworthy. Check them
against the real assembly (`[enum]::GetValues` on a node) before any test compares values.

### 3. Faking the `Get-WsusServer` object

A `[pscustomobject]` with `Add-Member ScriptMethod` per method the script calls is enough, with
`Mock Get-WsusServer { $wsus }`. Gotchas hit:

- Return arrays from script methods as `,@(...)` so single and empty results keep array behaviour
  (`.Count`, `Where-Object`).
- A ScriptMethod did not see the test's `$script:` variable (null-valued method call, observed).
  Record calls on the fake itself (`$this.Calls.Add(...)`) and assert on that.
- `Mock` bodies do not capture test locals unless `.GetNewClosure()` is used.
- `Should -Invoke` counts only command calls, not object methods; assert on the recorded-call list.
- `GetUpdateApprovals($g).Count -eq 0` works with plain arrays; the script only uses `.Count`.

### 4. Prototype (passing)

Script 8 ran unmodified against stubs: gate Passed, `Approve` called for `Workstations` then
`Servers`. Pester 5.7.1 on pwsh 7.6.6 and Windows PowerShell 5.1.26100: 2/2 tests passed on both
(the second test asserts that Mock of an absent command throws). Skeleton:

```powershell
BeforeAll {
  $env:PSModulePath = "$PSScriptRoot\stubs;$env:PSModulePath"
  Import-Module UpdateServices -Force   # stub .psm1 does the Add-Type for enums and classes
}
It 'promotes' {
  $upd = [pscustomobject]@{ Title='KB1'; IsDeclined=$false; IsSuperseded=$false
                            KnowledgebaseArticles=@('1'); RequiresLicenseAgreementAcceptance=$false
                            Calls=[System.Collections.Generic.List[string]]::new() }
  $upd | Add-Member ScriptMethod GetUpdateApprovals { param($g)
      if ($g.Name -eq 'Pilot') { ,@([pscustomobject]@{CreationDate=[datetime]::UtcNow.AddDays(-10)}) } else { ,@() } }
  $upd | Add-Member ScriptMethod GetSummaryForComputerTargetGroup { param($g)
      [pscustomobject]@{InstalledCount=10;InstalledPendingRebootCount=0;NotInstalledCount=0;DownloadedCount=0;FailedCount=0} }
  $upd | Add-Member ScriptMethod Approve { param($a,$g) $this.Calls.Add($g.Name) }
  # $wsus: GetConfiguration / GetComputerTargetGroups / GetUpdateClassifications / GetUpdates as ScriptMethods
  Mock Get-WsusServer { $wsus }.GetNewClosure()
  $null = & '.\8-Approve-WsusRing.ps1' -WsusServer wsus01
  $upd.Calls -join ',' | Should -Be 'Workstations,Servers'
}
```

The prototype files were throwaway and are not committed; recreate from the above (the stub `.psm1`
is about 30 lines).

## Per-script feasibility

Only script 8 was run; the rest is assessed from reading the scripts.

| Script | Automatable in CI | Notes and manual remainder |
|---|---|---|
| 0 New-WsusAdminGroup | Yes, ActiveDirectory stub plus `Mock` | Real AD behaviour (OU, scope, replication) manual |
| 1 Install-WsusNode | Partly | `Install-WindowsFeature`, `New-NetFirewallRule` differ or are absent on client SKUs; stub or mock them. Real role install manual |
| 2 Set-WsusNodeConfig | Branch logic only | `IIS:\AppPools\WsusPool` has no drive without IIS, so wrap pool and binding calls in small functions you can mock (or mock `Set-ItemProperty`/`Get-Item` with `-ParameterFilter` on `-Path`). The `Web.config` edit can be tested on a temp file by overriding `$env:ProgramFiles`. `takeown`, `icacls`, cert binding, `Restart-Service` manual |
| 3 Configure-WsusUpstream | Yes (type stubs plus fake `$wsus`) | Sync polling loop (`GetSynchronizationStatus` until `NotProcessing`): fake must return it and `Start-Sleep` should be mocked. Real category and classification titles manual |
| 4 Configure-WsusReplica | Yes | Real downstream sync manual |
| 5 Invoke-WsusMaintenance | Mostly | `Invoke-WsusServerCleanup` stubbable. The `System.Data.SqlClient.SqlConnection` to WID is built via `New-Object`; mock `New-Object` with a `-ParameterFilter` on `TypeName` returning a fake with `Open/CreateCommand/Dispose`, or refactor into a function. Uses `Start-Transcript`, so point `-LogPath` at `$TestDrive`. Real SUSDB maintenance manual |
| 7 New-WsusClientGpo | Yes, GroupPolicy stub | Real GPO content, linking and client application manual |
| 8 Approve-WsusRing | Yes (prototype passes) | Real approval semantics manual |

## Must stay manual

- Whether the real `Microsoft.UpdateServices.Administration` API accepts the calls. A stub echoes
  what the script already assumes (signature drift, collection semantics, enum values, exception types).
- Actual WSUS sync, approvals, cleanup, WID/SUSDB maintenance.
- IIS app pool, binding and certificate behaviour; `Web.config` ACL changes.
- AD and GPO side effects, replication, client policy application.
- Windows feature installation (WSUS role).

## Unverified

- Whether a hosted runner can install the WSUS role and admin console (for example
  `Install-WindowsFeature UpdateServices-API`) to obtain the real assembly for contract tests. Not
  tested, and the runner readme does not list it. Worth a separate spike if #8 wants contract tests.
- No Microsoft Learn class page for `UpdateScope` was found (404 on the URLs tried), so the real
  constructors and enum values are unconfirmed from a primary source. The repo's own script usage was
  the only evidence for the stub surface.

## Suggested direction for #8

1. `tests/stubs/{UpdateServices,ActiveDirectory,GroupPolicy,WebAdministration}` stub modules with
   realistic parameter lists; `UpdateServices` also carries the `Add-Type` stub.
2. A `New-FakeWsusServer` test helper returning the ScriptMethod fake, parameterised by groups and updates.
3. Wrap IIS provider and SQL connection calls in tiny functions in the scripts (or mock `New-Object`).
4. CI on `windows-latest`; Pester 5.x is preinstalled (`Import-Module Pester -MinimumVersion 5.0`);
   run under `pwsh` and `powershell`.
