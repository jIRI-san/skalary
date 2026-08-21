# 8a0644: Dispatch plan up front
<!-- plan-id: 8a0644 -->
<!-- depends-on: 57cc2c, 6a629b, c21cdc, 34088e -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
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

## Phase 1: Published contract and deterministic plan
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min - 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Publish `ARCH-Fleet-Dispatch-V1`, note/index/human doc, fleet design note/index, runtime store/gitignore/scaffold ownership, limits/role descriptors, self-contained schemas, exact bundle grammar, secret-guard extraction, and owner/parity/security mutations; converge plugin bundles, versions, registry, marketplace, and governing docs (REQ-1, REQ-10, REQ-11, REQ-12, RISK-1, RISK-7, RISK-8, RISK-12) `L`
- [ ] 1.2 Implement deterministic conservation, dependency planning, capability/path normalization, schema/descriptor deep parity, bounded maximum fixtures, mutation table, focused Fast tests, and plan-workflow/plugin-registry docs; converge generated outputs (REQ-1, REQ-2, REQ-10, REQ-11, REQ-12, RISK-1, RISK-4, RISK-5, RISK-8) [after: 1.1] `L`

## Phase 2: Recoverable store and admission
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Implement the engine-derived store, closed command status/exits, atomic state machine, locks, fixed leaves, verified readers, capture dedup/compaction, zero-summary close, list/abandon/remove, recovery epochs, cleanup tombstones, required platform confinement, and lifecycle docs/tests; converge generated outputs (REQ-3, REQ-5, REQ-10, REQ-11, RISK-7, RISK-10, RISK-13) [after: 1.2] `L`
- [ ] 2.2 Implement lease admission, work-conserving ready order, fake clock, persisted throttle wait/retry, dependency cancellation, host telemetry provenance, complete rendering, maximum lifecycle/write/resource recipes, suite classification, and admission docs/tests; converge generated outputs (REQ-4, REQ-5, REQ-10, REQ-11, RISK-2, RISK-3, RISK-4, RISK-10, RISK-13, RISK-15) [after: 2.1] `L`

## Phase 3: Planning fleet
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add hand-authored CIP Designer, Requirements Validator, and Judge agents, allowlist role keys, closed data-only outputs, empty Git receipts, installed mappings, exact eval ID, adversarial fixtures, and customization docs; converge generated outputs (REQ-6, REQ-10, REQ-11, RISK-5, RISK-7, RISK-8) [after: 2.2] `M`
- [ ] 3.2 Integrate post-interview CIP Plan/pre-view/admission/result/capture with 4/8 and 32-step draft refusal, failure/rerun policy, poisoned installed lifecycle/blindness controls, drafting/DR gate, phase-local evidence, and plan-workflow docs; converge generated outputs (REQ-4, REQ-5, REQ-6, REQ-11, REQ-12, RISK-2, RISK-4, RISK-8, RISK-9, RISK-14, RISK-16) [after: 3.1] `L`

## Phase 4: Isolated implementation fleet
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Add hand-authored CI roles, dormant autopilot integration, disposable-worktree create/audit/promote/quarantine scripts, bounded Git receipts, allowlist role keys, installed mappings, exact eval ID, path/late-result fixtures, and autopilot/plan docs; converge generated outputs (REQ-7, REQ-10, REQ-11, RISK-5, RISK-7, RISK-8, RISK-17, RISK-18) [after: 3.2] `L`
- [ ] 4.2 Integrate CI/autopilot step lifecycle with 4/8 and 128/256 persisted budgets, intent/requirement inputs, failure/recovery policy, isolated promotion, Judge-before-CR, poisoned installed lifecycle, dormant activation proof, phase-local evidence, and docs; converge generated outputs (REQ-4, REQ-5, REQ-7, REQ-11, REQ-12, RISK-2, RISK-4, RISK-5, RISK-8, RISK-9, RISK-14, RISK-16, RISK-17, RISK-18) [after: 4.1] `L`

## Phase 5: Authoritative review adapters
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Add `ReviewFleetAdapter.psm1`, verified frozen-slot/budget conversion, v1 outcome/diagnostic mapping, pre-dispatch compensation, zero-summary close, exact adapter tests, and review contract/design docs; converge generated outputs (REQ-4, REQ-5, REQ-8, REQ-10, REQ-11, REQ-12, RISK-2, RISK-3, RISK-6, RISK-8) [after: 4.2] `L`
- [ ] 5.2 Integrate CR and DR independently through Freeze, fleet pre-view/admission, Publish, both authoritative views, exact eval IDs, poisoned installed lifecycle/blindness controls, throttle/finalization evidence, and updated dispatch/collation docs; converge generated outputs (REQ-4, REQ-5, REQ-8, REQ-11, REQ-12, RISK-2, RISK-3, RISK-6, RISK-8) [after: 5.1] `L`

## Phase 6: Epic adapter handoff
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Add the generic epic-shaped conformance fixture, activation-owner contract, resolver evidence, and update `25aa23` handoff assets plus plan-workflow docs without a retirement guard; converge generated outputs (REQ-9, REQ-11, REQ-12, RISK-6, RISK-8, RISK-11) [after: 5.2] `M`

## Phase 7: Activation and integration closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Run exact required structural evals, installed blindness matrix, mandatory Linux/Windows maximum/confinement receipts, suite-budget gates, mutation matrix, bundle/catalog parity, then atomically activate CI/autopilot fleet cadence and sync dogfood/catalogs/docs (REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, RISK-1, RISK-2, RISK-5, RISK-7, RISK-8, RISK-12, RISK-13, RISK-14, RISK-17, RISK-18) [after: 6.1] `L`
- [ ] 7.2 Run complete repository validation, final CR, generated architecture/doc freshness, cleanup/incomplete-run inspection, exact index-error evidence, and intent/requirement crosscheck without claiming provider-global enforcement (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11, RISK-12, RISK-13, RISK-14, RISK-15, RISK-16, RISK-17, RISK-18) [after: 7.1] `L`

## Finalization

- [ ] 8.1 Rebuild the final evidence receipt, confirm every typed marker and complete project gate is green, set the lifecycle stage to done, and archive only after the operator intent and all twelve requirements remain satisfied (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12) [after: 7.2] `M`

## Known Plan Issues

Round 3 exhausted the default review limit with blocking residuals. Implementation must not begin while any Critical or High item remains unresolved.

- **KPI-1 (Critical):** Move activation to a final separate step and run active-state gates afterwards.
- **KPI-2 (Critical):** Give capture compaction one script owner and record dropped count plus retained range.
- **KPI-3 (Critical):** Assign Dedicated platform evidence a blocking Linux/Windows workflow, runner, gate id, and inventory row.
- **KPI-4 (Critical):** Replace linked-worktree write isolation with an isolated clone under sandbox/enforcement; retain commit audit for promotion.
- **KPI-5 (Critical):** Publish a runtime ABI table naming every fixed path, generation, schema, reader, and single writer.
- **KPI-6 (Critical):** Bound quarantined implementation environments by root/count/bytes/age and add list/remove/backpressure behavior.
- **KPI-7 (Critical):** Regenerate or remove duplicate requirement/risk step-map columns so they equal plan annotations.
- **KPI-8 (Critical):** Replace RISK-14's superseded `64/128` budget with the accepted `128/256` authority.
- **KPI-9 (Critical):** Add idempotent `Recover`/`AdvanceEpoch`; reserve `AbandonRun` for terminal abandonment.
- **KPI-10 (High):** Define the autopilot four-role host adapter, model translation, correlation, and restart behavior.
- **KPI-11 (High):** Bound cumulative nested CR logical calls, attempts, retry wait, and unreconciled work.
- **KPI-12 (High):** Run destructive store/removal/promotion tests only in disposable repository fixtures.
- **KPI-13 (High):** Assign exact file/suite owners to limits, rendering, CEP, and architecture evidence.
- **KPI-14 (High):** Make role handoffs immutable generations or require a reader that retains exact verified bytes.
- **KPI-15 (High):** Add fleet JSON Schema keyword inventory and runtime host-capability gate.
- **KPI-16 (High):** Define rerun charging/reservation so a 32-step plan has deterministic recovery behavior.
- **KPI-17 (High):** Extend canonical owner-local plugin probe descriptors for every installed fleet entrypoint.
- **KPI-18 (High):** Add phase-owned typed markers that can pass before later phases exist.
- **KPI-19 (High):** Add a plan-scoped atomic budget ledger that survives per-run cleanup.
- **KPI-20 (High):** Define post-dispatch review recovery: preserve observed outcomes, map abandoned slots, quarantine late results, Publish once.
- **KPI-21 (High):** Reject Git object modes `120000` and `160000` during promotion and prove main-tree immutability.
- **KPI-22 (High):** Bound `ListIncomplete` with stable cursors, page limits, total-run limits, and N/N+1 evidence.
- **KPI-23 (High):** Anchor fleet state to the orchestrating root and refuse isolated-environment-local stores.
- **KPI-24 (High):** Define satisfiable cumulative-write accounting and derive its N/N+1 limit.
- **KPI-25 (High):** Correct frozen-review wording: fleet supplies candidate input and consumes verified review-run authority.
- **KPI-26 (High):** Persist, charge, and render host calls whose terminal result remains unreconciled.
- **KPI-27 (Medium):** Enforce a symmetric reader/writer capability-conflict matrix.
- **KPI-28 (Medium):** Set Git receipt fixture size, time/memory ceiling, suite owner, and tree-scan mutation.
- **KPI-29 (Medium):** Persist transition/lease age and document incomplete-run recovery.
- **KPI-30 (Medium):** Define the 240-second retry-wait scope and render projected/consumed wait.
- **KPI-31 (Medium):** Add review adapter capacity refusal at N/N+1 with exact exit and diagnostic.
- **KPI-32 (Medium):** Add untrusted-data agent stanzas and adversarial directive/tool/verdict tests.
- **KPI-33 (Medium):** Update all owning review/eval/security docs in the Phase 1 secret-guard change.
- **KPI-34 (Medium):** Publish the CEP activation handoff here; do not edit dependent plan `25aa23`.
- **KPI-35 (Medium):** Add a mutation harness that applies each row and requires exactly the named test/diagnostic.
- **KPI-36 (Medium):** Release the store lock across `notBefore` waits and test concurrent Admit/ListIncomplete.
- **KPI-37 (Medium):** Register cadence limits in the descriptor or prove their tested derivation.
