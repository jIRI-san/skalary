---
description: Development and tooling rules for this repo — terminal commands, agent workflows, and conventions that affect CI/automation.
globs:
  - .github/**
  - .vscode/**
---

# Dev Rules

## Terminal Commands

- **Never start a PowerShell command with `&` or wrap `.ps1` scripts with `powershell -File`** — both break VS Code Copilot agent auto-approval (it won't approve commands starting with `&` or `powershell`). The terminal is already PowerShell; invoke everything directly:
  - `dotnet build` not `& dotnet build`
  - `.github/agents/scripts/Get-ReviewScope.ps1 -Mode uncommitted` not `powershell -File .github/agents/scripts/Get-ReviewScope.ps1 -Mode uncommitted`
  - If calling a variable-path executable, assign it first then call by name.

- **Never use `git add -A`, `git add .`, or `git add --all`** — stage only files the agent directly created or modified. Blanket staging risks committing unrelated or temporary files:
  - `git add src/Foo.cs src/Bar.cs` not `git add -A`

## Code Formatting

- **Always use the project formatter — never format code by manual edits.** In .NET repos with `.editorconfig`, run `dotnet format` before committing instead of reformatting code inline.
  - The formatter applies all `.editorconfig` rules consistently.
  - Do not attempt to fix formatting warnings by editing individual lines.

## Validation and test gates

- **Validation logic must live in committed scripts, not markdown orchestration text.** For plan workflows, run `scripts/skalary/Test-Plan.ps1` (directly or via `npm run validate-plan`) and `scripts/validate.ps1`; do not add ad-hoc regex checks to skill/agent markdown.
- **Pester is required for `test:unit` and typed `test:` evidence everywhere, not only in container-autopilot.** Keep the pinned Pester install step in `.devcontainer/autopilot/Dockerfile`. `Run-UnitTests.ps1` fails rather than skips when it cannot test — absent Pester (exit 2), zero discovered tests (exit 3), or a test file that never loaded (exit 4) — because it is the `test:unit` leg and the `test:` evidence executor, so a skip would be a green run that asserted nothing. The failure message names `Install-Module Pester -Scope CurrentUser -Force`, which is what makes failing loudly acceptable off-container.
- **Keep payload ownership explicit.** Shared workflow scripts are edited only under
  `scripts/skalary/` and regenerated with `Sync-PluginScripts.ps1`; plugin-owned executables and
  schemas are edited only under their owning `plugins/<name>/{scripts,schemas}/` roots. After either
  kind changes, synchronize dogfood, manifest mappings, plugin versions, marketplace, and registry
  in the same step. Do not hand-edit generated bundle or catalog copies.
- **Structural evals are a separate deterministic path.** Plugin Tier-1 cases live under
  `plugins/<name>/evals/*.Tests.ps1` and run through `npm run eval`; adding one does not add a
  `validate.ps1` gate. A plan that cites one as typed `test:` evidence still executes that named
  Pester case and blocks its crosscheck on failure. Always-on cross-surface invariants belong in
  `tests/` and the existing unit suite.
- **Runtime rows are measured, never relabeled.** Ordinary `npm test` rejects the current
  platform's stale tracked-input fingerprint. Refresh only through `Measure-SuiteRuntime.ps1`,
  which authorizes one stale measurement run, still enforces the ceiling, and emits a fingerprinted
  candidate afterward. Do not copy an old elapsed figure onto a new fingerprint. Complete all
  fingerprinted edits before final cross-platform measurement; only the generated runtime/profile
  JSON and `testResults.xml` may change afterward.

## Git History

- **Never use `git push --force`, `git push --force-with-lease`, or `git commit --amend` on pushed commits.** If a commit needs fixing, create a follow-up commit instead. Force-pushing rewrites shared history and can disrupt CI, other collaborators, and PR references.
