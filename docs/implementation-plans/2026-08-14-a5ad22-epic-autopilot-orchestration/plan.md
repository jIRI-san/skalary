# a5ad22: Epic autopilot orchestration
<!-- plan-id: a5ad22 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle. -->

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

## Phase 1: One-child host loop
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Add a host-owned epic loop that reads the existing `Get-PlanState` epic rollup, selects its `NextChild`, and persists one small resumable JSON record containing `epic`, `target`, `currentChild`, `branch`, `run`, and `outcome` (REQ-1, REQ-2, RISK-1) `M`
- [x] 1.2 Invoke the existing per-plan launcher for that child only, enforce one active child/container, and update the small state record from launcher start and terminal results without changing child execution semantics (REQ-1, REQ-2, RISK-2, RISK-4) [after: 1.1] `M`

## Phase 2: Merge gate and repeat
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Verify the child's terminal result, evidence, branch, and remote head through existing launcher outputs, then stop for operator merge rather than pushing or merging from the epic loop (REQ-3, RISK-2, RISK-3, RISK-4) [after: 1.2] `M`
- [ ] 2.2 After operator merge, refresh the target and `Get-PlanState` graph, clear the current child, select the next eligible child, and repeat; retain failure/block/degraded outcomes for explicit resume instead of skipping work (REQ-2, REQ-4, RISK-1, RISK-3, RISK-4) [after: 2.1] `M`

## Phase 3: Epic close and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 After the final merge, invoke the simplified epic-coherency review when available or run an epic-intent/definition-of-done crosscheck; record the result without creating an evidence-only finalization PR (REQ-5, RISK-5) [after: 2.2] `M`
- [ ] 3.2 Add focused state/resume, one-child, terminal-stop, target-refresh, failure, and final-crosscheck tests; synchronize existing plugin/generated copies, rebuild the existing evidence receipt, and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `M`
