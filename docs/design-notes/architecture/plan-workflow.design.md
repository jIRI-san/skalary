---
description: Plan workflow contracts for cip/ci/autopilot — validator stages, typed evidence, script-only validation, and legacy migration behavior
globs:
  - docs/implementation-plans/**
  - docs/review-ledger/**
  - scripts/skalary/Add-LedgerEntry.ps1
  - scripts/skalary/Remove-LedgerEntry.ps1
  - scripts/skalary/Test-Plan.ps1
  - scripts/skalary/PlanEvidence.psm1
  - scripts/skalary/PlanState.psm1
  - scripts/skalary/New-Plan.ps1
  - scripts/skalary/Validate-Plan.ps1
  - scripts/validate.ps1
  - plugins/create-implementation-plan/**
  - plugins/continue-implementation/**
---

# Plan Workflow

## Architecture

| Component | Responsibility | Notes |
|---|---|---|
| `plugins/create-implementation-plan/skills/cip/SKILL.md` | Orchestrates interview, drafting, DR rounds | Stays orchestration-only; calls validator scripts, does not embed validation logic |
| `plugins/continue-implementation/skills/ci/SKILL.md` | Orchestrates step execution and crosschecks | Uses deterministic script entry points before execution/crosscheck |
| `scripts/skalary/Test-Plan.ps1` | Deterministic plan validator and file-evidence verifier | Supports `-Stage Draft|PhaseCrosscheck|PlanCrosscheck`; reusable evidence verification path |
| `scripts/skalary/PlanState.psm1` | Plan parsing + identity/resolution module | Holds `Get-PlanMetadata` (explicit `-RepoRoot`), `Get-PlanInventory`, `New-PlanId`, `Resolve-Plan`; pure parsing, no plan-text execution |
| `scripts/skalary/New-Plan.ps1` | Scaffolds a new plan folder from the cip template | Generates the id via `New-PlanId`, writes the `plan-id` anchor + `# <id>: <Title>` heading, sanitizes + path-confines the slug |
| `scripts/skalary/PlanEvidence.psm1` | Confined `file:` marker evaluator | Canonicalize-then-confine path checks, assertion vocabulary, regex/time budget enforcement |
| `scripts/skalary/Add-LedgerEntry.ps1` | Deterministic workflow-memory append and dedup writer | Sanitizes untrusted text, enforces category/src/severity enums, uses workspace lock + idempotent replay |
| `scripts/skalary/Remove-LedgerEntry.ps1` | Deterministic workflow-memory prune/tombstone path | Full-line ordinal match, retention guards, `.archive/` move, no regex-driven destructive deletes |
| `docs/review-ledger/**` | Durable workflow-memory store by category | Seven-category taxonomy + README contract; consulted on demand, never auto-loaded |
| `scripts/skalary/Validate-Plan.ps1` + `scripts/validate.ps1` | Repo-level and single-plan entry points | Keep validation pre-approvable and composable via npm scripts |
| `docs/implementation-plans/*/evidence.md` | Receipt of typed evidence checks | Source of truth for archival-gate decisions |

## Key Patterns

| Pattern | Contract |
|---|---|
| Plan identity (naming) | New plan folders use `<yyyy-mm-dd>-<6hex>-<slug>`; the 6-hex `hash` is the stable id, frozen in a `<!-- plan-id: <hash> -->` header anchor and addressable by any unique prefix ≥4 chars (git-short-SHA semantics). Legacy `NNN-<slug>` folders keep parsing in place — no renames. Legacy ids are exactly `\d{3}`; hash prefixes are ≥4 chars, so the domains never overlap by length. |
| Plan-id generation | `New-PlanId` emits 6 crypto-random hex chars (ids are intentionally non-reproducible, so no slug/timestamp hashing). It scans active **and** archived ids, regenerates on a full-id collision, and warns when the id is not uniquely addressable at the 4-char minimum prefix. |
| Plan resolution | `Resolve-Plan` normalizes any reference — hash prefix (≥4), legacy 3-digit number, slug, or date — to the canonical id (the `plan-id` anchor value, or the legacy number). A 6-digit all-numeric reference is a hash, not a legacy number (length disambiguates); ambiguous prefixes error git-style. |
| Typed evidence markers | Acceptance criteria use only `test:<TestId>`, `file:<path>#<assertion>`, and `review:cr|dr`. |
| `file:` assertions | Closed vocabulary: `exists`, `contains:<regex>`, `count>=N`, `dircount>=N`. |
| Script-only validation | `cip`/`ci`/autopilot delegate validation to committed `.ps1` scripts; no in-chat or inline markdown validation logic. |
| Evidence receipt gating | Crosschecks rebuild `evidence.md`; archival/finalization is blocked on unresolved `✗` or unrun required markers unless explicitly deferred in Decisions. |
| Ledger dedup-key contract | `Add-LedgerEntry.ps1` keeps two keys: idempotence key (`category + normalized-lesson + plan + src + severity + sorted-tags`, date excluded) and recurrence key (`category + normalized-lesson + sorted-tags`, plan/src/date excluded). |
| Workflow-memory capture | Mid-run writes are ephemeral (`cr-log.md`, `learnings.md`, `evolution-log.md`) with explicit placeholders so missing sections fail loud while intentionally empty phases stay valid. |
| Workflow-memory harvest | Durable ledger writes happen only at finalization append-harvest via `Add-LedgerEntry.ps1`; prune is escalation-only and script-mediated via `Remove-LedgerEntry.ps1`. |

## Design Decisions

- Plan parsing lives in `PlanState.psm1` so `Test-Plan.ps1`, `New-Plan.ps1`, and the state CLI share one parser. `Get-PlanMetadata` takes an explicit `-RepoRoot` parameter (it previously closed over a script-scoped variable, which a module function cannot inherit under `Set-StrictMode`); all call sites pass it and parity is proven under a non-default `-RepoRoot`.
- Plan ids are random, not content-derived: a hash of slug/timestamp adds no recoverable meaning when ids are non-reproducible by design, so `New-PlanId` uses crypto-random hex and resolves collisions by scanning the active + archived inventory. `Repair-Plans` (and any migration) must never mutate an existing `plan-id` anchor.
- A plan's id is written into the ledger and `depends-on:` in exactly **one** canonical form; callers resolve any reference to that canonical form via `Resolve-Plan` before writing, so dedup/recurrence keys never fork across the legacy/hash schemes.
- `Test-Plan.ps1` is the single validation authority so approval/allowlist models stay stable across host/container/autopilot execution.
- Stage-aware validation avoids self-blocking plans during drafting while still enforcing strict verification at crosscheck/finalization.
- Evidence is machine-checkable only; non-deterministic markers (`cmd:`/`manual:`) are excluded to preserve autopilot safety and repeatability.
- Workflow-memory mutation is script-only (`Add`/`Remove`) and invoked through bound argument arrays; orchestrators do not hand-edit ledger files.

## Constraints

- Plan text is untrusted input. Validation scripts must use pure parsing/bound parameters (no dynamic command execution from plan content). New-plan slug input is sanitized to `[a-z0-9-]` and canonicalize-then-confined under `docs/implementation-plans`.
- Plan identity is dual-format: legacy `NNN-<slug>` folders keep parsing and stay in place; only new plans use `<date>-<hash>-<slug>`. The `plan-id` anchor is the canonical id and is never rewritten by migration.
- Legacy plans without `<!-- evidence: required -->` run in warn-only mode for strict integrity classes; opted-in plans enforce blocking behavior.
- Any workflow change that alters marker grammar, stage semantics, completion gates, or the plan naming/id scheme must update this note and the relevant `cip`/`ci` assets in the same change.
