# 6a629b: Vertical implementation and requirement loop
<!-- plan-id: 6a629b -->
<!-- depends-on: 57cc2c, 863d97 -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
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
- Evolution log — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Interactive vertical checkpoint MVP
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Land the read-only dependency/API/intent admission preflight and its zero-mutation negative fixtures; sync changed CI/CIP payloads, docs, and catalogs in-step (REQ-9, RISK-1) `M`
- [ ] 1.2 Add the shared checkpoint parser/gate, atomic bounded typed Capture writer, and interactive phase-close loop with owned evidence; sync changed CI/CIP payloads, docs, eval registration, and catalogs in-step (REQ-1, REQ-2, REQ-3, REQ-5, REQ-6, REQ-7, RISK-2, RISK-5, RISK-6) [after: 1.1] `L`

## Phase 2: Autonomous parity and durable stops
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Atomically reroute autopilot as the final evidence caller, map scope to launcher `next-phase`/`whole-plan`, and propagate one-phase sandbox/container stops; sync changed payloads, autopilot docs, and catalogs in-step (REQ-4, REQ-6, REQ-7, RISK-2, RISK-3, RISK-4) [after: 1.2] `L`
- [ ] 2.2 Prove mode parity, interruption/resume, state-bound operator continuation, and complete-plan progression beyond MVP (REQ-4, REQ-5, RISK-1, RISK-4) [after: 2.1] `M`

## Phase 3: Distribution, documentation, and final integration
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Prove aggregate source/bundle/dogfood/install/catalog parity, secret-guard availability, and negative drift mutations (REQ-5, REQ-6, RISK-3) [after: 2.2] `L`
- [ ] 3.2 Update all governing design notes and mandatory structural eval registration, then prove the one-per-tree-state final integration gate within platform budgets (REQ-6, REQ-8, RISK-6, RISK-7) [after: 3.1] `M`

## Known Plan Issues

- `RISK-7`: `Get-PlanIndex.ps1` reports the stale active `cda9da` review-scratch folder because it has no `plan.md`. This plan uses only the indexed archived completed `cda9da` authority and does not repair or infer records from scratch state.
