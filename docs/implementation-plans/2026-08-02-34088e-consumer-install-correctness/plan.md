# 34088e: Consumer install correctness
<!-- plan-id: 34088e -->
<!-- depends-on: cda9da -->
<!-- cip-stage: dr-round-3 -->
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

- [ ] 1.1 Extract one shared foreign-consumer snapshot/mutation-copy substrate around production Install/Update; migrate or delimit `ReviewConsumerInstall` and retirement adapters; put source confinement in Test-Registry/installer, index roots before cleanup, and add `test:ConsumerInstall.ProductionFixtureAndInventory` with mapping/link/hash/root mutations (REQ-1, RISK-1, RISK-4) `L`
- [ ] 1.2 Add typed scanner inventory/enumeration in `Sync-PluginScripts.ps1`, structural read-site parsing, exact owner caps in `tools/runtime-reference-limits.psd1`, scanner-owned exclusions in `tools/runtime-reference-exclusions.json`, one traversal/cached parses, and 1x/2x scaling; keep plan-local dispositions as migration provenance only, update architecture note/contract/human doc, and add `test:ConsumerInstall.RuntimeReferenceEnumeration` plus evidence-ID baseline (REQ-2, REQ-9, RISK-2, RISK-9, RISK-10) [after: 1.1] `L`
- [ ] 1.3 Resolve every live violation, enable bidirectional enforcement, retire migration-only state and update scanner exploration/indexes, then deliver installed MVP probes for one script-heavy and one scaffold plugin using overlay read canaries, payload-load sentinels, minimal environments, and isolation adapters; record diagnostic Stopwatch timing only, with authoritative measurement deferred to 2.4 (REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-3, RISK-10) [after: 1.2] `L`

## Phase 2: Complete active-plugin and scaffold matrix
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Extend plugin/registry schemas with closed `consumerProbe`, requiring entrypoint membership in that plugin's `files[].dest` and complete scaffold-to-probe bindings; add run/measurement schemas and manifest-first incremental state; implement deterministic waves of four, fast/slow task and matrix deadlines, terminal timeout/not-admitted records, minimal environment, network/firewall identities and startup reclaim, hard-kill recovery, root-confined quarantine retention, and `test:ConsumerInstall.ProbeDescriptorAndAttendance` (REQ-1, REQ-3, REQ-8, RISK-1, RISK-3, RISK-8, RISK-11) [after: 1.3] `L`
- [ ] 2.2 Execute active-addition/retirement/missing/orphan descriptor mutations and the complete matrix with planned/launched/terminal equality and zero skips; require payload-load proof before refusal, corruption per probe class, all-hang/outbound-socket red probes, credential-shape guard, and `test:ConsumerInstall.ActivePluginProbeMatrix` (REQ-3, REQ-8, RISK-1, RISK-3, RISK-7, RISK-8, RISK-11) [after: 2.1] `L`
- [ ] 2.3 Execute every declared first-use scaffold owner through its bound probe; assert scaffold/probe set equality and add `test:ConsumerInstall.FirstUseScaffoldLifecycle` for starter bytes, nested/hostile values, reparse ancestors, parent replacement, modified targets, interruption, cleanup, retry, and typed capability-unavailable refusal that cannot satisfy finalization (REQ-2, REQ-4, RISK-4) [after: 2.1] `L`
- [ ] 2.4 Atomically rename `Test-ReviewConsumerInstall.ps1`, actual `gate:review-runtime-integration`, workflow call, tests, and inventory row to `Test-ConsumerInstall.ps1`/`gate:consumer-runtime-integration`; emit paying-host scanner and per-platform probe receipts, enforce fast/slow deadlines plus install/copy counts, predeclare `met-or-tier-required`, and prove all-hang, passing slow-tier, firewall reclaim, linked quarantine-root, environment/auth, and credential red mutations (REQ-8, REQ-9, RISK-8, RISK-11) [after: 2.2, 2.3] `L`

## Phase 3: Owner-local workflow-limit parity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add the schema-backed `skalary/workflow-limits@1` projection, active-consumer registration tokens, and generic allowlisted discovery/refusal first; extend bundle closure/pruning/manifests for `.psd1` and registered schemas; then add `PlanWorkflowLimits.psd1`, migrate executable/template consumers, classify prose artifacts as provenance, and add owner/consumer/installed-copy mutations in `test:WorkflowLimits.PlanOwnerParity` (REQ-6, RISK-5, RISK-9) [after: 2.4] `L`
- [ ] 3.2 Register non-validating `x-skalary-limits` in `schemas/review/review-limits.schema.json` as the review owner; update CR/DR guides, collation inputs, schema copies, `review-reporting.design.md`, and compatibility fixtures without narrowing or retroactively invalidating `skalary/review-run@1`; add `test:WorkflowLimits.ReviewOwnerParity` with both-direction mutations and installed-authority clamping (REQ-6, RISK-5, RISK-9) [after: 3.1] `L`
- [ ] 3.3 Add `test:WorkflowLimits.FleetConsumerHandoff` plus `test:Epic.WorkflowLimitsDependencyState`; verify the script-owned `8a0644 -> 34088e` edge in bcece1, 33b1f9 consistency regeneration, receiving-side requirement/risk, synthetic scheduler descriptor, copied-cap refusal, idempotent replay, and marker/mirror rollback (REQ-7, RISK-5, RISK-6) [after: 3.2] `M`

## Phase 4: Consumer lifecycle and distribution proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Cite cda9da's authoritative retirement state/fault markers and add only downstream `test:ConsumerInstall.RetirementTransition`: invoke its delivered reconciler from the previous-generation fixture through installed entrypoints and prove same-source cleanup, foreign-source refusal, modified residue diagnosis, and idempotent retry without rebuilding upstream matrices (REQ-5, RISK-4, RISK-7) [after: 2.3] `L`
- [ ] 4.2 Converge affected bundles, dogfood, manifests/versions, README, marketplace, registry, suite inventory/profile, structural eval inventory, indexed consumer-probe/plugin-registry/plan-workflow/review-reporting/CI-gates notes, architecture note/contract, and human doc; detect the atomic gate rename; rerun final-inventory platform disposition; add exact-ID executor plus per-leg sourceTreeDigest receipt producer/verifier and evidence-only child-commit guard (REQ-8, REQ-9, RISK-8, RISK-9) [after: 2.4, 3.3, 4.1] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 5.1 Review the installed-surface inventory, source/read boundary, scaffold confinement, retirement transition, owner-local limit bindings, fleet handoff, diagnostics, and distribution proof; push the final candidate and require fresh tree-bound Linux/Windows CI suite, structural-eval, drift, and probe receipts before archival (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11) @human [after: 4.2] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `@cr` over the consumer fixture, runtime-reference scanner, probe matrix, scaffold lifecycle, limit owners/parity tests, installer lifecycle fixtures, generated distribution, and updated design notes.
  2. Triage every finding. Return blocking findings to the owning phase and preserve the published review artifact.
  3. Push the exact source candidate and wait for authoritative Linux and Windows CI receipts with the same `sourceTreeDigest`.
  4. Create at most one evidence-only child commit touching only `assets/evidence.md`, `assets/logs/**`, and `assets/reviews/**`; verify the sourceTreeDigest remains unchanged.
  5. Approve only when every active plugin and scaffold has a terminal installed probe with zero skips/capability-unavailable outcomes, read canaries remain untriggered, hostile scaffold and retirement-transition cases fail before unsafe mutation, limit mutations turn red, and both CI legs match the source tree and configured tier.

  **Verify:** `review:cr` is recorded; every required marker in `assets/evidence.md` is `✓`; active plugin/probe and scaffold/probe sets are equal; both per-leg receipts and evidence-only commit guard pass; all detect-only drift gates leave the tree unchanged; and the worktree is clean.

  **Rollback:** Before archival, mark the affected step `[~]`, remove approval, and repair the owner or consumer fixture. After release, repair forward with higher plugin versions; do not downgrade installed consumers or remove source-bound retirement records.

  </details>
