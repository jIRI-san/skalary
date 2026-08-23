# 9fda0b: GitHub work hierarchy synchronization
<!-- plan-id: 9fda0b -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle. -->

<!-- execution-mode: manual -->
<!-- scope: step -->
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

## Phase 1: Deterministic GitHub dry run
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 1.1 Build a pure deterministic projection from one local epic and its child plan assets to a GitHub parent issue, child issues, dependencies, phases, purpose, and acceptance content; define a narrow provider interface and one GitHub `gh` adapter (REQ-1, REQ-5, RISK-3, RISK-5) `M`
- [ ] 1.2 Add a read-only dry run that queries GitHub through the adapter, compares the projection with marker-managed remote sections and stable local-to-remote mappings, and renders ordered create/update/link/no-op/refuse actions without mutation (REQ-2, REQ-3, RISK-1, RISK-2, RISK-4) [after: 1.1] `M`

## Phase 2: Confirmed apply and convergence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add one simple mapping file keyed by stable epic/plan IDs and managed-section markers; refuse unmanaged edits, ambiguous adoption, missing targets, or changed mappings rather than overwriting them (REQ-3, REQ-4, RISK-2, RISK-3) [after: 1.2] `M`
- [ ] 2.2 Add operator-confirmed apply through the same `gh` adapter, executing the displayed action set in deterministic order and refreshing state so an immediate second run is a no-op (REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3, RISK-4) [after: 2.1] `M`

## Phase 3: Focused proof and distribution
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add focused mocked adapter tests for projection, dry run, apply confirmation, mapping, markers, conflict refusal, partial failure, and second-run no-op; document an optional operator-owned real smoke without making live credentials required evidence (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 2.2] `M`
- [ ] 3.2 Synchronize plugin/generated copies through existing writers, run focused mocked/installed/generated-drift/validation checks, rebuild the existing evidence receipt, and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `M`
