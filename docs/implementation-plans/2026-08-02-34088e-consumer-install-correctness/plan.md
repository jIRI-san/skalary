# 34088e: Consumer install correctness
<!-- plan-id: 34088e -->
<!-- depends-on: cda9da -->
<!-- cip-stage: done -->
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
- [ ] 1.2 Add scanner enumeration mode rooted in the closed reference grammar and machine-owned `tools/runtime-reference-policy.psd1` limits (10,000 files, 64 MiB aggregate UTF-8 input, 100,000 references, 256 persistent exclusions); use one indexed traversal, deterministic violation records, boundary/plus-one and 1x/2x scaling fixtures; enumerate every newly visible reference, record migration rationale only in `assets/decisions/runtime-reference-migration.md`, update the install-confinement architecture note/contract and human doc, and add `test:ConsumerInstall.RuntimeReferenceEnumeration` with seeded violations in every root (REQ-2, REQ-9, RISK-2, RISK-9, RISK-10) [after: 1.1] `L`
- [ ] 1.3 Resolve every enumerated violation, move any persistent exclusion into the scanner-owned policy, prove the migration inventory has zero unresolved entries, enable enforcement in the existing validation host, retire the migration asset and scanner exploration, then deliver an end-to-end installed MVP with one script-heavy and one scaffold-owning plugin; use read canaries plus payload-load sentinels and record diagnostic-only early timing in `test:ConsumerInstall.RuntimeReferenceEnforcement` (REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-3, RISK-10) [after: 1.2] `L`

## Phase 2: Complete active-plugin and scaffold matrix
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add owner-local probe descriptors plus `schemas/consumer/consumer-probe-{descriptor,run}.schema.json` and machine-owned `tools/consumer-probe-limits.psd1`; schema/Test-Registry must bind each direct entrypoint to the declaring plugin's own confined `files[].dest`, bind every scaffold one-to-one to an installed trigger and closed parameter cases, and reject shell text or escaping arguments. Implement deterministic ordinal waves of at most four deny-by-default child processes, each capped at 30 seconds, with an allowlisted environment, isolated profile roots, removed credential variables, network-capability preflight, canaries, process-tree cleanup, confined/root-identity-checked failed-root reclaim, and bounded terminal report; add `test:ConsumerInstall.ProbeDescriptorAndAttendance` (REQ-1, REQ-3, REQ-8, RISK-1, RISK-3, RISK-4, RISK-11) [after: 1.3] `L`
- [ ] 2.2 Execute the complete manifest-derived matrix with planned/launched/terminal equality and zero skips; on aggregate expiry mark running and unlaunched probes terminal `timed-out`. Accept preflight refusal only after payload-load proof; require supported CI hosts to pass link/network capability preflights, persist and startup-reclaim any tagged network-isolation state before launch, corrupt one exercised asset per probe/scaffold class, test entrypoint and argument escape separately, scan all channels for secret sentinels, and add `test:ConsumerInstall.ActivePluginProbeMatrix` (REQ-3, REQ-4, REQ-8, RISK-1, RISK-3, RISK-4, RISK-7, RISK-8, RISK-11) [after: 2.1] `L`
- [ ] 2.3 Execute every scaffold-to-probe binding; distinguish literal from parameterized contracts and add `test:ConsumerInstall.FirstUseScaffoldLifecycle` for starter bytes, idempotence, hostile values, reparse ancestors, parent replacement, modified targets, interruption, cleanup, retry, and false capability claims. Record `available|unavailable|failed`; anything except `available` plus executed cases leaves the marker unrun/failed and blocks finalization (REQ-2, REQ-4, RISK-4) [after: 2.1] `L`
- [ ] 2.4 Measure the full scanner in the existing `validate.ps1` host and the probe coordinator under ordinary 30-second Linux/60-second Windows aggregate allocations from `tools/consumer-probe-limits.psd1`; per-child timeout is the lesser of 30 seconds and remaining aggregate time. Push a measurement checkpoint and require tree-bound receipts from both CI platforms before selecting `met|tier-required`; when required, use blocking 120-second Linux/240-second Windows tier allocations. Rename the existing `gate:review-consumer-install` row/script in place and update its workflow invocation, inventory, `ci-gates.design.md`, and `review-reporting.design.md` atomically; optimize shared immutable setup once without dropping probes or raising an allocation. Add `test:ConsumerInstall.RuntimeAndDiagnosticBudget` with peak-concurrency, ordinary/tier passing, all-hang, and stale network-state reclaim cases (REQ-8, RISK-8, RISK-9, RISK-11) [after: 2.2, 2.3] `L`

## Phase 3: Owner-local workflow-limit parity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add discoverable `skalary/workflow-limits@1` owner descriptors and `scripts/skalary/PlanWorkflowLimits.psd1`; migrate PlanState/Test-Plan, active templates/guides, and every bundled consumer while classifying historical plans/transcripts as provenance; scan allowlisted active roots (`.github`, `plugins`, `scripts/skalary`, `schemas`, `tools`, and `docs/design-notes`) and require every owner-value literal to match an owner or descriptor registration token, excluding implementation plans, fixtures, goldens, and generated catalogs. Add both-direction owner/consumer red mutations and actionable diagnostics in `test:WorkflowLimits.PlanOwnerParity`; this step owns bundle/registry regeneration after descriptor changes (REQ-6, RISK-5, RISK-9) [after: 2.4] `L`
- [ ] 3.2 Register `schemas/review/review-limits.schema.json` as the installed review authority with `x-skalary-limits.reviewInvocationBudget` as the non-validating concrete owner; update CR/DR guides, collation inputs, schema copies, `review-reporting.design.md`, and compatibility fixtures without changing `$defs`, validation semantics, or retroactively invalidating `skalary/review-run@1`; add `test:WorkflowLimits.ReviewOwnerParity` with both-direction mutations and installed-authority clamping (REQ-6, RISK-5, RISK-9) [after: 3.1] `L`
- [ ] 3.3 Implement the generic owner-descriptor discovery/refusal path and add `test:WorkflowLimits.FleetConsumerHandoff` plus `test:Epic.WorkflowLimitsDependencyState`; verify the script-owned `8a0644 -> 34088e` edge, both mirrors, receiving-side requirement/risk, synthetic scheduler owner, copied-cap refusal, idempotent replay, and marker/mirror rollback (REQ-7, RISK-5, RISK-6) [after: 3.2] `M`

## Phase 4: Consumer lifecycle and distribution proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 From `cda9da`'s immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/`, invoke only its delivered production reconciler and prove the post-transition installed entrypoints/probes see same-source removal, foreign-source refusal, and modified-residue state through `test:ConsumerInstall.RetirementTransition`; cite `test:PluginRetirement.ReconciliationStateMatrix`, `test:PluginRetirement.SourceIdentityAndSecretGuard`, `test:PluginRetirement.TransactionRecovery`, and `test:PluginRetirement.ReaderRemovalAndResultContract` as upstream authority rather than rebuilding their outcome/fault matrix (REQ-5, RISK-4, RISK-7) [after: 2.3] `L`
- [ ] 4.2 Converge affected bundles, dogfood, manifests/versions, README, marketplace, registry, suite inventory/profile, structural eval inventory, remaining plugin-registry/plan-workflow design notes, architecture note/contract, and generated human doc; keep the gate/workflow/CI-gates/review-reporting changes from 2.4 detect-only here. Re-run both platform budget receipts after final generated bytes, add detect-only `test:ConsumerInstall.DistributionAndAttestation`, and prove it leaves the tree unchanged (REQ-9, RISK-8, RISK-9) [after: 2.4, 3.3, 4.1] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 5.1 Review the installed-surface inventory, source/read boundary, scaffold confinement, retirement transition, owner-local limit bindings, fleet handoff, diagnostics, and distribution proof; push the final candidate and require fresh tree-bound Linux/Windows CI suite, structural-eval, drift, and probe receipts before archival (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11) @human [after: 4.2] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `@cr` over the consumer fixture, runtime-reference scanner, probe matrix, scaffold lifecycle, limit owners/parity tests, installer lifecycle fixtures, generated distribution, and updated design notes.
   2. Triage every finding. Return blocking findings to the owning phase and preserve the published review artifact.
   3. Push the exact implementation candidate and wait for both supported CI legs. Record the run IDs, candidate commit/tree digest, suite receipt, structural-eval attestation, drift attestation, and consumer-probe report from each leg.
   4. Create at most one evidence-only final commit whose parent is that attested candidate and whose diff is confined to this plan's evidence/review assets. Approve only when every active plugin has a terminal installed probe with zero skips, all required host capabilities are `available`, read canaries remain untriggered, hostile scaffold and retirement-transition cases fail before unsafe mutation, both-direction limit mutations turn the parity gate red, and both CI legs match the parent candidate within their configured ceilings.

  **Verify:** `review:cr` is recorded; every required marker in `assets/evidence.md` is `✓`; active plugin/probe/scaffold sets are equal with zero skips; both candidate-tree CI receipt sets are recorded and valid; any final commit changes only allowlisted evidence/review paths and names its attested parent; all detect-only drift gates pass without mutation; and the worktree is clean.

  **Rollback:** Before archival, mark the affected step `[~]`, remove approval, discard the evidence-only commit if present, and repair the owner or consumer fixture. A platform-tier contradiction reopens step 2.4. After release, repair forward with higher plugin versions; do not downgrade installed consumers or remove source-bound retirement records.

  </details>
