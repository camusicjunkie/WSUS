## Agent skills

### Issue tracker

Issues live in GitHub Issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` at the repo root, plus `docs/adr/` once the first decision is recorded. See `docs/agents/domain.md`.

### Verify

`./build.ps1 -Task All` is the one check, same as CI (PSScriptAnalyzer, then Pester, on 5.1 and 7). A pre-push hook runs it: enable once per clone with `git config core.hooksPath .githooks`. After a red CI run, read `gh run view --log-failed`.

### Navigation

- Adding or changing a function, or writing tests: read `tests/README.md` first (layout, shared helpers, fakes).
- Mocking the WSUS `UpdateServices` API in Pester: read `docs/research/pester-mock-updateservices.md`.
- Reviewing a diff: `CODING_STANDARDS.md`.
