# 25aa23: Epic coherency review
<!-- plan-id: 25aa23 -->
<!-- depends-on: 8a0644, 79cfe1 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:none; npm:none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Evolution log — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Dormant epic review authority
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Update review-run contract JSON/note/index and owning plan/review/customization/epic-coherency notes first, then add bounded RFC/state schemas and focused failing fixtures for asset resolution, trust encoding, pre-write scans, independent digest truth, cycle-policy reuse, lifecycle/reconciliation, locks, terminal receipts, gitignore, and legacy parity (REQ-1, REQ-3, REQ-4, REQ-7, RISK-2, RISK-5, RISK-8, RISK-9, RISK-11, RISK-12, RISK-13) `L`
- [ ] 1.2 Implement `Resolve-EpicAssetPath`, deterministic crash-safe RFC writing, epic-associated v1 review/finalization/discovery, shared cycle policy, atomic bounded state/projection, and UUID-scoped cleanup as dormant APIs; synchronize bundled runtime/approvals and prove installed legacy consumers unchanged (REQ-1, REQ-3, REQ-4, REQ-7, RISK-2, RISK-4, RISK-5, RISK-7, RISK-8, RISK-9, RISK-11, RISK-12, RISK-13) [after: 1.1] `L`

## Phase 2: Generated concern family and fleet mapping
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Update concern-authoring/fleet/customization contracts first, then version registry/schema/template/inventory as `review-concerns@2`, preserve CR/DR generation/provenance, and add four closed no-tool CEP concerns with migration, hostile-input, and family-refusal evidence (REQ-2, REQ-5, REQ-7, RISK-5, RISK-10, RISK-11) [after: 1.2] `L`
- [ ] 2.2 Generate/distribute CEP concerns and implement exact frozen-slot-to-REQ-9 mapping with work-conserving admission, typed fault seams, bounded inert projections, finalization matrix verification, blocked malformed/degraded publication, and dependency completion gates; keep `/cep` dormant (REQ-2, REQ-3, REQ-5, REQ-7, RISK-1, RISK-3, RISK-7, RISK-10, RISK-11, RISK-14) [after: 2.1] `L`

## Phase 3: Atomic `/cep` activation and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Update `/cep` contract/guidance and implement dormant orchestration plus `Sync-EpicDecomposition.ps1` composition, including terminal operation transitions, write-ahead ownership, existing-child edge refusal, safe repair/rollback, visible approved pointer, and installed end-to-end tests; do not make the skill call the new flow yet (REQ-1, REQ-2, REQ-4, REQ-5, REQ-6, REQ-7, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-9, RISK-11, RISK-12, RISK-13, RISK-14) [after: 2.2] `L`
- [ ] 3.2 Regenerate human architecture and all concern/script/schema/dogfood/catalog copies; close installed structural evals, dependency gates, focused budgeted matrices, suite metadata, Fast, Slow, repository validation, and final CR, then activate `/cep` only after every preceding check is green (REQ-7, RISK-1, RISK-7, RISK-10) [after: 3.1] `L`
