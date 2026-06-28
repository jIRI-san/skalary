---
description: Plan workflow contracts for cip/ci/autopilot — validator stages, typed evidence, script-only validation, and legacy migration behavior
globs:
  - docs/implementation-plans/**
  - docs/review-ledger/**
  - scripts/skalary/Add-LedgerEntry.ps1
  - scripts/skalary/Remove-LedgerEntry.ps1
  - scripts/skalary/Build-EvidenceReceipt.ps1
  - scripts/skalary/Test-DependencyPlan006.ps1
  - scripts/skalary/Test-Plan.ps1
  - scripts/skalary/PlanEvidence.psm1
  - scripts/skalary/PlanState.psm1
  - scripts/skalary/New-Plan.ps1
  - scripts/skalary/Get-PlanState.ps1
  - scripts/skalary/Set-PlanStage.ps1
  - scripts/skalary/Add-WorkflowNote.ps1
  - scripts/skalary/Repair-Plans.ps1
  - scripts/skalary/Validate-Plan.ps1
  - scripts/validate.ps1
  - plugins/create-implementation-plan/**
  - plugins/continue-implementation/**
---

# Plan Workflow

## Architecture

| Component | Responsibility | Notes |
|---|---|---|
| `plugins/create-implementation-plan/skills/cip/SKILL.md` | Orchestrates interview, drafting, DR rounds | Slim/orchestration-only; calls `New-Plan`/`Set-PlanStage`/`Add-WorkflowNote`/`Test-Plan` and embeds no validation or capture-schema prose; carries the anti-drift contract |
| `plugins/continue-implementation/skills/ci/SKILL.md` | Orchestrates step execution and crosschecks | Slim; reads state via `Get-PlanState`, captures via `Add-WorkflowNote` (`capture.md`), builds receipts via `Build-EvidenceReceipt`; retains resume/reset + `@human`/`[discovery]` judgment under the anti-drift contract |
| `scripts/skalary/Test-Plan.ps1` | Deterministic plan validator and file-evidence verifier | Supports `-Stage Draft|PhaseCrosscheck|PlanCrosscheck`; reusable evidence verification path |
| `scripts/skalary/PlanState.psm1` | Plan parsing + identity/resolution module | Holds `Get-PlanMetadata` (explicit `-RepoRoot`), `Get-PlanInventory`, `New-PlanId`, `Resolve-Plan`; pure parsing, no plan-text execution |
| `scripts/skalary/New-Plan.ps1` | Scaffolds a new plan folder from the cip template | Generates the id via `New-PlanId`, writes the `plan-id` anchor + `# <id>: <Title>` heading, sanitizes + path-confines the slug |
| `scripts/skalary/Get-PlanState.ps1` | Plan progress + next-step state CLI (`npm run plan-state`) | Composes `Resolve-Plan`/`Get-PlanProgress`/`Get-NextStep`/`Get-PlanHeaderMarkers`; text or `-Json`; surfaces `@human`/`[discovery]`/blocked/uncommitted flags so `ci` collapses its read/find-next-step prose to one call |
| `scripts/skalary/Set-PlanStage.ps1` | Idempotent `cip-stage` anchor writer | Single writer of `<!-- cip-stage: ... -->`; `cip`/`dr` set the stage instead of hand-editing the header |
| `scripts/skalary/Add-WorkflowNote.ps1` | Typed mid-run capture writer | `-Kind` CrLog/Learnings/Capture → `cr-log.md`/`learnings.md`/`capture.md`; emits `[src:][sev:]`/`[trigger:]` tokens from typed params, sanitizes only the free-text body, owns init/append + the `No entries for this phase.` placeholder fail-loud contract; the 10-entry fold-to-overflow cap is Learnings-only (`CrLog`/`Capture` uncapped) |
| `scripts/skalary/Repair-Plans.ps1` | On-demand legacy loose-file migration | `-WhatIf`, idempotent no-op on clean, preserves `depends-on`/worktree markers and existing `plan-id`s; archived plans are a non-goal |
| `scripts/skalary/PlanEvidence.psm1` | Confined `file:` marker evaluator | Canonicalize-then-confine path checks, assertion vocabulary, regex/time budget enforcement |
| `scripts/skalary/Add-LedgerEntry.ps1` | Deterministic workflow-memory append and dedup writer | Sanitizes untrusted text, enforces category/src/severity enums, uses workspace lock + idempotent replay; accepts both legacy `\d{3}` and `[0-9a-f]{6}` hash plan ids and canonicalizes the reference via `Resolve-Plan` before writing |
| `scripts/skalary/Remove-LedgerEntry.ps1` | Deterministic workflow-memory prune/tombstone path | Full-line ordinal match, retention guards, `.archive/` move, no regex-driven destructive deletes |
| `scripts/skalary/Build-EvidenceReceipt.ps1` | Format-only per-REQ receipt aggregator | Pure formatter over verifier objects; emits the shared golden receipt line, never re-runs evidence |
| `scripts/skalary/Test-DependencyPlan006.ps1` | Hard phase-0 dependency start-gate | Resolves the guarded plan reference and every `depends-on` token through `Resolve-Plan`; pins compatibility-anchor tokens that slimming must preserve |
| `docs/review-ledger/**` | Durable workflow-memory store by category | Seven-category taxonomy + README contract; consulted on demand, never auto-loaded |
| `scripts/skalary/Validate-Plan.ps1` + `scripts/validate.ps1` | Repo-level and single-plan entry points | Keep validation pre-approvable and composable via npm scripts |
| `docs/implementation-plans/*/evidence.md` | Receipt of typed evidence checks | Source of truth for archival-gate decisions |

## Key Patterns

| Pattern | Contract |
|---|---|
| Plan identity (naming) | New plan folders use `<yyyy-mm-dd>-<6hex>-<slug>`; the 6-hex `hash` is the stable id, frozen in a `<!-- plan-id: <hash> -->` header anchor and addressable by any unique prefix ≥4 chars (git-short-SHA semantics). Legacy `NNN-<slug>` folders keep parsing in place — no renames. Legacy ids are exactly `\d{3}`; hash prefixes are ≥4 chars, so the domains never overlap by length. |
| Plan-id generation | `New-PlanId` emits 6 crypto-random hex chars (ids are intentionally non-reproducible, so no slug/timestamp hashing). It scans active **and** archived ids, regenerates on a full-id collision, and warns when the id is not uniquely addressable at the 4-char minimum prefix. |
| Plan resolution | `Resolve-Plan` normalizes any reference — hash prefix (≥4), legacy 3-digit number, slug, or date — to the canonical id (the `plan-id` anchor value, or the legacy number). A non-hex reference resolves by exact slug first, then a case-insensitive **substring** match — a partial slug resolves only when it uniquely matches one plan. A 6-digit all-numeric reference is a hash, not a legacy number (length disambiguates); ambiguous prefixes/substrings error git-style. |
| Typed evidence markers | Acceptance criteria use only `test:<TestId>`, `file:<path>#<assertion>`, and `review:cr|dr`. |
| `file:` assertions | Closed vocabulary: `exists`, `contains:<regex>`, `count>=N`, `dircount>=N`. |
| Script-only validation | `cip`/`ci`/autopilot delegate validation to committed `.ps1` scripts; no in-chat or inline markdown validation logic. |
| Script distribution (bundling) | The state/validation scripts live once under `scripts/skalary/` (dev tooling + npm), but every script a shipped `ci`/`cip` skill invokes at runtime is **bundled into that plugin** (`plugins/<name>/skills/<skill>/scripts/`, installed to `.github/skills/<skill>/scripts/`) by `Sync-PluginScripts.ps1`, including the `PlanState.psm1`/`PlanEvidence.psm1` module closure. Those skills reference the installed `.github/...` path, never the repo-root `scripts/skalary/...` path, so they stay self-contained on install. (The autopilot agent still invokes these scripts via the repo-root `scripts/skalary/...` path because it always executes inside a checked-out repo; bundling autopilot is a tracked follow-up.) See plugin-registry.design.md → Skill Script Bundling. |
| Evidence receipt gating | Crosschecks rebuild `evidence.md`; archival/finalization is blocked on unresolved `✗` or unrun required markers unless explicitly deferred in Decisions. |
| Ledger dedup-key contract | `Add-LedgerEntry.ps1` keeps two keys: idempotence key (`category + normalized-lesson + plan + src + severity + sorted-tags`, date excluded) and recurrence key (`category + normalized-lesson + sorted-tags`, plan/src/date excluded). |
| Ledger plan-id compatibility | The `$Plan` validator accepts `[0-9a-f]{4,6}` hash prefixes and `<yyyy-mm-dd>` dates alongside `\d{3}` (so `Resolve-LedgerPlanId` can fold any reference before writing), while the `ConvertTo-LedgerRecord` parse regex and the written entry string stay strictly `[0-9a-f]{6}` or `\d{3}`. Widening the parser rescues previously-unparseable well-formed `plan-<6hex>` entry lines so they survive append + canonical rewrite. The canonical rewrite reconstructs the file from the leading header block plus parseable `\d{3}`/`[0-9a-f]{6}` entry lines only — interleaved free-form or malformed lines placed after the first record are not preserved. The reference is folded to one canonical id via `Resolve-Plan` before any key is built, so dedup/recurrence keys never fork across schemes; only `[0-9a-f]{6}` or `\d{3}` is ever written. |
| Shared receipt grammar | `Build-EvidenceReceipt.ps1` is the single emitter of the golden per-REQ line `<glyph> REQ-N — <marker> — <result> — <commit>` (em-dash `U+2014` with surrounding spaces; `✓ U+2713` pass, `✗ U+2717` fail/unrun; result `passed`/`failed`/`unrun`, optional `: <note>`). A REQ passes only when **all** its markers pass; failed and unrun markers are preserved verbatim. The receipt is format-only — it never re-runs evidence. |
| Workflow-memory capture | Mid-run writes are ephemeral and script-mediated via `Add-WorkflowNote.ps1` (`cr-log.md`, `learnings.md`, `capture.md`) with explicit `No entries for this phase.` placeholders so missing sections fail loud while intentionally empty phases stay valid. The 10-entry cap is **Learnings-only** and folds the oldest entries into a single `[trigger:overflow-summary]` line; `CrLog` and `Capture` are uncapped. |
| Workflow-memory harvest | Durable ledger writes happen only at finalization append-harvest via `Add-LedgerEntry.ps1`; prune is escalation-only and script-mediated via `Remove-LedgerEntry.ps1`. |

## Design Decisions

- Plan parsing lives in `PlanState.psm1` so `Test-Plan.ps1`, `New-Plan.ps1`, and the state CLI share one parser. `Get-PlanMetadata` takes an explicit `-RepoRoot` parameter (it previously closed over a script-scoped variable, which a module function cannot inherit under `Set-StrictMode`); all call sites pass it and parity is proven under a non-default `-RepoRoot`.
- Plan ids are random, not content-derived: a hash of slug/timestamp adds no recoverable meaning when ids are non-reproducible by design, so `New-PlanId` uses crypto-random hex and resolves collisions by scanning the active + archived inventory. `Repair-Plans` (and any migration) must never mutate an existing `plan-id` anchor.
- A plan's id is written into the ledger and `depends-on:` in exactly **one** canonical form; callers resolve any reference to that canonical form via `Resolve-Plan` before writing, so dedup/recurrence keys never fork across the legacy/hash schemes. The `Test-DependencyPlan006` start-gate resolves both the guarded reference and each declared dependency the same way, so a legacy `006` and a hash-style dependency trigger identical preflight behavior.
- Ledger hash-id compatibility preserves **well-formed** entry lines: widening the parser (validator + `ConvertTo-LedgerRecord` regex + entry string) was co-edited so previously-unparseable `[0-9a-f]{6}` entry lines become records and survive the canonical rewrite instead of being silently dropped. The rewrite reconstructs from the leading header + parseable records, so it does not guarantee retention of interleaved comments or malformed/short-hex lines placed after the first record; a mixed-format round-trip regression test guards the entry-line case.
- Evidence receipts have one golden grammar emitted only by `Build-EvidenceReceipt.ps1`; orchestrators and autopilot consume that shared formatter rather than hand-writing receipt lines, so the receipt shape stays identical across `ci`/`cip`/autopilot.
- The workflow scripts have a single source of truth (`scripts/skalary/`) but are duplicated into each consuming plugin rather than shared through a runtime module or a common plugin. Plugins install and are versioned independently, so a shared runtime location cannot guarantee a compatible script is present; managed duplication (generated by `Sync-PluginScripts.ps1`, drift-gated to byte-identical) is the accepted cost of that independence. Consequently, **a change to any shared script bumps the `version` of every plugin that bundles it** — the edit is a payload change to each dependent plugin.
- `Test-Plan.ps1` is the single validation authority so approval/allowlist models stay stable across host/container/autopilot execution.
- Stage-aware validation avoids self-blocking plans during drafting while still enforcing strict verification at crosscheck/finalization.
- Evidence is machine-checkable only; non-deterministic markers (`cmd:`/`manual:`) are excluded to preserve autopilot safety and repeatability.
- Workflow-memory mutation is script-only (`Add`/`Remove`) and invoked through bound argument arrays; orchestrators do not hand-edit ledger files.

## Constraints

- Plan text is untrusted input. Validation scripts must use pure parsing/bound parameters (no dynamic command execution from plan content). New-plan slug input is sanitized to `[a-z0-9-]` and canonicalize-then-confined under `docs/implementation-plans`.
- Plan identity is dual-format: legacy `NNN-<slug>` folders keep parsing and stay in place; only new plans use `<date>-<hash>-<slug>`. The `plan-id` anchor is the canonical id and is never rewritten by migration.
- A legacy `NNN-<slug>` folder must not carry a divergent hex `plan-id` anchor: `Get-PlanInventory` sets the canonical id to the anchor value when present, so a mismatched anchor makes the plan unaddressable by its 3-digit number and can fork ledger/`depends-on` keys.
- Header anchors (`plan-id`, `cip-stage`) are read/written file-wide today (`Get-PlanInventory`, `Set-PlanStage`), not header-scoped like `Get-PlanHeaderMarkers`. Keep these anchors in the pre-`##` header and never place an example `<!-- plan-id: ... -->` / `<!-- cip-stage: ... -->` in the body — a body occurrence can hijack canonical identity or block the real stage write.
- `Get-PlanState`'s uncommitted-changes probe is best-effort/fail-open: a `git status` failure reports a clean tree, so the explicit commit gate (not this flag) remains the authority on dirty-tree state.
- Legacy plans without `<!-- evidence: required -->` run in warn-only mode for strict integrity classes; opted-in plans enforce blocking behavior.
- Any workflow change that alters marker grammar, stage semantics, completion gates, or the plan naming/id scheme must update this note and the relevant `cip`/`ci` assets in the same change.
- Any edit to a `scripts/skalary/` script that is bundled into a plugin must re-run `Sync-PluginScripts.ps1` (which re-copies the bundle and **patch-bumps the `version` of every plugin that bundles that script**), then rebuild `registry.json`, in the same change; the `Sync-PluginScripts.ps1 -WhatIf` bundle drift gate in `scripts/validate.ps1` fails CI otherwise.
