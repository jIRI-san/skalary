# 4dd933: Cross-plan artifact context [DONE]
<!-- plan-id: 4dd933 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle. -->

<!-- execution-mode: manual -->
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
- Evidence receipt - `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)

## Phase 1: Bounded artifact resolver
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Add one resolver beside `Get-PlanIndex.ps1` that accepts already resolved plan IDs and allowlisted artifact kinds, then uses existing plan inventory, layout resolution, and asset-path resolution to return content plus source metadata (REQ-1, RISK-1, RISK-2) `M`
- [x] 1.2 Enforce canonical plan confinement, regular-file checks, per-artifact and total byte bounds, deterministic ordering, and explicit missing/refused results while treating all returned content as untrusted historical input (REQ-2, RISK-1, RISK-2) [after: 1.1] `M`

## Phase 2: Shared consumer path and provenance
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Integrate `/cip` and `/cep` through the same resolver after index, epic/dependency, or operator selection; record plan ID, artifact kind, path, and relationship in existing `references.md` (REQ-3, REQ-4, RISK-3) [after: 1.2] `M`
- [x] 2.2 Optionally integrate plan-associated `/dr` and `/cr` through that resolver only, recording the same metadata in review scope while leaving review-run v1 unchanged (REQ-3, REQ-4, RISK-3, RISK-4) [after: 2.1] `M`

## Phase 3: Distribution and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Add focused resolver, confinement, byte-bound, missing-artifact, provenance, and installed-consumer tests; synchronize bundled scripts and plugin copies with existing generators (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4) [after: 2.2] `M`
- [x] 3.2 Run focused plan-context, review-consumer, generated-drift, and validation checks; rebuild the existing evidence receipt and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4) [after: 3.1] `M`
