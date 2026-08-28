# 669ad3: Epic-prefixed plan folder naming
<!-- plan-id: 669ad3 -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming target: <epic-id>-<yyyy-mm-dd>-<plan-id>-<slug> or standalone-<yyyy-mm-dd>-<plan-id>-<slug>; plan-id remains canonical. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Evidence receipt - `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)

## Phase 1: New-plan naming
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Extend existing inventory and resolution parsing to accept current and prefixed hash-plan folders while preserving canonical `plan-id`, stable dependency/ledger references, and legacy numbered-plan behavior (REQ-1, RISK-1, RISK-3) `M`
- [~] 1.2 Update existing plan/epic scaffolding so newly created hash plans use the epic ID or `standalone` prefix directly, without an intermediate rename; synchronize affected plugin copies (REQ-1, REQ-5, RISK-3, RISK-5) [after: 1.1] `M`

## Phase 2: Optional script-owned migration
<!-- worktree: (recorded by /ci when worktree is created) -->

- [~] 2.1 Add one migration script whose default `-WhatIf` path inventories eligible current hash-plan folders, rejects collisions or identity mismatches, and writes a deterministic old/new mapping without moving files (REQ-2, REQ-3, RISK-1, RISK-4) [after: 1.1] `M`
- [ ] 2.2 Add explicit apply/resume that consumes the mapping, moves one folder at a time under one existing repository lock or safe sequential operation, records completion in the mapping, and converges idempotently after interruption; do not invoke bulk migration automatically (REQ-3, REQ-4, RISK-1, RISK-2, RISK-4) [after: 2.1] `M`

## Phase 3: Consumer compatibility and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Update only path consumers that require dual current/prefixed grammar through existing shared resolution; add focused new-plan, legacy, collision, `-WhatIf`, apply, and resume fixtures (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.2, 2.2] `M`
- [ ] 3.2 Run focused inventory/resolution/migration, installed-consumer, generated-drift, and validation checks; rebuild the existing evidence receipt and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `M`
