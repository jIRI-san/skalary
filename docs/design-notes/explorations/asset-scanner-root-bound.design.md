---
description: Deferred exploration — the asset-bootstrap scanner enforces only roots that some plugin already declares, so an undeclared root is invisible rather than a violation. Load before changing the Sync-PluginScripts asset grammar or the scaffolds[] contract.
globs:
  - scripts/skalary/Sync-PluginScripts.ps1
  - schemas/plugin/plugin.schema.json
  - schemas/registry/registry.schema.json
---

# Asset Scanner Root Bound

Operator decision 2026-08-01, from the `b0c0d3` `/pfb` round: **leave the bound, correct the wording.** The design note now states the limitation plainly instead of framing it as a property. This note holds the analysis for whoever picks it up.

## The bound

`Sync-PluginScripts.ps1` arm 3 matches a reference only when its root appears in `$scaffoldRoots` — a set built *from the `scaffolds[]` declarations themselves*. Enforcement therefore applies exactly where compliance already exists.

| Root | Declared by | Checked |
|---|---|---|
| `docs/review-ledger/` | `continue-implementation` | yes |
| `docs/implementation-plans/` | `create-implementation-plan` | yes |
| `docs/feedback/` | `self-improvement` | yes |
| `docs/design-notes/` | nobody | **no** |
| `docs/architecture-notes/` | nobody | **no** |

## The live gap

`plugins/design-notes/skills/design-notes/SKILL.md` reads `docs/design-notes/.design-notes.md` at runtime. It is outside `.github/`, so the installer cannot write it; it is in no `files[]` and no `scaffolds[]`. In a consumer repo without that file the skill degrades silently — the exact outcome RISK-9 names — and the drift gate reports clean. `architecture-notes` has the same shape against `docs/architecture-notes/`.

Neither is a *new* regression: both predate the scanner. The point is that the gate built to catch this class cannot see them.

## Why it was left

Widening was implemented during `b0c0d3` phase 10 and reverted in the same phase: rooting the closed set in the grammar (`docs|schemas|tools`) immediately surfaced a batch of undeclared references, each needing a `scaffolds[]` entry or an explicit exclusion. That is real work with a real risk of over-declaring paths nobody actually scaffolds, and it was out of scope for the step that found it.

The operator's call was that a narrower gate with honest documentation beats a wider gate rushed in at the end of a plan.

## If picked up

1. Root the closed set in the grammar, not the declared set.
2. Enumerate what that surfaces before deciding — the count drives whether this is an afternoon or a phase.
3. For each: a `scaffolds[]` entry with a real first-use writer, or an exclusion with a stated reason. An entry whose declared `owner` does not actually create the path is worse than no entry — that failure mode already occurred once, when `Add-LedgerEntry` declared a first-use write it did not perform.
4. Keep the `owner`-truthfulness gap in mind: nothing currently asserts a declared `owner` performs the write it claims.
