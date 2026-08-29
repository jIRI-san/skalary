# 6a629b: Vertical implementation and requirement loop
<!-- plan-id: 6a629b -->
<!-- depends-on: 57cc2c, 863d97 -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: phase -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Evolution log - [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt - `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)

## Phase 1: Interactive vertical checkpoint
<!-- worktree: feature/2026-08-14-6a629b-vertical-implementation-requirement-loop -->

- [x] 1.1 Add read-only phase admission to `/ci` using existing plan metadata/state: dependencies complete, phase prerequisites satisfied, confirmed intent available, and applicable requirements identified before mutation (REQ-1, RISK-1) `M`
- [x] 1.2 At phase close, reread confirmed intent, crosscheck applicable requirements through existing evidence results, record the usable increment, and stop for the operator when evidence or high-impact uncertainty is unresolved (REQ-2, REQ-3, RISK-2, RISK-3) [after: 1.1] `M`

## Phase 2: Capture and one-phase autonomy
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Capture decisions, lower-impact uncertainty, and checkpoint outcome through existing `Add-WorkflowNote` kinds; keep contract, user-experience, security, and irreversible-structure uncertainty as an operator checkpoint (REQ-3, REQ-4, RISK-3) [after: 1.2] `M`
- [ ] 2.2 Route autopilot `next-phase` through the same admission and phase-close checks, then stop after one phase and resume from existing plan progress without a second checkpoint format (REQ-2, REQ-5, RISK-2, RISK-4) [after: 2.1] `M`

## Phase 3: Complete-plan integration and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Integrate the loop into `/ci` and autopilot while preserving normal whole-plan progression after operator continuation; synchronize changed payloads through existing plugin generators and notes (REQ-1, REQ-4, REQ-5, REQ-6, RISK-1, RISK-4, RISK-5) [after: 2.2] `M`
- [ ] 3.2 Run focused admission, evidence, capture, operator-stop, next-phase resume, installed-consumer, and generated-drift checks; rebuild the existing evidence receipt and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `M`
