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

For the human workflow from planning through implementation and review, start with the
[operator guide](docs/operator-guide/README.md).

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

- `code-review` and `design-review`: require PowerShell 7.6+ before reviewer dispatch.
- `process-pr-comments`: requires GitHub CLI (`gh`) installed and authenticated for the current user (`gh auth login`), because the plugin resolves auth exclusively via `gh auth token`.

## Security Note (`irm | iex`)

`irm ... | iex` executes downloaded content in-process. This repository mitigates risk by pinning to immutable refs and keeping bootstrap behavior minimal, but you should still inspect the script before execution and use only trusted refs.

## Plugin Catalog

Generated from `registry.json` by `scripts/skalary/Build-Registry.ps1`.

<!-- BEGIN SKALARY PLUGIN CATALOG -->
| Plugin | Version | Status | Dependencies | Files | Description |
|--------|---------|--------|--------------|-------|-------------|
| `architecture-notes` | 1.0.10 | partial | — | 16 | Architecture notes toolkit — skill-first authoring of interface-level architectural contracts and ADRs, with a parallel docs/architecture-notes tier. /can and /uan are thin prompt wrappers over the skill. |
| `autopilot` | 1.3.16 | partial | code-review, create-implementation-plan | 38 | Self-contained direct-workflow autonomous plan executor. |
| `code-review` | 1.0.80 | stable | — | 9 | Risk-selected code review with direct advisory Markdown. |
| `continue-implementation` | 1.0.117 | stable | autopilot, code-review, create-implementation-plan | 9 | Direct plan implementation workflow with Git criteria protection. |
| `create-implementation-plan` | 1.0.100 | stable | design-review | 27 | Direct implementation and epic plan creation. |
| `design-notes` | 1.1.4 | stable | — | 7 | Design notes toolkit — the design-notes skill bootstraps the docs/design-notes scaffold from bundled templates and creates/updates notes; /design-notes, /cdn, and /udn are thin prompt shortcuts over it. |
| `design-review` | 1.0.79 | stable | — | 8 | Risk-selected design review with direct advisory Markdown. |
| `plugin-manager` | 1.0.24 | stable | — | 15 | Install, uninstall, list, and update skalary plugins through user-invocable skills that wrap the skalary PowerShell scripts. |
| `process-pr-comments` | 1.0.2 | stable | — | 2 | Process PR comments skill for classifying, fixing, and replying to review feedback. |
| `self-improvement` | 1.0.82 | stable | create-implementation-plan | 12 | Stateless post-plan feedback and bounded local self-improvement from the recent-learning handoff. |
| `work-hierarchy-sync` | 1.0.25 | stable | — | 4 | Synchronize local implementation epics and plans to a deterministic GitHub issue hierarchy with dry-run review, explicit apply confirmation, stable mappings, and conflict refusal. |
<!-- END SKALARY PLUGIN CATALOG -->
