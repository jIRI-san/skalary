# 4dd933: Cross-plan artifact context
<!-- plan-id: 4dd933 -->
<!-- depends-on: 669ad3, ca8ba8 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: phase -->
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
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Sidecar and registry authority
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Add the generic closed sidecar-root table, literal-data parser, exact bundle tuple inventory, and same-change bundle/catalog parity (REQ-1, RISK-6) `L`
- [ ] 1.2 Add core kinds including `PlanContextReceipt`, limits/diagnostic/evidence projection, all five plugin/seven PlanState copies, and paired parity mutations (REQ-1, RISK-3, RISK-6) [after: 1.1] `L`

## Phase 2: Bounded resolver authority
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add ordered discovery, per-operation/platform ceilings, completeness, and one-invocation/resume identity evidence; register heavy tests in-tier now (REQ-2, RISK-1) [after: 1.2] `L`
- [ ] 2.2 Add confined verified-pair admission, shared secret guard, exact/base64 authority, status matrix, bounded diagnostics, and injective projection tests (REQ-3, REQ-4, RISK-2, RISK-3, RISK-4) [after: 2.1] `L`

## Phase 3: Planning provenance
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add the fixed receipt schema/writer with lock order, confinement, timeout, exits, atomic replay/reset, and fault tests; register heavy tests in-tier now (REQ-5, RISK-4, RISK-7) [after: 2.2] `L`
- [ ] 3.2 Integrate `/cip` and `/cep`, sync their plugin in the same change, and prove bounded installed hostile workflows with shared fixtures (REQ-3, REQ-4, REQ-6, RISK-2, RISK-4, RISK-6) [after: 3.1] `L`

## Phase 4: Planning evidence and docs
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Add the CIP/CEP exact required evals and bijective evidence map with one bounded negative-gate run (REQ-9) [after: 3.2] `M`
- [ ] 4.2 Update planning, plugin, eval, gate, customization, architecture-note, index, and README docs; measure the planning slice on both platforms (REQ-10, RISK-8) [after: 4.1] `M`

## Phase 5: V2 context role
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Verify the `ca8ba8` v2 prerequisite, then add the manifest-bound context role, verified-version dispatch, and exact inherited/role/task/aggregate budget arithmetic (REQ-7, RISK-3, RISK-5) [after: 4.2] `L`
- [ ] 5.2 Decode/scan/frame inside Freeze, bind completeness/invocation/dispatch accounting, and prove maximum/refusal/tamper/old-reader cases (REQ-7, REQ-8, RISK-2, RISK-3, RISK-5) [after: 5.1] `L`

## Phase 6: Review lifecycle and consumers
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Extend publish/read/render/list/finalize/repair/cleanup with the complete v1/v2 state and fault matrix; register heavy tests in-tier now (REQ-8, RISK-5) [after: 5.2] `L`
- [ ] 6.2 Integrate plan-associated `/dr` and `/cr`, sync both plugins in the same change, and prove isolated hostile plus unchanged generic modes (REQ-3, REQ-8, RISK-2, RISK-4, RISK-5, RISK-6) [after: 6.1] `L`

## Phase 7: Review evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Add the DR/CR exact required evals and finish one-to-one ordinary/eval evidence ownership (REQ-9) [after: 6.2] `M`
- [ ] 7.2 Run bounded dedicated installed/review lifecycle and required-eval evidence; update suite/runtime metadata from both platforms (REQ-10, RISK-8) [after: 7.1] `M`

## Phase 8: Final contracts and shipped bytes
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 8.1 Reconcile both review contracts/notes and every exact design/index/README owner with the context-role implementation and `9fda0b` sidecar reuse (REQ-10, RISK-5, RISK-6) [after: 7.2] `M`
- [ ] 8.2 Regenerate human architecture, all bundles, dogfood, registry, and marketplace; run the immutable-tree outer delivery gate and publish unchanged Linux/Windows receipts (REQ-10, RISK-6, RISK-8) [after: 8.1] `L`
