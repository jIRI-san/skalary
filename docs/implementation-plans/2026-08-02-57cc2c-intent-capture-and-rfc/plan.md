# 57cc2c: Intent capture and design RFC
<!-- plan-id: 57cc2c -->
<!-- depends-on: 4dd933 -->
<!-- cip-stage: dr-round-3 -->
<!-- epic: bcece1 -->
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
- Domain model — [assets/domain.md](assets/domain.md)
- Approved design — [assets/design.md](assets/design.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Enforced planning-state MVP
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Capture the pre-change Slow baseline; add bounded generic dependency admission, schema distribution, closed Interview Gates vocabulary, canonical installed reader/writer, capability refusal, and focused hostile/recovery tests; converge every touched payload (REQ-1, REQ-8, RISK-1, RISK-2, RISK-3, RISK-5, RISK-6, RISK-7, RISK-8) `M`
- [ ] 1.2 Route `New-Plan.ps1`, `/cep`, and a resumable minimum `/cip` path through `Set-InterviewGates.ps1` for initialization, bounded stdin content, classification, durable correction authority, confirmation, revocation, and approval-source handling; converge every touched payload (REQ-2, REQ-3, REQ-8, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.1] `M`
- [ ] 1.3 Share one lock across gate mutation and lifecycle advancement, enforce enrolled integrity below the floor and at crosschecks, expose `Get-PlanState` diagnostics and repair/version signals, and close Phase 1 Fast/Slow evidence plus payload parity (REQ-2, REQ-8, RISK-2, RISK-5, RISK-6) [after: 1.2] `M`

## Phase 2: Confirmed context and bounded artifacts
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Strengthen `interview-guide.md` with three bounded checkpoints, prose-gate supersession, durable correction authorization, resume semantics, and deletion-resistant Tier-1 cases; converge every touched payload (REQ-3, REQ-8, RISK-3) [after: 1.3] `M`
- [ ] 2.2 Complete conditional domain elicitation and single-sourced `domain-template.md` sections with objective classification state plus operator judgment, reader/writer hostile matrices, and payload convergence (REQ-4, REQ-8, RISK-2, RISK-3, RISK-5) [after: 2.1] `M`
- [ ] 2.3 Complete provisional-outline RFC classification, `design-template.md`, final-plan mechanical recheck, explicit invalidation before design-affecting decision/risk edits, interactive approval/revocation, DR handoff, and payload convergence (REQ-5, REQ-8, RISK-3, RISK-4) [after: 2.2] `M`

## Phase 3: Vertical planning and execution continuity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add objective parsed-plan routing invariants to `drafting-guide.md` and stable Tier-1 cases while leaving phase usability to operator/DR judgment; converge every touched payload (REQ-6, REQ-8, RISK-5) [after: 2.3] `M`
- [ ] 3.2 Route `/ci`, `/dr`, and autopilot through the installed reader before mutation and at crosschecks; keep intent per step, bundle autopilot's closure, preserve closed exit-42 reason/progress records, and converge every touched payload (REQ-7, REQ-8, RISK-3, RISK-4, RISK-8) [after: 3.1] `M`
- [ ] 3.3 Add a provisional Interview Gates architecture contract; update plan-workflow, customization, registry, autopilot, review, and eval notes; delete promoted exploration files and repair links/indexes; prove generation reconvergence; and build the existing commit-bound evidence receipt after final Fast/Slow/analyzer/eval/install gates (REQ-8, RISK-6) [after: 3.2] `M`

## Known Plan Issues

- **Dependency-gate bootstrap:** current `/ci` and autopilot cannot enforce arbitrary `depends-on` edges until step 1.1 lands, but this plan already depends on `4dd933`. Do not invoke `/ci 57cc2c` until `4dd933` and its transitive chain are complete; the first implementation preflight must verify that condition before mutation. This one-time bootstrap cannot be made self-enforcing by code introduced inside the blocked plan.
- **Enrollment dual deletion:** deleting both `<!-- interview-gates: required -->` and `assets/interview-gates.json` is indistinguishable from a grandfathered current tree. The operator accepted git/review detection instead of a permanent legacy-plan baseline.
- **Out-of-band governed edits:** direct edits or merges that bypass `Set-InterviewGates.ps1` cannot reset confirmation without digest binding. The operator chose transactional invalidation rather than content digests; workflow instructions and review must reject bypasses.
- **Reviewer-enforced operator identity:** `approvalSource: interactive-operator` proves the workflow received the closed interactive response, not cryptographic human identity. This matches the repository's existing reviewer-enforced trust model.
