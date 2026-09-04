---
description: Development and tooling rules for this repo — terminal commands, agent workflows, and conventions that affect CI/automation.
globs:
  - .github/**
  - .vscode/**
---

# Dev Rules

## Terminal Commands

- **Keep operator choices equivalent across hosts.** Define one ordered option list with the same
  labels and context in VS Code and Copilot CLI. Every option includes any recommendation/default,
  `effort: <1-10>`, and `complexity: <1-10>`. VS Code uses `vscode_askQuestions`; Copilot CLI shows
  the same options as a numbered list and accepts the number or exact label. Do not add a picker
  abstraction. `/cr` treats a missing host path, context, or score as a finding.

- **Never start a PowerShell command with `&` or wrap `.ps1` scripts with `powershell -File`** — both break VS Code Copilot agent auto-approval (it won't approve commands starting with `&` or `powershell`). The terminal is already PowerShell; invoke everything directly:
  - `dotnet build` not `& dotnet build`
  - `.github/agents/scripts/Get-ReviewScope.ps1 -Mode uncommitted` not `powershell -File .github/agents/scripts/Get-ReviewScope.ps1 -Mode uncommitted`
  - If calling a variable-path executable, assign it first then call by name.

- **Installed skill scripts use stable direct paths.** Invoke `.github/skills/<skill>/scripts/<name>.ps1`
  directly with bound arguments; do not wrap it with `pwsh -File`. Exact read-only and focused paths
  may be pre-approved. Install, update, remove, set, build, sync, repair, and other mutations remain
  explicit per invocation.

- **Never use `git add -A`, `git add .`, or `git add --all`** — stage only files the agent directly created or modified. Blanket staging risks committing unrelated or temporary files:
  - `git add src/Foo.cs src/Bar.cs` not `git add -A`

## Code Formatting

- **Always use the project formatter — never format code by manual edits.** In .NET repos with `.editorconfig`, run `dotnet format` before committing instead of reformatting code inline.
  - The formatter applies all `.editorconfig` rules consistently.
  - Do not attempt to fix formatting warnings by editing individual lines.

## Validation and test gates

- **Validation logic must live in committed scripts, not markdown orchestration text.** For plan workflows, run `scripts/skalary/Test-Plan.ps1` and `scripts/validate.ps1 -Path <affected-path>`; do not add ad-hoc regex checks to skill/agent markdown.
- **Routine validation is explicitly focused and local.** Use `Run-UnitTests.ps1 -TestPath`, `Test-Evals.ps1 -Plugin`, or `validate.ps1 -Path`. Never widen or retry. The direct `-FullRepository` switch is operator-only; no skill or package alias invokes it. Repository-owned GitHub workflows are prohibited.
- **Pester is required for focused unit and typed `test:` evidence.** Keep the pinned Pester install step in `.devcontainer/autopilot/Dockerfile`. `Run-UnitTests.ps1` fails rather than skips when it cannot test — absent Pester (exit 2), zero discovered tests (exit 3), a test file that never loaded (exit 4), or focused timeout (exit 13).
- **Keep payload ownership explicit.** Shared workflow scripts are edited only under
  `scripts/skalary/` and regenerated with `Sync-PluginScripts.ps1`; plugin-owned executables and
  schemas are edited only under their owning `plugins/<name>/{scripts,schemas}/` roots. After either
  kind changes, synchronize dogfood, manifest mappings, plugin versions, marketplace, and registry
  in the same step. Do not hand-edit generated bundle or catalog copies.
- **Structural evals are a separate deterministic path.** Plugin Tier-1 cases live under
  `plugins/<name>/evals/*.Tests.ps1` and run through `Test-Evals.ps1 -Plugin <name>`; adding one does not add a
  `validate.ps1` gate. A plan that cites one as typed `test:` evidence still executes that named
  Pester case and blocks its crosscheck on failure. Always-on cross-surface invariants belong in
  `tests/` and the existing unit suite.
- **Do not maintain suite tiers, runtime baselines, coverage inventories, or budget clocks.** They
  turned test execution into a subsystem without making routine work cheaper. Keep focused commands
  below 30 seconds by selecting only affected files or plugins; report a slow command rather than
  introducing measurement state.

## Git History

- **Never use `git push --force`, `git push --force-with-lease`, or `git commit --amend` on pushed commits.** If a commit needs fixing, create a follow-up commit instead. Force-pushing rewrites shared history and can disrupt CI, other collaborators, and PR references.
