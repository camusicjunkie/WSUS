# Coding standards

Read during review. PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`) already enforces 5.1 syntax and cmdlet compatibility, and rejects suppressions without a justification; this file holds only what a linter cannot judge.

## Duplication

- Two public functions whose bodies differ only by a value (Enable/Disable-style pairs) share one private helper that takes that value, as `Set-WsusApprovalRuleState` does. Flag a second copy of a body.
- A check that several functions repeat (role, elevation, prerequisite) lives in one `Assert-*` helper.
- A shared helper keeps its own tests; the public tests assert only that the function calls it (see `tests/README.md`, "Shared private helpers").

## Compatibility

- Code must run on Windows PowerShell 5.1 and PowerShell 7. Flag any 7-only operator, cmdlet or parameter, even where the analyzer is silent.

## Suppressions

- Suppress inline with `SuppressMessageAttribute` on the smallest scope (function, not file), with a `Justification` that names the reason in the module's terms. A new blanket exclusion in the settings file is a rejection.

## Surrounding style

- New code matches its neighbours: one function per file, file name = function name, comment-based help on every public function, a CHANGELOG `Unreleased` line for every user-visible change.
