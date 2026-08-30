# 8a0644: Dispatch plan up front
<!-- plan-id: 8a0644 -->
<!-- depends-on: 57cc2c, 6a629b, c21cdc -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-7 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata - defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
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
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Shared dispatch primitive
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min - 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add a small pure dispatch planner that accepts ordered task descriptors, validates ids/dependencies/omissions, and returns selected tasks plus deterministic ready waves of at most four; add focused unit tests and the fleet design note (REQ-1, REQ-2, REQ-8, RISK-1, RISK-4) `M`
- [x] 1.2 Add a run-scoped orchestration adapter that renders the plan before dispatch, launches only planned ready tasks, retries once only on an explicit throttle result, cancels transitive dependents after failure, and renders final attendance/degradation (REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-3) [after: 1.1] `M`

## Phase 2: Planning and implementation skills
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Integrate `/cip` Designer, Requirements Validator, and Judge tasks through the shared plan/pre-view/attendance contract; preserve existing role tools and model selection, and add installed structural coverage (REQ-4, REQ-8, RISK-2, RISK-4, RISK-5) [after: 1.2] `M`
- [ ] 2.2 Integrate `/ci` and autopilot Designer, Validator, Implementor, and Judge tasks through the same contract while preserving their existing execution and promotion boundaries; add installed structural coverage (REQ-5, REQ-8, RISK-2, RISK-4, RISK-5) [after: 2.1] `M`

## Phase 3: Review and epic adapters
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Adapt `/cr` and `/dr` frozen task lists to the shared planner while leaving review-run publication, persistence, and result rendering authoritative; prove the six- and fourteen-task wave shapes and attendance parity (REQ-6, REQ-8, RISK-2, RISK-3, RISK-6) [after: 2.2] `M`
- [ ] 3.2 Publish the generic epic-review conformance shape and local handoff consumed later by plan `25aa23`, without editing that plan or adding another scheduler (REQ-7, REQ-8, RISK-6) [after: 3.1] `S`

## Phase 4: Distribution and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Update source skills, bundled copies, structural evals, registry/catalog outputs, and the relevant customization/plan/review design notes using existing repository generators; do not add activation or migration infrastructure (REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, RISK-5) [after: 3.2] `M`
- [ ] 4.2 Run focused planner/adapter tests, installed-consumer and eval checks, complete repository validation, final CR, and intent/requirement crosscheck (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6) [after: 4.1] `M`
