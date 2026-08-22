# 34088e: Consumer install correctness
<!-- plan-id: 34088e -->
<!-- depends-on: cda9da -->
<!-- cip-stage: drafted -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 12 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:none; npm:none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Design-review evolution — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Production-installed consumer MVP and scanner migration
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Extract one shared foreign-consumer snapshot/mutation-copy substrate around the production installer; migrate or explicitly delimit existing review/retirement adapters; confine manifest sources, index resolved fixture roots before cleanup, add parent/reparse guards, and create `test:ConsumerInstall.ProductionFixtureAndInventory` with mapping/hash/root mutations (REQ-1, RISK-1, RISK-4) `L`
- [ ] 1.2 Add scanner enumeration mode rooted in the closed reference grammar, one indexed traversal, deterministic violation records, and scaling budget; enumerate every newly visible reference, record disposition in `assets/decisions/runtime-reference-migration.md`, update the install-confinement architecture note/contract and human doc, and add `test:ConsumerInstall.RuntimeReferenceEnumeration` with seeded violations in every root (REQ-2, REQ-9, RISK-2, RISK-9, RISK-10) [after: 1.1] `L`
- [ ] 1.3 Resolve every enumerated violation, enable enforcement, retire/update the scanner exploration and indexes, then deliver an end-to-end installed MVP with one script-heavy and one scaffold-owning plugin; use read canaries plus payload-load sentinels and record the first scanner/probe timing in `test:ConsumerInstall.RuntimeReferenceEnforcement` (REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-3, RISK-10) [after: 1.2] `L`

## Phase 2: Complete active-plugin and scaffold matrix
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add owner-local probe descriptors plus `schemas/consumer/consumer-probe-{descriptor,run}.schema.json`; implement the harness as at most one deny-by-default child process per active plugin with a 30-second deadline, controlled environment, network/credential/read canaries, process-tree cleanup, failed-root index, and bounded terminal report; add `test:ConsumerInstall.ProbeDescriptorAndAttendance` (REQ-1, REQ-3, REQ-8, RISK-1, RISK-3, RISK-11) [after: 1.3] `L`
- [ ] 2.2 Execute the complete manifest-derived matrix with planned/launched/terminal equality and zero skips; accept preflight refusal only after payload-load proof, corrupt one exercised asset per probe class, scan all channels for secret sentinels, and add `test:ConsumerInstall.ActivePluginProbeMatrix` (REQ-3, REQ-8, RISK-1, RISK-3, RISK-7, RISK-8, RISK-11) [after: 2.1] `L`
- [ ] 2.3 Execute every declared first-use scaffold owner; distinguish literal from parameterized contracts and add `test:ConsumerInstall.FirstUseScaffoldLifecycle` for starter bytes, idempotence, hostile values, reparse ancestors, parent replacement, modified targets, interruption, cleanup, and retry with unavailable link creation treated as non-pass (REQ-2, REQ-4, RISK-4) [after: 2.1] `L`
- [ ] 2.4 Measure scanner and full probe costs on the current tree. Enforce 10-second scanner, 30-second Linux, and 60-second Windows added-runtime allocations in `test:ConsumerInstall.RuntimeAndDiagnosticBudget`; optimize shared immutable setup once, and if either allocation still misses, add a named blocking integration-tier inventory/workflow/budget before proceeding without dropping probes or raising the existing ceiling (REQ-8, RISK-8, RISK-11) [after: 2.2, 2.3] `L`

## Phase 3: Owner-local workflow-limit parity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add discoverable `skalary/workflow-limits@1` owner descriptors and `scripts/skalary/PlanWorkflowLimits.psd1`; migrate PlanState/Test-Plan, active templates/guides, and every bundled consumer while classifying historical plans/transcripts as provenance; add owner/consumer red mutations and actionable diagnostics in `test:WorkflowLimits.PlanOwnerParity` (REQ-6, RISK-5, RISK-9) [after: 1.3] `L`
- [ ] 3.2 Register `schemas/review/review-limits.schema.json` as the installed review authority; update CR/DR guides, collation inputs, schema copies, `review-reporting.design.md`, and compatibility fixtures without changing or retroactively invalidating `skalary/review-run@1`; add `test:WorkflowLimits.ReviewOwnerParity` with both-direction mutations and installed-authority clamping (REQ-6, RISK-5, RISK-9) [after: 3.1] `L`
- [ ] 3.3 Implement the generic owner-descriptor discovery/refusal path and add `test:WorkflowLimits.FleetConsumerHandoff` plus `test:Epic.WorkflowLimitsDependencyState`; verify the script-owned `8a0644 -> 34088e` edge, both mirrors, receiving-side requirement/risk, synthetic scheduler owner, copied-cap refusal, idempotent replay, and marker/mirror rollback (REQ-7, RISK-5, RISK-6) [after: 3.2] `M`

## Phase 4: Consumer lifecycle and distribution proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 From `cda9da`'s immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/`, invoke only its delivered production reconciler and add `test:ConsumerInstall.RetirementTransition` for previous-generation same-source cleanup, foreign-source refusal, modified residue/degraded receipt, bounded secret-free diagnosis, crash-resume outcome, and idempotent retry; do not duplicate tombstone, inventory, journal, or legacy-policy tests (REQ-5, RISK-4, RISK-7) [after: 2.3] `L`
- [ ] 4.2 Converge affected bundles, dogfood, manifests/versions, README, marketplace, registry, suite inventory/profile, structural eval inventory, plugin-registry/plan-workflow/review-reporting/CI-gates design notes, architecture note/contract, and generated human doc; add detect-only `test:ConsumerInstall.DistributionAndAttestation` and prove it leaves the tree unchanged (REQ-9, RISK-8, RISK-9) [after: 2.4, 3.3, 4.1] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 5.1 Review the installed-surface inventory, source/read boundary, scaffold confinement, retirement transition, owner-local limit bindings, fleet handoff, diagnostics, and distribution proof; push the final candidate and require fresh tree-bound Linux/Windows CI suite, structural-eval, drift, and probe receipts before archival (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11) @human [after: 4.2] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `@cr` over the consumer fixture, runtime-reference scanner, probe matrix, scaffold lifecycle, limit owners/parity tests, installer lifecycle fixtures, generated distribution, and updated design notes.
  2. Triage every finding. Return blocking findings to the owning phase and preserve the published review artifact.
     3. Push the exact final candidate and wait for both supported CI legs. Record the run IDs, tree digest, suite receipt, structural-eval attestation, drift attestation, and consumer-probe report from each leg.
     4. Approve only when every active plugin has a terminal installed probe with zero skips, read canaries remain untriggered, hostile scaffold and retirement-transition cases fail before unsafe mutation, both-direction limit mutations turn the parity gate red, and both CI legs match the final tree within their configured ceilings.

     **Verify:** `review:cr` is recorded; every required marker in `assets/evidence.md` is `✓`; active plugin/probe sets are equal with zero skips; both current-tree CI receipt sets are recorded and valid; all detect-only drift gates pass without mutation; and the worktree is clean.

  **Rollback:** Before archival, mark the affected step `[~]`, remove approval, and repair the owner or consumer fixture. After release, repair forward with higher plugin versions; do not downgrade installed consumers or remove source-bound retirement records.

  </details>
