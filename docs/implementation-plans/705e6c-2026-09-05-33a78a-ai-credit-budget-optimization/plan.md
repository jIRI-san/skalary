# 33a78a: AI credit budget optimization
<!-- plan-id: 33a78a -->
<!-- depends-on: 367e9a -->
<!-- depends-on: 367e9a -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:c4529c5c72052bbc7fb68ef230fd523cb8dd7ea789a4c0d58596e4147498ac8e -->
<!-- epic: 705e6c -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Domain model — [assets/domain.md](assets/domain.md)
- Approved design — [assets/design.md](assets/design.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Review results — advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Budget contract and default-context runtime
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Replace the stale cost note with the dated 180K operating contract, exact model ladder, fallbacks, escalation criteria, and retained simplicity boundaries (REQ-2, REQ-8, REQ-10, RISK-2, RISK-3, RISK-7) `M`
- [x] 1.2 Remove the autopilot context setting and every active `long_context` schema, example, launcher, container, sandbox, and configuration path; set routine autopilot to Luna/medium while retaining explicit model and effort overrides (REQ-1, REQ-2, REQ-4, REQ-9, RISK-1, RISK-4, RISK-7, RISK-10) [after: 1.1] `L`
- [x] 1.3 Add focused model-routing, default-context-only, schema, launcher, and active-residue fixtures without inspecting archived plans (REQ-1, REQ-2, REQ-4, REQ-9, RISK-1, RISK-4, RISK-7) [after: 1.2] `S`

## Phase 2: Cheap-first planning, implementation, and review
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Retune `/cep`, `/cip`, `/ci`, autopilot, CR, and DR to direct-work-first execution, one evidence-triggered combined delegate, a three-call ceiling, and the Luna/Terra/Sol/Opus escalation ladder with no automatic Judge (REQ-2, REQ-3, REQ-4, REQ-5, REQ-10, RISK-1, RISK-2, RISK-7, RISK-9) [after: 1.3] `L`
- [ ] 2.2 Reduce high-frequency `autopilot`, `cep`, `cip`, `ci`, `cr`, `dr`, and `si` entrypoints to at most 4 KiB, three supporting artifacts, a 400-word prompt target, and an 800-word cap by moving rare selected-path detail into installed assets (REQ-3, REQ-7, REQ-9, REQ-10, RISK-5, RISK-8) [after: 2.1] `M`
- [ ] 2.3 Add focused consumer-contract, call-limit, escalation, prompt/artifact budget, skill-size, and unchanged-retained-guard fixtures (REQ-2, REQ-3, REQ-4, REQ-5, REQ-7, REQ-9, REQ-10, RISK-1, RISK-2, RISK-5, RISK-7, RISK-9) [after: 2.2] `S`

## Phase 3: Premium eval cost reduction
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Classify each active waza task as deterministic-gradeable or subjective, switch skill execution to Luna, retain Terra judgment only for subjective behavior, and preserve injection, refusal, and tool-use coverage (REQ-2, REQ-6, REQ-10, RISK-1, RISK-6, RISK-7) [after: 2.3] `L`
- [ ] 3.2 Update waza convention tests, model allowlists, and plugin-focused invocation guidance so no deterministic route triggers premium work and no routine premium path selects Sol, Opus, long context, or a full-repository sweep (REQ-2, REQ-6, REQ-9, REQ-10, RISK-2, RISK-4, RISK-6, RISK-7) [after: 3.1] `M`
- [ ] 3.3 Run structural eval checks plus a no-cost model-availability probe; leave any live premium smoke explicit and operator-initiated rather than making it completion evidence (REQ-6, REQ-8, REQ-10, RISK-3, RISK-6, RISK-7) [after: 3.2] `S`

## Phase 4: Distribution, guidance, and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Synchronize canonical plugin assets into dogfood/registry surfaces and update operator guidance plus the future `a524dc` configuration inventory with the 180K/20K budget, dated pricing links, exact model roles, and explicit escalation path (REQ-1, REQ-2, REQ-7, REQ-8, REQ-9, RISK-3, RISK-4, RISK-8) [after: 3.3] `M`
- [ ] 4.2 Run the smallest focused model, autopilot, direct-workflow, skill-size, eval-convention, operator-guide, and consumer-install checks; prove active long-context residue is zero and retired guards remain intact (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, RISK-1, RISK-4, RISK-5, RISK-6, RISK-8, RISK-10) [after: 4.1] `M`
- [ ] 4.3 Reconcile architecture/design notes with the delivered behavior, run direct evidence, and complete one risk-selected whole-plan CR without an automatic second model or unchanged-scope rerun (REQ-2, REQ-3, REQ-5, REQ-8, REQ-9, REQ-10, RISK-1, RISK-2, RISK-3, RISK-5, RISK-6, RISK-8, RISK-9) [after: 4.2] `S`
