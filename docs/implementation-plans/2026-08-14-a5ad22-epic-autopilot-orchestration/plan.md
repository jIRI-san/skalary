# a5ad22: Epic autopilot orchestration
<!-- plan-id: a5ad22 -->
<!-- depends-on: 8a0644, 25aa23, 669ad3, 79cfe1 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
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
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Prerequisites and one-child GitHub slice
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Refuse before mutation unless every declared dependency is done, review-approved, evidence-clean, and ABI/schema digest-compatible; replace the 006-only gate with a general installed dependency preflight, then define the Phase-1 architecture/state/provider/selector/status contracts and sync owning payloads/docs (REQ-1, RISK-1, RISK-2) `M`
- [ ] 1.2 Implement the minimum bounded Git-bundle export/import transport, separate Copilot authentication from repository mutation authority, and add a dormant side-effect-free reconcile command that snapshots one target OID, pins authority, selects one topologically ready child, and reaches a host-mediated GitHub merge handoff (REQ-2, RISK-3, RISK-4) [after: 1.1] `L`
- [ ] 1.3 Prove dependency refusal and the composed one-child bundle path through isolated installed, hostile, exact-limit/one-over, source-poisoned, and non-blindness scenarios while the `/ci` menu and direct `Run` remain disabled; sync payloads/docs (REQ-3, RISK-1, RISK-3) [after: 1.2] `S`

## Phase 2: Crash-safe runtime lifecycle
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Extend the launcher with optional nonce-bound identity, exact fork/base, idempotent launch, managed reattach, remaining timeout, bounded bundle/transcript extraction, canonical image reuse, and crash-retained artifact cleanup; sync launcher payload/docs (REQ-4, RISK-4, RISK-5) [after: 1.3] `L`
- [ ] 2.2 Implement the complete Run/Status/Reset state and exit table, separate counters/epochs, stale-request authorization, deterministic Run recovery, cumulative budgets, domain-owned publication/recovery using shared stateless helpers, and fault seams across every effect boundary (REQ-5, RISK-1, RISK-4, RISK-5) [after: 2.1] `M`
- [ ] 2.3 Prove Windows/Linux installed runtime closure, bundle retention/import, restart/duplicate suppression, exits 124/143/43/44/45/5/unknown, transcript/cache/publication faults, and supplemental Docker smoke; keep `Run` disabled and sync payloads/docs (REQ-6, RISK-4, RISK-6) [after: 2.2] `S`

## Phase 3: GitHub multi-child completion
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Harden GitHub facts, bundle provenance, exact target base, host-mediated expected-old-OID push/PR creation, exact ancestry, baseline import, merge records, authority re-pin, scope authorization, and disagreement stops (REQ-7, RISK-7, RISK-8) [after: 2.3] `L`
- [ ] 3.2 Enforce child path/ref capabilities, trusted executable resolution, bounded bundle/object/blob/commit/path/diff audits, and prove a two-child topological sequence with later/external/unresolvable dependencies, sibling mutation, stale target, squash-only, authority/graph change, and zero retry; sync payloads/docs (REQ-8, RISK-3, RISK-7, RISK-8) [after: 3.1] `L`

## Phase 4: Delivered-outcome coherency
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Build owner-state `epic-delivery@1` over review-run v1 `purpose=design` and `source.kind=rfc`, binding reviewed target OID, intent digest, merge records, and verified receipts; pre-admit/project caps and confine/normalize/scan/fence bytes (REQ-9, RISK-9) [after: 3.2] `M`
- [ ] 4.2 Generate the closed delivery concern family, reserve owner-defined 8/16 fleet budget, dispatch one frozen audit through review-run v1, require complete attendance/disposition, map degraded exit 5, and create only a sealed evidence-only finalization PR from a clean verdict (REQ-10, RISK-9) [after: 4.1] `L`
- [ ] 4.3 Block findings/degradation for corrective work and fresh source; prove envelope, injection, target/source change, fleet one-over, finalization capability/merge, history retention, and no-self-remediation scenarios; sync payloads/docs (REQ-11, RISK-9) [after: 4.2] `S`

## Phase 5: Distribution and lifecycle close
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Converge GitHub and delivery slices, regenerate the epic mirror, activate `Run` only behind `AUTOPILOT_DISABLE_EPIC`, verify all scripts/schemas/agents/scaffolds/dogfood/registry/marketplace/scenario results/design notes/architecture human doc/analyzer/runtime budgets, then run ordinary `/ci` receipt, done-stage, and archival flow (REQ-12, RISK-6, RISK-10) [after: 4.3] `L`
