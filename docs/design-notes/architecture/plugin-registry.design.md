---
description: Source-first plugin packaging, generated catalogs, transactional lifecycle, confinement, receipts, and dogfood.
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
| `.github/.skalary/receipts/*.json` | Per-plugin source/ref/version and file hash/outcome ownership; avoids a shared lock-file conflict. |
| `.github/.skalary/retirements/*.json` | Versioned preview/apply/result state; never deletion authority by itself. |
| `.github/**` | Dogfood installed output, converged from declared plugin files. |
| skill `scripts/**` | Generated canonical-script closures owned only by `Sync-PluginScripts.ps1`. |

Standard Copilot metadata stays in `SKILL.md`; packaging metadata stays in `plugin.json`. Evals never
install. Direct review Markdown is advisory and never registry/receipt state.

## Install, update, remove, and retirement

Dependency resolution is deterministic topological order with name dedupe, lexical ties, and
pre-copy cycle detection. One immutable SHA supplies each remote or local operation. Apply stages
under `.github/.skalary/tmp/`, verifies hashes, backs up, atomically moves, then writes the receipt;
failure restores backups and writes no receipt.

Receipt `sourceIdentity` is version 1: GitHub stores canonical `github.com/<owner>/<repository>`, local
sources store a canonical-path SHA-256, and immutable `ref` is separate. Ambiguous legacy source labels
fail closed for retirement.

Update reconciles the old receipt against the new manifest under the mutation lock. A new absent,
unowned destination installs without `-Force`; an existing unowned or foreign-owned path remains
protected. Retired destinations are removed only when still equal to their receipt hash (or explicitly
forced); modified residue remains recorded as `skipped-modified` in a degraded receipt. Payload and
receipt moves share a rollback transaction and converge idempotently.

Explicit remove and automatic retirement share `Invoke-PluginRemovalPrimitive`: serialize through
`mutation.lock`; confine payload/state/journal/backup paths and parent chains; write a validated journal
before mutation; and require plugin/source/transaction identity, receipt hashes, backup paths, and
backup hashes to match for recovery. Modified files remain with original expected ownership as
`degraded`/`skipped-modified`; only explicit `Remove-Plugin -Force` deletes them.

`registry-retirements.json` is immutable append-only tombstone authority. Build copies it to
`retiredPlugins`; marketplace remains active-only; active/retired names are disjoint. History checks
take explicit current/historical files without Git; missing required history errors. State paths use
the plugin-name grammar plus `.github` confinement and closed embedded schema; affected paths are never
truncated, only display summaries are.

Install/update reconcile after source verification and before active lookup or already-current return.
First observation writes a complete preview; the next exact automatic operation applies it. Stale
automatic input refreshes without deletion; explicit apply rejects missing/stale preview. Under lock,
apply rederives the tombstone/source/ref/version intersection with current receipt ownership.
`failed` returns to preview only after exact journal and observed-content recovery.

One invocation emits at most one `RETIREMENT:` JSON record: exit `20` for a direct retired target,
`21` for blocking failure. Terminal remedy replay is read-only, never hashes content, handles at most
eight plugins/64 paths, and advances global and per-state cursors. Recovery covers partial journals and
post-commit/pre-terminal crashes. Terminal state retains the old ref for manual restore, but tombstones
still block fresh install and restored receipts remain explicit-removal authority. Repository-relative
manual residue stays under the consumer root; `~/...` CLI paths stay under the profile; rooted and
traversing tails are rejected.

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
Installed content references installed paths, never authoring paths. `docs/review-standards.md` is the
exact optional read-only exception for direct-workflow consumers. Autopilot is one self-contained
plugin (agent, skill, launchers, schemas, devcontainer, and templates), with no separate infra bootstrap.

Plugin-owned SI lifecycle/schema and architecture-note scripts remain canonical in their plugins and
dogfood directly. `AtomicStore.psm1` is a normal shared canonical bundle. CI/autopilot bundle
`Write-RecentLearning.ps1` and scaffold its handoff without depending on SI; SI owns its reader and
proposal lifecycle. npm aliases are dogfood-only.

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

Self-improvement's declared topology includes literal manifests/indexes and confined parameterized
active/archive/backup/quarantine/repair/receipt paths; installed SI materializes them on first use.
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
