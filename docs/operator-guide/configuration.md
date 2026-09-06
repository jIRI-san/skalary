# Configuration

## Purpose

`/skalary-config` is a read-only facade over existing Skalary configuration owners. It reports
effective values, precedence, validation availability, and a bounded preview; it is not a central
configuration store and does not replace direct subsystem commands.

## Start with discovery

Run the installed command with one supported category:

```powershell
.github/skills/skalary-config/scripts/Read-SkalaryConfig.ps1 -Action show -Category autopilot -RepoRoot .
```

The supported categories are `autopilot`, `models-reviews`, `local-review-standards`,
`terminal-approvals`, `evals`, `design-architecture`, `plugin-distribution`, and
`repository-toolchain`. `show`, `validate`, `diff`, and `preview` do not write files. Missing
source-only categories report unavailable in an installed consumer rather than guessing.

## Routine changes

Only `autopilot`, `local-review-standards`, and `models-reviews` support facade mutations. Create a
preview first, then apply the exact preview digest:

```powershell
.github/skills/skalary-config/scripts/Set-SkalaryConfig.ps1 -Action preview -Category autopilot -ChangesJson '{"model":"primary-model-low"}' -RepoRoot .
.github/skills/skalary-config/scripts/Set-SkalaryConfig.ps1 -Action apply -Category autopilot -ChangesJson '{"model":"primary-model-low"}' -ExpectedDigest '<preview-digest>' -ProposedAction edit -RepoRoot .
```

`cancel` makes no change. `bootstrap` previews only the selected missing file; apply it with
`-Action apply -ProposedAction bootstrap` and its preview digest. `reset -Key` restores a supported key
from its shipped default. The preview digest rejects stale inputs. Changes to executable settings require
`-AcknowledgeExecutableSettings`; `long_context` requires
`-AcknowledgeLongContextCost`.

Never give the skill credential values or paths. Autopilot setup guidance uses a separate shell;
after setup, run:

```powershell
.github/skills/skalary-config/scripts/Test-AutopilotAuth.ps1 -RepoRoot .
```

## Direct owners remain available

The facade does not own advanced maintainer policy or generated outputs. Use these existing commands
directly when they match the task:

| Surface | Direct owner |
|---|---|
| Terminal approvals | `scripts/skalary/Set-ScriptApproval.ps1 -Name <installed-plugin> -RepoRoot .` |
| Eval credentials and Waza runs | `scripts/skalary/Resolve-EvalToken.ps1 -RepoRoot .` and `scripts/skalary/Invoke-WazaEvals.ps1 -Plugin <plugin>` |
| Design and architecture scaffolds | `.github/skills/design-notes/scripts/Initialize-DesignNotes.ps1 -RepoRoot .` and `.github/skills/architecture-notes/scripts/Copy-ArchScaffold.ps1 -TargetRoot .` |
| Plugin distribution | `scripts/skalary/Sync-PluginScripts.ps1`, `Build-Registry.ps1`, `Build-Marketplace.ps1`, and `Sync-Dogfood.ps1` |

Plugin manifests, eval specifications and pins, model allowlists, toolchain policy, registry,
marketplace, README catalog, and dogfood files remain source-owned or generator-owned. Removing
`skalary-config` removes only this facade; those direct configuration paths continue to work.
