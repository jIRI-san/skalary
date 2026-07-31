# Decision: asset bootstrap on install

## Problem

A skill or agent that reads a file which only exists in this repo's working tree works perfectly when dogfooded and fails in every consumer repo. The failure is quiet: the agent reads nothing, proceeds without the guide/map/template, and produces degraded output rather than an error.

`Sync-PluginScripts.ps1` already solves exactly this — for `.ps1`/`.psm1` only. It scans payload markdown and scripts for `.github/skills/<skill>/scripts/<name>.ps?1` references, resolves each against `scripts/skalary/`, follows the dot-source/module closure, copies them into the plugin bundle, and registers them in `files[]`. Markdown assets (guides, templates, maps, schemas) have no equivalent gate.

This plan adds many such assets — `dispatch-guide.md`, `concern-ledger-map.md`, `intent-template.md`, `harvest-guide.md`, the new plan template — which makes the gap load-bearing rather than theoretical.

## Contract

1. **Installed by default.** Every file a payload (`SKILL.md`, `*.agent.md`, `*.prompt.md`, bundled script) reads at runtime must appear in that plugin's `plugin.json` `files[]` with a `dest` under `.github/`. Installation materializes it; the registry hashes it; install/remove stay transactional and integrity-checked.

2. **Scaffolded when installation cannot reach it.** `ARCH-Install-Confinement` confines installer writes to `.github/`, and there is no post-install hook. Runtime paths outside `.github/` therefore cannot be installed and must instead be scaffolded on first use by the owning skill — the model `/design-notes init` already uses for `docs/design-notes/`. The approved set is **machine-readable**, declared as a `scaffolds[]` array in `plugin.json`, and must also **reach `registry.json`**, because consumer installs resolve against the registry rather than the source tree. That means extending both the registry schema (which currently sets `additionalProperties: false` on plugin entries) and `Build-Registry.ps1`; otherwise the declarations never travel to the consumers who need them.

   | Path | Owner | Trigger | Mode |
   |---|---|---|---|
   | `docs/review-ledger/<category>.md` | `/ci` harvest, `/si` | first harvest | parameterized — category is a closed enum from the concern→ledger map, never free text |
   | `docs/implementation-plans/<plan>/assets/**` | `New-Plan.ps1` | plan scaffold | parameterized — already sanitized + canonicalize-then-confined today |
   | `/pfb` feedback queue | `/pfb` | first queued marker | fixed literal |

   Two modes, both explicit: a **literal** entry names a fixed path with no variable components; a **parameterized** entry is flagged as such and must route through a canonicalize-then-confine helper with a closed value domain. A blanket "fixed literal only" rule would fail the two unavoidable parameterized rows above, so the schema and tests model both modes distinctly.

3. **Gated.** The `Sync-PluginScripts.ps1` reference scanner is extended from `.ps1`-only to every referenced asset, under a **closed grammar**: installed-path literals (`.github/skills/<skill>/...`) plus relative `./assets/<file>` references inside runtime payloads. Fenced code blocks, prose links in design notes, and dynamically composed reads (`Join-Path './assets' $name`) are out of grammar — the first two are excluded, the third is unsupported and must not appear in payloads. An asset that is referenced but neither declared in `files[]` nor matched by a `scaffolds[]` entry fails the `-WhatIf` drift gate in `scripts/validate.ps1`. Tests cover false positives (fenced examples), false negatives (dynamic references), and cross-plugin references.

## Why not a post-install hook

A hook would let installation write outside `.github/`, which is precisely what `ARCH-Install-Confinement` exists to prevent — arbitrary code execution and unbounded write scope at install time. First-use scaffolding keeps the confinement intact and keeps the write inside a skill the operator explicitly invoked.
