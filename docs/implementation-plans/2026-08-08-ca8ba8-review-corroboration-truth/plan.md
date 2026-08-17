# ca8ba8: Review corroboration truth
<!-- plan-id: ca8ba8 -->
<!-- depends-on: c21cdc -->
<!-- epic: 33b1f9 -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
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

## Phase 1: Versioned contracts, policy, and immutable v1 baseline
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Pin v1 inventory; add all named v2 schemas including limits/receipt/status, exact role budgets, version-map precedence and pinned policy digest, content trust, draft architecture contract/index/human doc, and design notes; synchronize outputs and close schema/version markers (REQ-1, REQ-4, REQ-5, REQ-7, REQ-8, REQ-9, REQ-10, RISK-3, RISK-4, RISK-5, RISK-7, RISK-12) `L`
- [ ] 1.2 Define exactly-two-model ASCII policy@1 with 16,384 ceiling and schema-derived shingle/memory bounds; test direct 16,385 gate, framing, direction controls, descriptor digest/missing policy, forged fields, limits parity, and v1 immutability; update docs, synchronize outputs, and close policy evidence (REQ-1, REQ-2, REQ-3, REQ-10, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.1] `L`

## Phase 2: Bounded corroboration and elevation engine
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add isolated v2 scoring over shared parity-pinned primitives: precompute bounded sets, release them per group, reject count overflow before scoring, derive group/pair commitments and derived-only witnesses, neutralize rendered direction controls, and apply raw/effective severity plus closed `needs-review`; update docs/sync outputs (REQ-2, REQ-3, REQ-4, REQ-5, REQ-7, REQ-10, RISK-1, RISK-2, RISK-4, RISK-5, RISK-6, RISK-9) [after: 1.2] `L`
- [ ] 2.2 Extend reference/Fast policy-elevation suites and the Slow maximum-group worker for reachable 16,384, pure-gate 16,385, bounded shingle memory, echo/verdict refusal, two-model enforcement, control rendering, and v1 parity; synchronize outputs and close projection/elevation evidence (REQ-2, REQ-3, REQ-4, REQ-5, REQ-7, REQ-10, RISK-1, RISK-2, RISK-4, RISK-6, RISK-7, RISK-9) [after: 2.1] `L`

## Phase 3: Reader-first lifecycle, admission, and compact evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Implement dual structured/view/status readers, exact-policy frozen completion, replay, pre-write all-field secret scan and rejected-input removal, caller-approval refusal, finalization/cleanup repair, and receipt@2 diagnosis floor while writers remain v1; update docs/sync outputs (REQ-5, REQ-6, REQ-8, REQ-9, REQ-10, RISK-3, RISK-4, RISK-7, RISK-9, RISK-11, RISK-12) [after: 2.2] `L`
- [ ] 3.2 Implement admission@2 with offending group/role/bytes/limit/guidance, deterministic whole-group children/rollup, permanent candidate/unpartitionable refusal, every role/summary/receipt overflow, and aggregate 16-child cost measurement; synchronize outputs and close lifecycle/admission/retained-verdict evidence (REQ-6, REQ-7, REQ-8, REQ-10, RISK-2, RISK-3, RISK-4, RISK-7, RISK-10, RISK-11, RISK-12) [after: 3.1] `L`

## Phase 4: Truthful views and v2 writer activation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Render structured/status/summary/full/rollup corroboration, raw/effective severity, `needs-review`, and derived-only witnesses through v2 views/receipt/reference/goldens; preserve v1 bytes, update docs/sync outputs, and close rendering/retained evidence including direction-control and diagnosis-floor cases (REQ-4, REQ-5, REQ-8, REQ-10, RISK-4, RISK-5, RISK-7, RISK-9) [after: 3.2] `M`
- [ ] 4.2 Atomically change the engine version-map default so CR/DR new freeze+publish use v2, expose active writer/policy capability, add verification and revert-activation-plus-resync runbook, update installed fixtures/guides/docs, synchronize outputs, and close staged activation/consumer evidence (REQ-6, REQ-8, REQ-9, REQ-10, RISK-3, RISK-4, RISK-11, RISK-12) [after: 4.1] `L`

## Phase 5: Architecture, documentation, and integration evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Reconcile the already-updated v1/v2 architecture contracts, index/human doc, review/plan design notes, guides, and cross-plan error record; run deterministic content/drift checks and close documentation/distribution evidence (REQ-2, REQ-9, REQ-10, RISK-5, RISK-8, RISK-11) [after: 4.2] `M`
- [ ] 5.2 Run PSScriptAnalyzer, complete Fast/Slow suites, named structural eval execution, and repository validation; require Linux and Windows CI receipts for the aggregate parent budget before finalization, leaving an unavailable platform marker honestly unrun without loosening ceilings (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, RISK-2, RISK-3, RISK-4, RISK-7) [after: 5.1] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] X.Y Finalization gate: run the plan crosscheck, retain the verified review/evidence pair, and archive only with an all-green receipt (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10) [after: 5.2] `S`

## Known Plan Issues

- Policy@1 intentionally uses ASCII lexical tokens and can miss non-ASCII similarity or semantic paraphrases. Reports state only that no suspicious policy@1 similarity was observed; they never claim served-model independence.
- A hostile reviewer can echo another output and force `needs-review`, suppressing otherwise valid elevation. This fail-closed denial of confidence is accepted: findings remain visible, raw severity is preserved, and suspicion can never approve or elevate.
