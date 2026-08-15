# skalary

Plugin-based GitHub Copilot customizations for prompts, skills, and agents.

## Installation

Bootstrap scripts and registry into a target repository:

```powershell
irm https://raw.githubusercontent.com/jIRI-san/skalary/main/scripts/skalary/bootstrap.ps1 | iex
```

`bootstrap.ps1` downloads `scripts/skalary/*.ps1` and `registry.json` into `scripts/skalary/`, creates `.github/.skalary/`, and does not execute plugin payload.

### Review Guidance

Before running the one-liner:
1. Review `scripts/skalary/bootstrap.ps1` at the ref you intend to install.
2. Confirm the repo/ref pair is the source you trust.
3. Pin an immutable SHA instead of `main` if you need a reproducible install.

## Usage

Install a plugin (dependencies are resolved and installed automatically):

```powershell
pwsh -NoProfile -File scripts/skalary/Install-Plugin.ps1 -Name ci
```

Update an installed plugin to the registry version:

```powershell
pwsh -NoProfile -File scripts/skalary/Update-Plugin.ps1 -Name ci
```

Remove a plugin:

```powershell
pwsh -NoProfile -File scripts/skalary/Remove-Plugin.ps1 -Name ci
```

List registry plugins with install/modified/outdated state:

```powershell
pwsh -NoProfile -File scripts/skalary/Get-Plugin.ps1
pwsh -NoProfile -File scripts/skalary/Get-Plugin.ps1 -Installed
```

Search plugins by name/description/tags:

```powershell
pwsh -NoProfile -File scripts/skalary/Find-Plugin.ps1 -Query review
```

### Plugin-specific prerequisites

- `process-pr-comments`: requires GitHub CLI (`gh`) installed and authenticated for the current user (`gh auth login`), because the plugin resolves auth exclusively via `gh auth token`.

## Security Note (`irm | iex`)

`irm ... | iex` executes downloaded content in-process. This repository mitigates risk by pinning to immutable refs and keeping bootstrap behavior minimal, but you should still inspect the script before execution and use only trusted refs.

## Plugin Catalog

Generated from `registry.json` by `scripts/skalary/Build-Registry.ps1`.

<!-- BEGIN SKALARY PLUGIN CATALOG -->
| Plugin | Version | Status | Dependencies | Files | Description |
|--------|---------|--------|--------------|-------|-------------|
| `architecture-notes` | 1.0.5 | partial | — | 17 | Architecture notes toolkit — skill-first authoring of interface-level architectural contracts and ADRs, with a parallel docs/architecture-notes tier. /can and /uan are thin prompt wrappers over the skill. |
| `architecture-tests` | 1.0.20 | partial | — | 14 | Architecture-tests runner — executes architecture-contract checks via deterministic (NetArchTest, ts-arch; dependency-cruiser reserved) or advisory semantic-eval adapters and emits freshness-bound receipts (parent-commit + sources hash) whose verdict maps to a maturity-aware gate. Companion to the architecture-notes plugin. |
| `autopilot` | 1.2.3 | partial | — | 20 | Self-contained autopilot plugin payload for agent, skill, scripts, schemas, and devcontainer. |
| `code-review` | 1.0.7 | stable | — | 25 | Code review orchestrator with model-agnostic concern reviewers and a single review-scope emitter. |
| `continue-implementation` | 1.0.29 | stable | autopilot, code-review | 14 | Code implementation workflow skill with autonomous execution guidance. |
| `create-implementation-plan` | 1.0.29 | stable | design-review | 26 | Implementation plan generation skill for coding workflows. |
| `design-notes` | 1.1.2 | stable | — | 6 | Design notes toolkit — the design-notes skill bootstraps the docs/design-notes scaffold from bundled templates and creates/updates notes; /design-notes, /cdn, and /udn are thin prompt shortcuts over it. |
| `design-review` | 1.0.6 | stable | — | 24 | Design review orchestrator with specialist model agents. |
| `plugin-manager` | 1.0.4 | stable | — | 15 | Install, uninstall, list, and update skalary plugins through user-invocable skills that wrap the skalary PowerShell scripts. |
| `process-pr-comments` | 1.0.0 | stable | — | 2 | Process PR comments skill for classifying, fixing, and replying to review feedback. |
| `self-improvement` | 1.0.22 | stable | create-implementation-plan | 12 | Self-improvement loop — /pfb compares delivered work against the plan's captured intent and records the operator's verdict; /si harvests the review ledger, plan learnings, and recorded feedback into ranked improvements to the customizations themselves. |
<!-- END SKALARY PLUGIN CATALOG -->
