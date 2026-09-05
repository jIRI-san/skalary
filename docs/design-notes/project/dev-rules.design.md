---
description: Repository terminal, staging, formatting, validation, and history rules.
globs:
  - .github/**
  - .vscode/**
---

# Dev Rules

## Terminal and interaction

- Complex predefined choices are host-equivalent ordered lists with context, example, benefits,
  pros/cons, recommendation/default, `effort: <1-10>`, `complexity: <1-10>`, and Mermaid only when
  structure matters. VS Code uses `vscode_askQuestions`; CLI accepts number or exact label. Free-form
  input asks one focused question; trivial yes/no stays concise. Do not add a picker abstraction.
- Never start PowerShell commands with `&` or wrap scripts in `powershell -File`/`pwsh -File`; both
  break prefix auto-approval. Invoke `dotnet build` and
  `.github/skills/<skill>/scripts/<name>.ps1 -RepoRoot .` directly. Assign variable executable paths
  before calling them. Mutating commands remain explicit.
- Never use `git add -A`, `git add .`, or `git add --all`; stage only directly changed paths.

## Formatting and validation

- Use the project formatter; in `.NET` repositories with `.editorconfig`, run `dotnet format` rather
  than manually reformatting warnings.
- Validation logic belongs in committed scripts. Plan work uses `Test-Plan.ps1` and focused
  `validate.ps1 -Path`; do not encode ad-hoc validators in workflow Markdown.
- Routine commands are focused and local and never widen/retry. Broad/premium routes are explicit
  operator actions; repository-owned GitHub workflows remain prohibited.
- Shared workflow scripts are edited only in `scripts/skalary/`; plugin-owned executables/schemas only
  in their plugin. Distribution completion is defined by
  [plugin-registry.design.md](../architecture/plugin-registry.design.md), not duplicated here.
- Pester failure codes, command timeout, and no-suite-policy rules belong to
  [ci-gates.design.md](ci-gates.design.md). Structural eval placement and typed evidence belong to
  [plugin-evals.design.md](../architecture/plugin-evals.design.md).

## Git history

Never force-push or amend pushed commits. Add a follow-up commit instead.
