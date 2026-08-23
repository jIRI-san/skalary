# 863d97: Evidence and receipt truth
<!-- plan-id: 863d97 -->
<!-- cip-stage: dr-round-3 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Design-review evolution — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Truthful evidence outcomes and waivers
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Extend the current evidence result objects, `Test-Plan` verification path, and format-only `Build-EvidenceReceipt.ps1` input handling so each marker retains one explicit outcome: `passed`, `failed`, `skipped`, `unrun`, `stale`, `degraded`, or `waived`. Preserve marker detail in the rendered receipt and add `test:EvidenceTruth.OutcomeAggregationAndRendering` (REQ-1, REQ-4, RISK-1, RISK-3, RISK-4) `L`
- [ ] 1.2 Add a small optional plan-local `assets/evidence-waivers.json` reader. Validate exact plan, requirement, marker, reason, and optional platform at read time; permit a waiver only for an exact skipped/degraded case, keep the visible outcome `waived`, and reject wildcard, stale, malformed, failed, or unrun waivers with `test:EvidenceTruth.PlanLocalWaivers` (REQ-2, REQ-4, RISK-2, RISK-3, RISK-4) [after: 1.1] `M`

## Phase 2: Structured focused execution and finalization gate
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Extend the current `Run-UnitTests.ps1` test runner with focused selection and structured per-test output using its existing discovery, process, environment, timeout, and exit behavior. Preserve selected/executed counts and map Pester pass, fail, skip, not-run, discovery error, and interruption into the shared outcomes; add `test:EvidenceTruth.FocusedStructuredResults` (REQ-3, REQ-4, RISK-1, RISK-3, RISK-5) [after: 1.1] `L`
- [ ] 2.2 Feed structured test results plus current file/review verifier results into the existing receipt formatter. Update CI/autopilot crosschecks and `Test-Plan -Stage PlanCrosscheck` so finalization blocks on `failed`, `skipped`, `unrun`, `stale`, or `degraded` unless the exact result is validly waived; add `test:EvidenceTruth.FinalizationBlocksNonPassingResults` (REQ-1, REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.2, 2.1] `L`

## Phase 3: Distribution and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Synchronize affected CI/CIP/autopilot bundles and dogfood through existing writers, update the plan-workflow and CI-gates notes, and run focused outcome/waiver/finalization tests plus existing structural eval and repository validation paths. Add `test:EvidenceTruth.InstalledParityAndDrift` (REQ-4, REQ-5, RISK-4, RISK-5) [after: 2.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review outcome mapping, waiver exactness, focused structured output, receipt rendering, installed parity, and finalization blocking before archival (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) @human [after: 3.1] `S`
  <details><summary>Details</summary>

  **Steps:**
   1. Run `@cr` over result mapping, waiver parsing, focused test output, formatter integration, finalization gating, synchronized bundles, and owning notes.
   2. Return blocking findings to the owning phase; otherwise record `review:cr` and rebuild the evidence receipt through the existing workflow.

   **Verify:** every marker has a visible outcome, only exact valid waivers satisfy skipped/degraded evidence, every other non-pass blocks PlanCrosscheck, installed copies match canonical scripts, and all required markers in `assets/evidence.md` pass.

   **Rollback:** Do not approve or archive. Remove or correct invalid waivers, mark the affected step `[~]`, and rerun focused checks before rebuilding the receipt.

  </details>
