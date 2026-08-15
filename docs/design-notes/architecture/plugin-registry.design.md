---
description: Plugin registry architecture for skalary — plugin manifests, generated registry, install/update/remove flows, integrity and confinement guarantees
globs:
  - plugins/**
  - registry.json
  - scripts/skalary/**
  - schemas/plugin/plugin.schema.json
  - schemas/registry/registry.schema.json
  - schemas/receipt/receipt.schema.json
  - .github/.skalary/**
---

# Plugin Registry

The plugin registry is a source-first packaging system: `plugins/` is authoritative, `registry.json` is generated metadata, and `.github/` is a dogfood install target synchronized from plugin sources.

## Bundle Model and Layout

| Layer | Source of truth | Purpose | Files |
|---|---|---|---|
| Plugin source | `plugins/<name>/` | Authoring bundle with manifest + payload | `plugins/*/plugin.json`, payload files |
| Registry index | `registry.json` | Generated install catalog with file hashes and bootstrap metadata | `scripts/skalary/Build-Registry.ps1` output |
| Runtime state | `.github/.skalary/receipts/<name>.json` | Per-plugin installation tracking, merge-safe | install/update/remove verbs |
| Retirement state | `.github/.skalary/retirements/<name>.json` | Durable, source-bound preview/apply/result authority | retirement reconciler and shared removal engine |
| Dogfood target | `.github/**` | Installed copies used by local tooling | `Sync-Dogfood.ps1` |
| Skill script bundle | `plugins/<name>/skills/<skill>/scripts/**` | Per-plugin copies of the workflow scripts a skill invokes at runtime, generated from `scripts/skalary/` | `Sync-PluginScripts.ps1` |

## Schema Contracts

| Schema | Contract |
|---|---|
| `schemas/plugin/plugin.schema.json` | Declares plugin identity, semver, dependencies, `files[]` as `{src,dest}`, optional `status`, optional `scaffolds[]` (first-use runtime paths outside `.github/`), reserved `evals` block. |
| `schemas/registry/registry.schema.json` | Generated catalog embeds per-file `sha256`, the plugin's `scaffolds[]`, and bootstrap metadata (`ref`, script URL, one-liner). |
| `schemas/receipt/receipt.schema.json` | Per-plugin receipt stores resolved source `ref` SHA, version, and per-file `{dest,sha256,outcome}` with optional `degraded` and reserved `evalStatus`. |
| `schemas/registry/plugin-retirement.schema.json` | Closed permanent tombstone catalog: immutable source/ref/version payload sets plus manual residue remedies. |
| `schemas/retirement/retirement-state.schema.json` | Closed versioned consumer state for `preview`, `applying`, `retired`, `residue`, and `failed`, including the complete affected path/hash set and prior source/ref/version. |

Design choice: per-plugin receipts replace a shared lock file to avoid cross-branch merge conflicts.

Receipt writers use the shared version 1 `sourceIdentity` API in `_Common.ps1`. GitHub sources
persist only canonical `github.com/<owner>/<repository>` identity; local sources persist only a
SHA-256 digest of the canonical path. The immutable commit `ref` remains a separate field. Legacy
`source` labels are accepted for ordinary receipt reads but retirement can upgrade them only when
their kind and exact `@<ref>` suffix are unambiguous; otherwise reconciliation fails closed.

Retirement state names pass the plugin-name grammar before path construction, and the resulting
path is resolved through the same `.github` confinement helper as payload destinations. Reads and
writes validate the closed embedded version 1 schema. Durable state never truncates affected files;
only summaries cap displayed paths and carry total/omitted counts.

`registry-retirements.json` is the canonical permanent retirement catalog. `Build-Registry.ps1`
copies it into skalary `registry.json.retiredPlugins`; the Copilot marketplace remains active-only.
Active and retired names are disjoint. `Test-PluginRetirementHistory.ps1` compares explicit files
without reading Git; CI alone materializes the pull-request base or previous-push commit, treating a
resolvable commit with no catalog as the empty set and failing when a required commit is unavailable.
`Test-Registry.ps1` remains Git-free.

## Copilot Skill Metadata Boundary

To prevent drift with evolving Copilot skill specs, plugin packaging keeps ownership boundaries explicit:

| Artifact | Allowed metadata |
|---|---|
| `SKILL.md` (inside plugin payload) | Standard Copilot skill frontmatter and skill body only. |
| `plugin.json` | Packaging and install metadata (`version`, dependencies, `files[]`, status, eval reservation). |
| `registry.json` | Generated install index derived from `plugin.json` + file hashes. |

`plugin.json` must not introduce alternate skill-schema fields into `SKILL.md`; compatibility is preserved by keeping skill spec data standard and packaging data external.

## Dependency and Install Model

Install/update behavior is implemented in `scripts/skalary/Install-Plugin.ps1` and `scripts/skalary/Update-Plugin.ps1` using shared helpers in `_Common.ps1`.

| Area | Decision |
|---|---|
| Dependency resolution | Deterministic topological order, dedupe by plugin name, lexical tie-breaks, cycle detection before copy. |
| Source coherence | One resolved SHA per operation; remote clone and local `-Source` both install from a single commit snapshot. |
| Transactional apply | Stage files under `.github/.skalary/tmp/`, verify staged hashes, back up targets, atomic move, then write receipt. |
| Rollback | Any failure restores backups, removes staged files, writes no new receipt. |
| `evals/` handling | Files under `evals/` are always excluded from installation. |

Explicit uninstall and automatic retirement call one `Invoke-PluginRemovalPrimitive` in
`_Common.ps1`. The primitive serializes through `.github/.skalary/mutation.lock`, validates all
payload/state/journal/backup paths and existing parent chains before state reads or mutation, and
writes a schema-validated journal before backup/delete/receipt boundaries. Recovery treats that
journal as untrusted: plugin/source/transaction identity, receipt pre/post hashes, confined
transaction-derived backup paths, and backup content hashes must all agree before rollback.

Retirement authority is never read from preview or journal state. Under the lock, the primitive
rederives the exact intersection of the tombstone's immutable source/ref/version destination hashes
and the current same-source receipt. Modified files remain on disk and retain their original
expected receipt hash under `degraded`/`skipped-modified` ownership; only explicit
`Remove-Plugin -Force` can remove them. A `failed` retirement state returns to `preview` only after
journal recovery and exact source/ref/version, receipt ownership, and observed-content verification.

## Integrity and Security Model

| Threat | Guard |
|---|---|
| Path traversal / escape from `.github/` | Full-path resolution rejects `..`, absolute, UNC, drive-relative, and ADS destinations; managed mutation also rejects links/reparse points in destinations and parent chains. |
| Payload tampering | Staged payload hash must match `registry.json` before any move. |
| Cross-plugin overwrite/remove collisions | Registry-wide destination uniqueness validation + runtime ownership map from receipts. |
| Destructive overwrite/remove of user edits | Update/remove verify receipt hash and mark modified files as skipped unless `-Force`. |
| Arbitrary code execution in bootstrap flow | `bootstrap.ps1` downloads scripts + `registry.json` only; it does not execute plugin payload. |

## Catalog Determinism

`registry.json`, `.github/plugin/marketplace.json` and the README catalog table are compared byte for byte by their drift gates, so their ordering must be a property of the build rather than of the host that ran it. PowerShell's `Sort-Object` compares through the current culture: `cs-CZ` reads the digraph `ch` as one letter placed after `h` and sorts accented letters apart from the base letter `en-US` folds them onto.

| Invariant | Rule |
|---|---|
| One comparer | Every list reaching a generated catalog is ordered by `Sort-Ordinal` (`_Common.ps1`) with an explicit `[System.StringComparer]::Ordinal`. `Build-Registry.ps1`, `Build-Marketplace.ps1` and `Test-Registry.ps1` each declare `$script:CatalogComparer` and pass it, so the choice is visible where the catalog is owned. |
| Generator and gate agree | `Test-Registry.ps1` re-derives the README catalog block, so it is a second implementation of the same ordering and must use the same comparer — otherwise the gate rejects a correctly generated README on a differently collating host. |
| Ordinal equality | Drift and idempotence comparisons use `[string]::Equals(..., [StringComparison]::Ordinal)`, not `-eq`/`-ne`. |
| Proven, not assumed | `test:BuildRegistry.CzechCollationFixtureIsStable` rebuilds every catalog under `en-US` then `cs-CZ` and requires byte-identical output; `test:BuildRegistry.FixtureIsRedBeforeFix` keeps the fixture's ids genuinely divergent, so the stability assertion cannot pass vacuously. |

## Validation Payload Scope

`scripts/validate.ps1` parses its file set through `scripts/skalary/PayloadScope.psm1` rather than `Get-ChildItem -Recurse`.

| Invariant | Rule |
|---|---|
| Allowlist, not denylist | `Get-SkalaryPayloadFile` walks an explicit list of payload roots. A root nobody listed is not scanned, instead of a name nobody thought to exclude being scanned. |
| Platform parity | Without `-Force` pwsh treats dot-prefixed entries as hidden on Unix and not on Windows, so `.github` was parsed on one platform only. The allowlist walk sees the same set on both. |
| Pruned subtrees | `.git`, `.skalary`, `.worktrees`, `bin`, `node_modules`, `obj` are pruned wherever they nest. `.github/.skalary` is the installer's gitignored runtime state; parsing it would make the file count a function of local install history. |
| Reparse points refused | `Path.GetFullPath` normalises `..` and separators but does not resolve links, so directories carrying the reparse-point attribute are not descended into. Unreadable *files* fail loudly rather than vanishing from the set. |
| No silent empty run | A missing allowlisted root throws under `-RequireRoot`, and a run that enumerated nothing is an error — a gate that parsed nothing has proved nothing. |

## Autopilot Plugin Bundle

`autopilot` is a self-contained plugin: agent, autonomous skill, launch scripts, schema files, devcontainer assets, and config templates ship from `plugins/autopilot/` and install under `.github/agents/` and `.github/skills/autopilot/**`.

No separate autopilot infra bootstrap script exists. Provisioning happens through standard plugin install/update and dogfood sync flows.

## Dogfood Authority and Sync

`plugins/` is authoritative. `.github/` is treated as installed output and can drift.

`scripts/skalary/Sync-Dogfood.ps1` converges `.github/` back to `plugins/` sources, is idempotent, and supports `-WhatIf` for CI drift detection. Running sync to convergence produces the expected state for CI drift-check pass criteria (`.github/` byte-equivalent to plugin sources). Destination collision checks in sync mirror registry safety rules.

## Skill Script Bundling

Skills and agents that invoke deterministic PowerShell at runtime must ship that code **inside their own plugin**. The canonical sources live once under `scripts/skalary/`; `Sync-PluginScripts.ps1` copies each plugin's referenced scripts (plus their closure — `.psm1` module imports **and** `.ps1` dot-source siblings such as `_Common.ps1`; the closure regex matches `\.psm?1` with a leading `[A-Za-z0-9_]`) into `plugins/<name>/skills/<skill>/scripts/`, which the manifest `files[]` then installs to `.github/skills/<skill>/scripts/`. The `ci` and `cip` plugins bundle their workflow scripts this way; the autopilot agent is a tracked follow-up (it currently runs scripts from the repo-root `scripts/skalary/` path because it always executes inside a checked-out repo).

| Invariant | Rule |
|---|---|
| Bundle-or-break | Every script a shipped `SKILL.md`/agent invokes at runtime must be listed in that plugin's `files[]` and referenced by its **installed** path (`.github/skills/<skill>/scripts/<Script>.ps1`), never by the repo-root `scripts/skalary/...` path. Repo-root references only work while dogfooding and silently break on install into another repo. |
| Managed duplication | Bundled copies are generated, not hand-authored: `scripts/skalary/` is the single source of truth and `Sync-PluginScripts.ps1` is the only writer of `plugins/**/skills/**/scripts/`. A `-WhatIf` drift gate (wired into `scripts/validate.ps1`) proves every bundled copy is byte-identical to its source. |
| Version independence | Plugins install and version independently, so each carries its own copy — duplication across plugins is intentional and accepted (no shared runtime module, no cross-plugin hierarchy). |
| Version-bump coupling | Because there is exactly one source per script, **any change to a shared script bumps the `version` of every plugin that bundles it.** `Sync-PluginScripts.ps1` performs this patch bump automatically when it re-copies a changed bundle, so the advertised version never lags the payload. A script edit is a content change to each dependent plugin's payload; a stale (unsynced) bundle fails the `-WhatIf` drift gate. |
| Plugin-owned scripts (exception) | Not every plugin script is a `scripts/skalary/` bundle. The `architecture-notes` scripts (`Copy-ArchScaffold`, `Import-ArchHarvest`, `Import-ArchAdr`, …) and the `architecture-tests` **adapters/providers** (`plugins/architecture-tests/scripts/{adapters,providers}/**`) are **canonical inside their own plugin**, not `scripts/skalary/`. `Sync-PluginScripts.ps1` does not manage them; `Sync-Dogfood.ps1` mirrors them to `.github/`. Referencing a plugin-owned script by the literal installed path `.github/skills/<skill>/scripts/<Name>.ps1` from a **foreign** plugin's content triggers a stray cross-plugin bundle (the bundler's ref regex) — so cross-plugin references use bare names or gated wording. |

The one deliberate split: the `architecture-tests` **runner** (`Invoke-ArchTests.ps1`) is a normal `scripts/skalary/` bundle (single source of truth) but is bundled into `architecture-tests` **only** — its **adapter/provider file set** (`plugins/architecture-tests/scripts/{adapters,providers}/**`) is plugin-owned and can't be bundled into `ci` (the runner, `ArchReceipt.psm1`, `Assert-ArchLock.ps1`, and `Invoke-ArchAdapter.ps1` are all `scripts/skalary/` bundles), so `/ci` invokes the installed runner via a gated bare reference. See [architecture-tests.design.md](architecture-tests.design.md).


The npm aliases (`plan-state`, `new-plan`, `validate-plan`, etc.) target `scripts/skalary/` directly and remain a **dogfood-only** developer convenience; installed skills never depend on npm.

## Asset Bootstrap

A skill that reads a file which exists only in this repo's working tree works perfectly when
dogfooded and fails in every consumer repo — **quietly**. The agent reads nothing, proceeds without
the guide/map/template, and produces degraded output rather than an error. That failure mode is why
this is a gate rather than a convention.

| Invariant | Rule |
|---|---|
| Installed by default | Every file a payload (`SKILL.md`, `*.agent.md`, `*.prompt.md`, bundled script, or another asset) reads at runtime must appear in some plugin's `files[]` with a `dest` under `.github/`. Installation materializes it, the registry hashes it, install/remove stay transactional. |
| Scaffolded when installation cannot reach it | `ARCH-Install-Confinement` confines installer writes to `.github/`, and there is no post-install hook. A runtime path outside `.github/` is therefore materialized on **first use** by the owning skill or script and declared in `scaffolds[]`. A post-install hook would be the alternative, and it is precisely what the confinement exists to prevent. |
| Declarations reach the registry | Consumer installs resolve against `registry.json`, not the source tree, so `Build-Registry.ps1` carries `scaffolds[]` through. A declaration that stops at `plugin.json` never reaches the repo that has to honour it. |
| Two modes, both explicit | A **literal** entry names a fixed path and forbids a `confine` helper. A **parameterized** entry uses `<name>` (one segment) or `**` (subtree), **requires** a `confine` helper, and may carry a closed `values` domain. The schema enforces both branches, so a variable path cannot be mislabelled as fixed to dodge the helper requirement. |
| Declarations must be true | The declared `confine` helper has to be shipped **and called** by the declaring plugin's own payload — asserted by test, because a manifest that describes a control nobody implements is worse than no manifest: it passes the gate while the gap stays open. `owner` and `trigger` are **documentation, not assertions**; they name who to go ask, and nothing verifies that the named owner performs the write. |

**The scanner grammar is closed** (`Sync-PluginScripts.ps1`, gated by `validate.ps1` via `-WhatIf`):

1. **Installed-path literal** — `.github/` followed by one of the three payload roots (`skills/`, `agents/`, `prompts/`); required `dest` is the same path minus `.github/`. An undeclared `.github/agents/...` or `.github/prompts/...` reference fails exactly like a skill asset does.
2. **Skill-relative** — `./assets/<file>`, resolved against the payload's **skill root**, so a guide living under `assets/` spells a sibling exactly as its `SKILL.md` does. The leading `./` is load-bearing: a bare `assets/intent.md` names a *plan folder* asset, which is not a payload file at all.
3. **Scaffold path** — a `docs/`, `schemas/`, or `tools/` runtime path under a root some plugin scaffolds; it must match a `scaffolds[]` entry.

Out of grammar, deliberately: fenced code blocks (illustrations, not reads — and an *unterminated*
fence is an error, because blanking the remainder of a file would silently narrow the gate),
dynamically composed reads (`Join-Path './assets' $name` — unsupported, must not appear in a
payload), and a path whose final segment is a bare `<placeholder>` (prose describing a shape).

**Known bound — enforcement is self-referential.** Arm 3 only inspects a reference whose root some
plugin *already* declares in `scaffolds[]`, because the root set is derived from the declarations
themselves. A root nobody has declared is not a violation; it is skipped, so the gate cannot see it.
`docs/review-ledger/` is declared and therefore checked; `docs/design-notes/` is not, so
`design-notes/SKILL.md` reading `docs/design-notes/.design-notes.md` at runtime — outside `.github/`,
absent from `files[]` and from every `scaffolds[]` — passes silently, and would degrade in a consumer
repo that lacks the file. Two paths of the same class, opposite enforcement, decided by which plugin
happened to declare first.

So the guarantee is narrower than "every runtime path is declared": it is *"declarations are
exhaustive for roots that already have at least one declaration."* Widening it means rooting the
closed set in the grammar (`docs`, `schemas`, `tools`) rather than in the declared set, which turns
every currently-invisible reference into a violation that must be declared or excluded. That is
tracked, not done — see
[explorations/asset-scanner-root-bound.design.md](../explorations/asset-scanner-root-bound.design.md).

Bundled `.ps1`/`.psm1` whose canonical source is `scripts/skalary/` are skipped by arm 1 — the
script-bundler arm materializes them on the same run. A **plugin-local** script has no such owner
and stays subject to the `files[]` check.

## Skill Size Cap

A `SKILL.md` is loaded in full on every invocation of its skill, so its size is a recurring
per-invocation context cost, not a one-off. `scripts/skalary/Test-SkillSize.ps1` enforces a
repo-wide **12 KB cap** (`-MaxBytes 12000`, pinned against this note by test) over both the plugin sources and the `.github/` dogfood mirror (the mirror is
what the hosts actually load), and is wired into `scripts/validate.ps1`. Detail goes into `assets/`
and is read on demand — which then makes it subject to the asset-bootstrap gate above.

## Copilot CLI Marketplace (dual catalog)

The same `plugins/*/plugin.json` sources feed a second, independent catalog for GitHub Copilot CLI: `.github/plugin/marketplace.json`, generated by `scripts/skalary/Build-Marketplace.ps1` and validated against `schemas/marketplace.schema.json`. This makes the repo installable both ways — skalary's `registry.json` → committed `.github/` (VS Code), and `marketplace.json` → `~/.copilot/installed-plugins/` (`copilot plugin install <name>@skalary`).

| Invariant | Rule |
|---|---|
| Shared manifest | Copilot CLI reads the **same** `plugins/<name>/plugin.json`; its skalary-only fields are tolerated (spike-confirmed). Marketplace entries set `strict: false` as a safeguard. |
| Generator-owned path | `.github/plugin/marketplace.json` is written only by `Build-Marketplace.ps1`. `Sync-Dogfood.ps1` is copy-only and never prunes, so the generated catalog coexists without drift. |
| Drift gate | `validate.ps1` runs `Build-Marketplace.ps1 -WhatIf` (semantic compare); a stale catalog fails validation. |

### `-RegistryPath` fallback

`Find-Plugin.ps1`, `Get-Plugin.ps1`, and `Remove-Plugin.ps1`'s dependent check accept `-RegistryPath` and fall back to `scripts/skalary/registry.json` (via `Resolve-RegistryPath` in `_Common.ps1`) when no root `registry.json` exists — the bootstrapped-repo layout. With neither present they emit a clear "not a skalary-managed repo" error instead of a terse throw. See [plugin-manager.design.md](./plugin-manager.design.md) for the skills that depend on this.
## Evals Contract

Plan 005 implements the eval harness as **report-only** and keeps registry/receipt seams reserved:

| Surface | Reserved contract |
|---|---|
| Plugin manifest | Optional `evals` object with `path`, `status`, `lastRun`. |
| Registry | Per-plugin `evals.status` summary. |
| Receipt | Reserved `evalStatus` field. |
| Validation | `Test-Registry.ps1` emits warn-only informational eval checks. |

The harness writes `.eval-report.json` (and optional `.eval-artifacts/*`) only. It does **not** populate `plugin.json` `evals.status` / `lastRun`, `registry.json` `evals.status`, or receipt `evalStatus`.

Known issue (DR2-#15): structural evals now exist for all plugins, but `registry.json` may still report `evals.status: "none"` because the seam remains reserved. Treat that field as non-authoritative until registry writeback is explicitly implemented.

See [plugin-evals.design.md](./plugin-evals.design.md) for harness behavior, backend isolation, and judge contracts.
