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

## Git History

- **Never use `git push --force`, `git push --force-with-lease`, or `git commit --amend` on pushed commits.** If a commit needs fixing, create a follow-up commit instead. Force-pushing rewrites shared history and can disrupt CI, other collaborators, and PR references.
