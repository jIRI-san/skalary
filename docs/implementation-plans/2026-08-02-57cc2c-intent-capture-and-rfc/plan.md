# 57cc2c: Intent capture and design RFC
<!-- plan-id: 57cc2c -->
<!-- cip-stage: dr-round-3 -->
<!-- planning-confirmed: sha256:e29fb7fc979b8180067ab4ef7adb3b59ccdc679a04dee9942dcbafa68f97f49a -->
<!-- epic: bcece1 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata - defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand - never wholesale.

- Intent - [assets/intent.md](assets/intent.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Domain model - [assets/domain.md](assets/domain.md)
- Approved design - [assets/design.md](assets/design.md)
- Evidence receipt - `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs - `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

## Phase 1: Confirm planning context
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Update `/cip` to rephrase and confirm the five intent sections at the intent, domain/design, and final pre-draft checkpoints while preserving confirmed wording, decisions, uncertainty, and rejected alternatives in existing Markdown assets (REQ-1, RISK-1, RISK-3) `M`
- [x] 1.2 Use current lifecycle machinery to write one confirmation marker after the three checkpoints, invalidate it when intent or design changes, and expose the pending confirmation through existing plan state without adding another state store (REQ-2, RISK-1, RISK-2) [after: 1.1] `M`

## Phase 2: Approve a concise complete design
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Update the existing design template and `/cip` guidance to produce a concise Mermaid program design with optional call stacks, then require operator confirmation before drafting (REQ-3, RISK-1, RISK-3) [after: 1.2] `M`
- [x] 2.2 Keep the provisional outline and objective plan checks that route every requirement through MVP-first vertical phases to the complete outcome; leave semantic usability to the operator and design review (REQ-4, RISK-3) [after: 2.1] `M`

## Phase 3: Integrate and verify
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Integrate the confirmed Markdown context into `/ci`, `/dr`, and autopilot through existing layout readers and lifecycle checks; synchronize plugin copies with existing generators and update owning workflow notes (REQ-2, REQ-3, REQ-5, RISK-2, RISK-4) [after: 2.2] `M`
- [ ] 3.2 Run focused interview, invalidation, vertical-plan, installed-consumer, and generated-drift tests; rebuild the existing evidence receipt and complete the final intent/requirement crosscheck (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4) [after: 3.1] `M`
