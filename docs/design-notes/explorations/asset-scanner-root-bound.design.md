---
description: Deferred exploration — the asset-bootstrap scanner enforces only roots that some plugin already declares, so an undeclared root is invisible rather than a violation. Load before changing the Sync-PluginScripts asset grammar or the scaffolds[] contract.
globs:
  - scripts/skalary/Sync-PluginScripts.ps1
  - schemas/plugin/plugin.schema.json
  - schemas/registry/registry.schema.json
---

# Asset Scanner Root Bound [RESOLVED]

The bound was removed by plan `34088e` on 2026-08-23. This note retains the prior analysis and resolution.

## The bound

`Sync-PluginScripts.ps1` arm 3 matches a reference only when its root appears in `$scaffoldRoots` — a set built *from the `scaffolds[]` declarations themselves*. Enforcement therefore applies exactly where compliance already exists.

| Root | Declared by | Checked |
|---|---|---|
| `docs/implementation-plans/` | `create-implementation-plan` | yes |
| `docs/feedback/` | `self-improvement` | yes |
| `docs/design-notes/` | nobody | **no** |
| `docs/architecture-notes/` | `architecture-notes` | yes |

## The live gap

`plugins/design-notes/skills/design-notes/SKILL.md` reads `docs/design-notes/.design-notes.md` at runtime. It is outside `.github/`, so the installer cannot write it; it is in no `files[]` and no `scaffolds[]`. In a consumer repo without that file the skill degrades silently — the exact outcome RISK-9 names — and the drift gate reports clean. `architecture-notes` has the same shape against `docs/architecture-notes/`.

Neither is a *new* regression: both predate the scanner. The point is that the gate built to catch this class cannot see them.

## Why it was left

Widening was implemented during `b0c0d3` phase 10 and reverted in the same phase: rooting the closed set in the grammar (`docs|schemas|tools`) immediately surfaced a batch of undeclared references, each needing a `scaffolds[]` entry or an explicit exclusion. That is real work with a real risk of over-declaring paths nobody actually scaffolds, and it was out of scope for the step that found it.

The operator's call was that a narrower gate with honest documentation beats a wider gate rushed in at the end of a plan.

## Resolution

`Sync-PluginScripts.ps1` now roots scaffold references directly in the closed `docs|schemas|tools`
grammar. Every concrete reference must match a declaration even when no plugin previously declared
that root. PowerShell comments are excluded by syntax; literal `Join-Path` targets are reconstructed,
and relative `$PSScriptRoot` or `$AssetRoot` sidecars are excluded from scaffold matching only when
their installed destination is declared or belongs to a verified bundle closure. The
foreign-consumer closure evidence pairs this static result with the production-installed manifest
inventory. Scaffold owner execution remains covered separately by
`test:ConsumerInstall.FirstUseScaffoldLifecycle`.
