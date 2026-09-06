---
description: Source-first plugin packaging, direct lifecycle, confinement, minimal receipts, and dogfood.
globs:
  - plugins/**
  - registry.json
  - scripts/skalary/**
  - schemas/{plugin,registry,receipt,retirement,marketplace}/**/*.json
  - .github/.skalary/**
  - .github/plugin/marketplace.json
  - tests/{ConsumerInstallFixture.psm1,skalary/ConsumerInstall.Tests.ps1}
---

# Plugin Registry

`plugins/` is authoritative; `registry.json` and `.github/plugin/marketplace.json` are generated, and
`.github/` is the dogfood install target.

| Layer | Contract |
|---|---|
| `plugins/<name>/plugin.json` | Identity, semver, dependencies, `{src,dest}` files, optional status/scaffolds/eval reservations. |
| `registry.json` | Hash-pinned install catalog, scaffolds, bootstrap metadata, and permanent retirements. |
| `.github/.skalary/receipts/*.json` | Per-plugin installed identity: exactly `name`, `version`, `sourceIdentity`, and immutable `ref`. |
| `.github/**` | Dogfood installed output, converged from declared plugin files. |
| skill `scripts/**` | Generated canonical-script closures owned only by `Sync-PluginScripts.ps1`. |

Standard Copilot metadata stays in `SKILL.md`; packaging metadata stays in `plugin.json`. Evals never
install. Direct review Markdown is advisory and never registry/receipt state.

## Direct lifecycle

Dependency resolution is deterministic topological order with name dedupe, lexical ties, and pre-copy
cycle detection. One immutable SHA supplies each remote or local operation. Lifecycle destinations,
receipt paths, temporary paths, and existing parent components must remain physically confined to
`.github/`; traversal, rooted, linked/reparse, and `.github/workflows/**` paths fail before access.

Each receipt has exactly `name`, `version`, `sourceIdentity`, and immutable `ref`. GitHub identities
are canonical `github.com/<owner>/<repository>`; local identities are canonical-path SHA-256. Invalid,
mismatched, linked, or legacy-shaped receipts fail closed. Receipts provide installed/outdated status
and the authority to materialize the old manifest; they never track per-file ownership.

Install preflights the complete manifest set, refuses an unowned destination unless `-Force`, writes
the confined payload directly, verifies resulting bytes, and writes the receipt last. An unchanged rerun
does not mutate files. Update requires a matching source identity, derives both old and target manifests,
and replaces their path union under the same receipt authority, including local edits. It verifies target
bytes and old-path absence before advancing the receipt.

Remove materializes the exact receipt-pinned manifest and preflights every present target. An unforced
modified target reports all differences and prevents every deletion; missing paths already converge.
`-Force` deletes the complete confined set. Dependency refusal remains unless forced, and removal
deletes the receipt only after its result is verified.

`registry-retirements.json` is immutable append-only published refusal metadata. Registry generation
copies it to `retiredPlugins`; marketplace remains active-only; active and retired names are disjoint.
Install and update of a retired name fail with an explicit removal command. Retirement never mutates
an installed plugin.

## Dubious decisions

The lifecycle optimizes for one trusted operator rather than interruption safety. There is no mutation
lock, journal, backup, rollback, or recovery: direct payload writes can remain after an interruption.
Receipt-last ordering preserves the last known installed identity and exposes that partial state for a
convergent retry.

An explicit update overwrites local edits on paths authorized by its matching receipt. Per-file ownership
and modified-state tracking would avoid this, but are intentionally absent to keep receipts minimal.
Conversely, install protects an unowned collision and unforced remove protects every modified target.

## Integrity and deterministic catalogs

| Threat/invariant | Guard |
|---|---|
| Escape or links | Reject `..`, absolute/UNC/drive-relative/ADS destinations and reparse points in managed paths. |
| Tamper/collision | Verify staged registry hash; enforce registry-wide destination uniqueness and receipt ownership. |
| User edits | Update/remove skip modified files unless explicit `-Force`. |
| Bootstrap execution | Download scripts/catalog only; cloned plugin payload is copied, never executed. |
| Stable output | All catalog/README ordering uses explicit ordinal comparers; equality is ordinal. |

Registry payload hashes are SHA-256 over bytes produced by Git clean filters, so CRLF checkout
conversion cannot disagree with committed or clone bytes while uncommitted canonical source edits
remain buildable. Local-source installs stage those same clean-filtered bytes; remote installs clone
with LF checkout. Registry, marketplace, and README catalog drift checks compare generated content
deterministically.
The Czech-collation fixture proves `en-US`/`cs-CZ` byte identity and non-vacuous divergent IDs.

`PayloadScope.psm1` walks an explicit regular, non-link root allowlist, prunes `.git`, `.skalary`,
`.worktrees`, `bin`, `node_modules`, and `obj`, fails unreadable files/missing required roots, and rejects
an empty run. It replaces platform-dependent recursive enumeration.

## Distribution and dogfood

`Sync-Dogfood.ps1` is copy-only, collision-checked, idempotent, and supports `-WhatIf`; it writes exactly
declared payloads and does not prune the generator-owned marketplace. Runtime PowerShell lives once in
`scripts/skalary/`; `Sync-PluginScripts.ps1` copies manifest-declared entry points and `.ps1`/`.psm1`
closures, prunes stale generated copies, and patch-bumps every affected independently versioned plugin.
Callers that directly change declared non-script payloads pass their repo-relative paths through
`-ChangedPath`; the sync compares those canonical sources with dogfood and patch-bumps their owners
before registry generation.
Installed content references installed paths, never authoring paths. `docs/review-standards.md` is the
exact optional read-only exception for direct-workflow consumers. Autopilot is one self-contained
plugin (agent, skill, launchers, schemas, devcontainer, and templates), with no separate infra bootstrap.

Plugin-owned SI reader/write-guard and architecture-note scripts remain canonical in their plugins and
dogfood directly. CI/autopilot bundle `Write-RecentLearning.ps1` and scaffold its handoff without
depending on SI; SI owns the bounded reader and interactive source-edit workflow. npm aliases are
dogfood-only.

After a payload or manifest change, run in order:
`Sync-PluginScripts.ps1`, `Build-Registry.ps1`, `Build-Marketplace.ps1`, then `Sync-Dogfood.ps1`.
`Test-Registry.ps1` plus detect-only bundle, marketplace, and dogfood modes verify manifest mappings,
versions, hashes, and installed snapshots; never hand-edit generated bundles or catalogs.

## Runtime asset/scaffold grammar

Every runtime-read payload must be in some `files[]`. Because installation is confined to `.github/`,
first-use paths outside it require `scaffolds[]`. Literal entries name fixed paths and forbid a confine
helper; parameterized `<name>`/`**` entries require a shipped, called helper and may define closed values.
`owner` and `trigger` are documentation, not enforcement.

The scanner fails closed over four forms: installed `.github/{skills,agents,prompts}` paths;
skill-relative `./assets/...`; `docs`/`schemas`/`tools` scaffold paths; and forbidden source-tree
`./plugins`/`./scripts/skalary` reads. Static AST `Join-Path` forms follow the same rules; dynamic
supported-root composition fails. Fenced examples, comments, and final bare placeholders are excluded;
an unterminated fence errors. Verified `$PSScriptRoot`/asset-root sidecars are exempt only when installed
or bundled. The bootstrap-owned `scripts/skalary/registry.json` fallback remains valid.

Self-improvement declares no state scaffold. Its installed payload is the stateless `/pfb` comparison,
the bounded recent-learning reader, the direct `/si` instructions, and the physical Markdown
write-scope guard.
Architecture notes may read a consumer-owned optional `schemas/architecture` legacy-contract directory,
but no plugin writer owns or scaffolds that path.

## Consumer and size evidence

The foreign-consumer fixture installs every active manifest into one poisoned empty Git repo. Its
manifest-derived oracle checks installed hashes, receipts, dependencies, confinement, and registry
mappings independently. Runtime-reference closure composes that inventory with bundle drift; smoke
derives one deterministic installed behavior per plugin; first-use lifecycle proves starter content,
safe rerun, modified-target preservation, bounded output, hostile refusal, and retry. Distribution
drift composes bundle, registry, marketplace, and dogfood gates without adding a schema or hosted proof.
This process-heavy inventory is an explicit installer diagnostic, not routine validation.

`Test-SkillSize.ps1` enforces `-MaxBytes 12000` over source and dogfood `SKILL.md`; move detail to
installed assets.

## Copilot CLI and eval seams

Marketplace entries share `plugin.json`, use `source: plugins/<name>` and `strict: false`, and install
as `<name>@skalary`; direct path install is deprecated. `Find-Plugin.ps1`, `Get-Plugin.ps1`, and remove
dependency checks accept `-RegistryPath`, falling back to bootstrap-owned
`scripts/skalary/registry.json`; absence of both reports “not a skalary-managed repo”.

Manifest `evals.status/lastRun`, registry `evals.status`, and receipt `evalStatus` remain reserved and
non-authoritative. The report-only harness writes none of them; see
[plugin-evals.design.md](plugin-evals.design.md). Operator-guide and review-standards references never
authorize installer mutation.
