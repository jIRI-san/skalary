# 367e9a: Simple review-to-plan workflow
<!-- plan-id: 367e9a -->
<!-- depends-on: 2aa7ec -->
<!-- cip-stage: dr-round-1 -->
<!-- planning-confirmed: sha256:1bc50f62bec3dde0f712adceb0c4ec9b3e57bc4b3e7c06e265bb1efac10f1edb -->
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

## Phase 1: Measured and proven direct workflow core
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Measure representative model cost, latency, availability, and useful output; approve exact OpenAI routine and Claude terminal/high-risk bindings (REQ-2, REQ-3, RISK-2, RISK-7) @human `M`
  <details><summary>Details</summary>

  **Steps:**
  1. Run the same bounded planning, implementation-judgment, and review fixtures with candidate models available to this Copilot subscription.
  2. Record observed premium-request or credit cost, elapsed latency, availability, and whether each result found the seeded high-impact issue without material false positives.
  3. Compare the OpenAI-first recommendation against at least one Claude independent-review result.
  4. Select exact routine, terminal/high-risk, and availability-fallback bindings; record the observations and rationale in the agent-cost design note and canonical model policy assets without changing confirmed plan criteria.

  **Verify:** observations cover every selected role and the approved table obeys 2-default/5-maximum calls, uses OpenAI for routine work, limits Claude to terminal or concrete high-risk review, and names one replacement fallback.

  **Rollback:** restore the previous model assets; no workflow migration starts until the operator approves replacement bindings.

  </details>
- [x] 1.2 Build the dormant direct report, Git criteria-baseline, native role/stuck-recovery, direct evidence, local review-standards, and retained review-guard paths beside the active workflow (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-12, RISK-2, RISK-3, RISK-4, RISK-6, RISK-10) [after: 1.1] `L`
- [x] 1.3 Prove the dormant core with focused report-shape, path-confinement, hostile-content, secret-redaction, four-file criteria mutation, stuck-recovery, budget-exhaustion, direct-evidence, and terminal-review fixtures (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-12, RISK-2, RISK-3, RISK-4, RISK-6, RISK-7, RISK-10) [after: 1.2] `S`

## Phase 2: Atomic workflow activation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Prepare every CR/DR, `/cep`, `/cip`, `/ci`, autopilot, direct-evidence, and historical-context consumer for the proven direct shapes while the old path remains active (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-12, REQ-16, RISK-1, RISK-2, RISK-3, RISK-4, RISK-6, RISK-8, RISK-10) [after: 1.3] `L`
- [x] 2.2 Activate the direct workflow across all consumers, remove the old producers/schemas/Fleet/generated concerns/receipts/repair paths and stale manifest/docs entries, then commit only after focused residue and installed-consumer checks pass (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-12, REQ-16, RISK-1, RISK-2, RISK-3, RISK-4, RISK-6, RISK-8, RISK-10) [after: 2.1] `L`

## Phase 3: Precise interaction and proportional review
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Make complex questions decision-ready across both hosts and convert active absolute/fuzzy policy language into confirmed invariants or observable conditional rules (REQ-10, REQ-11, RISK-8) [after: 2.2] `L`
- [x] 3.2 Apply the concrete threat-path security rubric and simple-versus-safer operator choice to the retained direct review guards (REQ-12, RISK-2, RISK-6, RISK-8) [after: 3.1] `M`
- [x] 3.3 Add focused decision-question, language-audit, concrete-threat, absent-boundary, and retained-guard fixtures (REQ-10, REQ-11, REQ-12, RISK-2, RISK-6, RISK-8) [after: 3.2] `S`

## Phase 4: Compact AI context and bounded human handoffs
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 4.1 Add conditional finalization compaction for edited AI design notes with semantic preservation, diff review, and operator approval for cross-note merge/delete (REQ-13, RISK-5, RISK-8) [after: 3.3] `M`
- [ ] 4.2 Replace durable harvest state with the `/ci`/autopilot-owned bounded cited `docs/feedback/recent-learning.md` handoff and define `/si` read-time fencing for child `3a4498` (REQ-15, RISK-9) [after: 4.1] `M`
- [ ] 4.3 Publish the complete `docs/operator-guide/README.md`, `planning.md`, `implementation.md`, and `reviews.md` with linked artifact/gate tables and Mermaid flows accumulated alongside earlier behavior changes (REQ-14, RISK-8) [after: 4.2] `M`

## Phase 5: Contract retirement and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Retire or rewrite obsolete architecture contracts and design notes, close the active absolute/fuzzy audit, and reconcile the operator guide with final executable behavior (REQ-10, REQ-11, REQ-12, REQ-13, REQ-14, RISK-5, RISK-6, RISK-8) [after: 4.3] `L`
- [ ] 5.2 Remove remaining stale manifests, generated copies, tests, and historical-adapter dependencies; run focused residue and consumer-install checks (REQ-4, REQ-8, REQ-16, RISK-1, RISK-4) [after: 5.1] `M`
- [ ] 5.3 Run direct plan evidence and affected-plugin checks, perform compaction if design notes changed, write the bounded learning handoff, and execute the single whole-plan terminal CR with a closed clean/findings/incomplete outcome (REQ-1, REQ-2, REQ-3, REQ-6, REQ-7, REQ-8, REQ-9, REQ-12, REQ-13, REQ-14, REQ-15, REQ-16, RISK-1, RISK-2, RISK-4, RISK-5, RISK-6, RISK-7, RISK-9, RISK-10) [after: 5.2] `S`
