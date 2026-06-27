# Crosscheck Guide (`ci` Step 5)

> Read this asset when validating phase/plan completion and proving requirements with typed evidence.

## Evidence verification

At phase and plan crosschecks, verify each requirement's typed markers from Acceptance Criteria:

- `test:<TestId>` -> run only the named Pester test and fail if it is missing or failing.
- `file:<path>#<assertion>` -> verify via `scripts/skalary/Test-Plan.ps1 -EvidenceMarker ... -EvidenceStage <PhaseCrosscheck|PlanCrosscheck>` (delegates to the dot-sourceable `PlanEvidence` callable).
- `review:cr|dr` -> verify the relevant review run reports no remaining findings for the claimed class; treat "no review run" as unrun evidence (fail the gate).

Use deterministic, pre-approvable commands only. Parse markers into typed variables and pass them as bound arguments (no shell-string interpolation, no eval). Use `PlanCrosscheck` only at true finalization.

Build the receipt with the shared formatter — do not hand-write receipt lines. `Build-EvidenceReceipt.ps1` is a **pure formatter**: it takes the per-marker verifier results as `-Result` objects (each carrying `Req`, `Marker`, `Success`, and an optional `Note`) plus the current `-Commit`, and returns an object whose `.Text` you write into `evidence.md` (the script itself does not read or write `evidence.md`):

```powershell
# $results = array of [pscustomobject]@{ Req='REQ-1'; Marker='test:foo'; Success=$true; Note='' } ...
$receipt = & scripts/skalary/Build-EvidenceReceipt.ps1 -Result $results -Commit <HEAD-sha> -Phase <N>
Set-Content -LiteralPath <plan-folder>/evidence.md -Value $receipt.Text -Encoding utf8NoBOM
```

`Build-EvidenceReceipt` emits the golden line `<glyph> REQ-N — <marker> — <result> — <commit>` (`✓` pass, `✗` fail/unrun); a REQ passes only when all its markers pass, and failed/unrun markers are preserved.

Receipt rules:
- Rebuild `evidence.md` on each phase/plan crosscheck run (never append to stale results from old commits).
- Emit one line per required marker; unexecuted markers emit `✗ … — unrun`.
- Use the current `HEAD` commit SHA in every emitted line.

## Phase crosscheck

1. Collect REQ IDs referenced by steps in the current phase.
2. Validate each acceptance criterion against implementation + typed evidence checks (`test:`/`file:`/`review:`).
3. Rebuild `evidence.md` via `Build-EvidenceReceipt` with the current commit SHA.
4. Fail phase completion if blocking criteria are unsatisfied.

## Plan crosscheck

1. Validate all REQ and RISK rows before completion.
2. Ensure unresolved gaps are explicitly deferred in Decisions if not fixed.
3. Re-run typed evidence checks at plan scope (`PlanCrosscheck` stage) at true finalization.

## archival-gate

Before archive/PR completion, require:
- `evidence.md` exists and is current.
- No unrun or failing required evidence (`✗`) remains unless explicitly deferred in Decisions (defer by REQ ID with rationale).
- This step wires the gate only; run `PlanCrosscheck` blocking target resolution only at true plan finalization (after all phases).

If the gate is not satisfied, block archival/completion.

## Dependency preflight (hard start-gate)

For plans declaring `<!-- depends-on: <id> -->`, run this deterministic non-Pester check at plan start and again immediately before any interactive harvest/finalization branch:

```powershell
pwsh -NoProfile -File scripts/skalary/Test-DependencyPlan006.ps1 -RepoRoot . -PlanPath <selected-plan-path>
```

It resolves the dependency through `Resolve-Plan` and validates the 006 behavior contracts through public script paths (pass/fail `file:` probes, evidence vocabulary, the `test:unit` gate, and pinned compatibility-anchor tokens). If it exits non-zero, stop execution immediately.

## Interactive harvest trigger (`/ci`) — mirror of canonical autopilot flow

This section is a **mirror** of the canonical harvest procedure in `plugins/autopilot/agents/autopilot.agent.md`. Keep parity with that file whenever harvest behavior changes.

At interactive plan completion, `/ci` runs harvest with the same shared scripts and ordering:

1. Run dependency preflight (`Test-DependencyPlan006.ps1`) before entering harvest/finalization.
2. If append infra is present (`Test-Path scripts/skalary/Add-LedgerEntry.ps1` and `Test-Path docs/review-ledger`), execute append harvest first:
   - Require category files (at minimum `docs/review-ledger/security.md` and `docs/review-ledger/testing.md`) before invoking append scripts.
   - Distill entries from `capture.md` (`## Capture`), `cr-log.md`, and `learnings.md`.
   - Map candidates deterministically into `Add-LedgerEntry` inputs: `-Category` from the 7-category rubric, `-Plan` the canonical plan id, `-Src ci`, `-Severity` from captured severity (default `Med`), `-Entry` one sanitized lesson, `-Tags` sorted tags.
   - Invoke `Add-LedgerEntry.ps1` via argument arrays / `ArgumentList` only (no shell-string interpolation).
   - Stage and commit ledger updates by explicit file names under `docs/review-ledger/`.
   - If harvest is idempotent/no-op with no staged ledger delta, skip the append commit and continue to branch selection.
3. Branch after the append commit:
   - Autonomous completion: push, archive commit, **required post-archive push**, create non-draft PR.
   - `@human` escalation: push, run `/udn` reconciliation with the user present first, derive full-line prune candidates, run `Remove-LedgerEntry.ps1`, commit prune/design-note edits, push, create draft PR, write marker, stop.
   - `/udn` contract: run deterministic reconciliation prompts/checks; if ambiguity remains, keep the draft-PR + marker path (no archive).
   - Prune preconditions: `Test-Path scripts/skalary/Remove-LedgerEntry.ps1` and `Test-Path docs/review-ledger/.archive`; if missing, skip prune and continue direct draft escalation.
   - Invoke `Remove-LedgerEntry.ps1` via argument arrays / `ArgumentList` only; always pass `-Category`, `-CurrentPlan`, and full-line candidate match payload (`-Match`/`-MatchBase64`) — never substring/regex targeting.
4. If repo infra is absent, skip harvest and keep branch semantics explicit: autonomous completion may continue standard completion flow, but `@human` completion must still route to draft PR + marker (no archive).

Fail-loud behavior: error only when expected log sections/placeholders are missing; `No entries for this phase.` is valid and must not fail harvest.

## `ledger-consult` (before a CR round)

Before launching a CR round (`@cr`, `code-review`, or `rubber-duck`), consult only the relevant category files from `docs/review-ledger/`:

- `security.md` — auth/trust-boundary/injection/secret/ACL
- `performance.md` — latency/throughput/allocation/N+1
- `error-handling.md` — retry/timeout/fail-loud/exception-flow
- `consistency.md` — contract drift/naming parity/duplication
- `plan-structure.md` — dependency gates/phase order/evidence-flow
- `testing.md` — flaky/missing/weak evidence coverage
- `observability.md` — logs/metrics/tracing/audit

Rules: exclude `docs/review-ledger/.archive/`; read only categories implied by the current step's REQ/RISK scope; optionally filter by `#tag`; never auto-load all ledger files by default.

## Ephemeral capture (`cr-log.md` / `learnings.md`, mid-run only)

Capture is mid-run, plan-folder-local, and **script-only** via `Add-WorkflowNote.ps1` — do not hand-edit these files and do not write `docs/review-ledger/*` during capture:

- Initialize a phase section (header + `No entries for this phase.` placeholder) by calling `Add-WorkflowNote` with no `-Message`.
- `cr-log.md` (`-Kind CrLog`): interactive `ci` persists `@cr` report + triage; autopilot persists `code-review`/`rubber-duck` findings with `-Src code-review`; standalone `cr` persists nothing.
- `learnings.md` (`-Kind Learnings`): append only on `rework>1`, `plan-contradiction`, or `reusable-pattern` triggers; the script replaces the phase placeholder and caps at 10 entries per plan with one `overflow-summary` fold.
- Stage and commit the changed log by explicit filename.

Fail-loud: missing required sections/placeholders fail; an intentionally empty `No entries for this phase.` section stays valid.
