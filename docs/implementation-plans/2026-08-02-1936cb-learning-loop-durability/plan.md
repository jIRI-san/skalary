# 1936cb: Learning loop durability
<!-- plan-id: 1936cb -->
<!-- cip-stage: dr-round-10 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 9 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:none; npm:none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Supporting material is organized under `assets/` by concern.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Bounded state store and recovery contract
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Define plugin-owned sources outside the bundle-managed tree: `plugins/self-improvement/schemas/{manifest,run,resolver-receipt,repair-observation,repair-receipt}.schema.json` and `plugins/self-improvement/scripts/{Enqueue-SiDue,Update-SiState,Get-SiState,Repair-SiState,Archive-SiState,SiStateStore}.ps*1`; enumerate every exact source-to-`skills/si/{schemas,scripts}` destination in `plugin.json`, define the closed state/limit/topology contracts, and sync dogfood/version/marketplace/registry in this step (REQ-1, REQ-7, REQ-8, RISK-1, RISK-7, RISK-8, RISK-10) `L`
- [x] 1.2 Implement those plugin-owned sources plus root-canonical `scripts/skalary/AtomicStore.psm1`; enumerate canonical writers and installed consumers: SI state/lifecycle writers, PFB `Update-FeedbackQueue`, CI and CIP `Add-WorkflowNote`, and CI/autopilot ledger/phase-harvest writers. Bundle the module closure into SI/PFB/CI/CIP/autopilot and require every writer to import/use it for locking, CAS, status, and atomic replace. Implement the state/repair contracts; sync all consumers/dogfood/manifests/versions/marketplace/registry; add `test:SiState.SchemaManifestAndRuns`, `test:SiState.RankedSetCompleteness`, `test:SiState.InspectionRepairStateMatrix`, `test:SiState.VersionMigrationRepairRollback`, `test:SiState.ConcurrentCrashCasExhaustion`, and `test:AtomicStore.AllWritersUseSharedPrimitive`, whose negative fixture keeps one direct writer and must fail (REQ-1, REQ-7, REQ-8, RISK-1, RISK-3, RISK-10) [after: 1.1] `L`
- [x] 1.3 Declare manifest, sharded active/archive run, backup, quarantine/index, repair-observation/receipt, and resolver-receipt scaffolds; sync dogfood/version/marketplace/registry; prove metadata-only inspection and local repair from a self-improvement-only consumer install with `test:SiState.BoundedManifestPagingAndRepair`, while `test:SiState.RepairReceiptGatesApplyRollback` proves every apply/rollback consumes the exact observation/receipt chain (REQ-1, REQ-7, REQ-8, RISK-7, RISK-8, RISK-10) [after: 1.2] `M`

## Phase 2: Crash-safe feedback and learning capture
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Update `Update-FeedbackQueue.ps1` to preserve existing 8-hex IDs, issue 16-hex IDs for new post-sanitization content, and enforce the exact ceilings in `operational-limits.md`; plus-one returns `capacity-blocked` before mutation, all mutations use Phase 1's installed `AtomicStore.psm1`, and migration never recomputes an old ID; globally sync every bundle/dogfood/manifest/version/marketplace/registry copy and add `test:FeedbackQueue.BoundedRoundTripMigrationAndCrash` (REQ-5, REQ-8, RISK-1, RISK-3, RISK-6, RISK-7) [after: 1.2] `L`
- [x] 2.2 Add logical `LearningOverflowRoot` and `HarvestReceiptRoot` kinds to `PlanState`, with assets-layout and permanent legacy-layout paths plus repo/inventory confinement for `-PlanDir`; extend `Add-WorkflowNote.ps1` entries with typed `-Concern`, sorted `-Requirement`, and `-ReviewType` fields from closed enums and include them in each domain-separated source-record ID; make it the sole locked writer of active learnings/append-only overflow, retire new `overflow-summary` generation, treat old summaries as explicit legacy-loss degradation, declare scaffolds, globally sync bundles/dogfood/manifests/versions/marketplace/registry, and add `test:WorkflowNote.LosslessOverflowCrashRecovery` plus `test:WorkflowNote.TypedProvenanceRoundTrip` (REQ-4, REQ-5, REQ-8, RISK-3, RISK-5, RISK-6, RISK-7, RISK-8) [after: 2.1] `L`
- [x] 2.3 Add deterministic repair/dedup for orphan overflow batches, stale temps, duplicate source-record IDs, old summaries, every crash point, and the shared CAS status enum; enforce exact ceilings and prove plus-one, `lock-timeout`, three-conflict exhaustion, hostile marker, concurrent writer, legacy path, escape, and rollback cases with `test:Capture.AtomicBoundaryMigrationMatrix`; sync every affected bundle/dogfood/manifest/version/marketplace/registry in this step (REQ-5, REQ-7, REQ-8, RISK-1, RISK-3, RISK-6, RISK-7) [after: 2.2] `L`

## Phase 3: Typed phase harvest and batch ledger writes
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Extract `LedgerStore.psm1` from `Add-LedgerEntry.ps1` as the single scalar/batch engine; implement `Invoke-PhaseHarvest.ps1` with source IDs binding repo/plan/phase/kind/review-type/path/exact bytes and deriving/cross-checking provenance; update CI/autopilot bundle references and globally sync scripts/dogfood/manifests/versions/marketplace/registry in this step (REQ-4, REQ-7, REQ-8, RISK-1, RISK-3, RISK-5, RISK-7, RISK-8) [after: 2.3] `L`
- [x] 3.2 Bundle the shared engine and phase harvester into both CI and autopilot from root-canonical sources, list both as distribution consumers, amend autopilot's closed execution allowlist for the bound installed copy, declare receipt scaffolds in both standalone installs, and globally sync scripts/dogfood/manifests/versions/marketplace/registry in this step; add `test:LearningHarvest.InstalledInvocationAndAutopilotAllowlist` proving both workflows invoke the installed script and malformed/missing sections surface as degraded (REQ-4, REQ-7, REQ-8, RISK-2, RISK-5, RISK-8) [after: 3.1] `L`
- [x] 3.3 Add `test:LearningHarvest.MultiPhaseBatchAndProvenance`, `test:LearningHarvest.FinalSweepReceiptReplay`, and `test:LearningHarvest.ActiveReceiptCapacityBoundary` covering every source class, phase isolation, derived REQ tags, forged routing metadata, normalized-text collisions, ledger ceilings, concurrent category writes, empty/malformed phases, final replay, and the exact receipt boundary: active receipts 1-64 succeed, receipt 65 returns `capacity-blocked` before mutation, and archived receipts never count toward the active set (REQ-4, REQ-7, REQ-8, RISK-2, RISK-3, RISK-5, RISK-7) [after: 3.2] `M`

## Phase 4: Bounded harvest and untrusted-input enforcement
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Add plugin-owned `plugins/self-improvement/scripts/Get-SiHarvest.ps1` mapped to `skills/si/scripts/Get-SiHarvest.ps1`; scan exactly the active set in `operational-limits.md` (manifest and phase receipts included; resolver outputs and archives excluded unless explicitly requested), and persist its pinned-OID index only through Phase 1's `AtomicStore.psm1`; scan every bounded file once, select/page the evidence window, bind cursors to the digest, sync dogfood/manifest/version/marketplace/registry, and extend `test:AtomicStore.AllWritersUseSharedPrimitive` with the index writer (REQ-6, REQ-7, REQ-8, RISK-1, RISK-3, RISK-7, RISK-8) [after: 1.3, 2.3, 3.1] `L`
- [ ] 4.2 Make the resolver the only SI free-text read path and add plugin-owned `plugins/self-improvement/scripts/Test-SiResolverReceipt.ps1` mapped to `skills/si/scripts/Test-SiResolverReceipt.ps1`. Persist `{payload,receiptId}` only through `AtomicStore.psm1`; closed-schema payload binds due/run/pinned OID/snapshot/selected/ranked digests and candidates, JCS-canonicalized with `receiptId=sha256('si-resolver-receipt-v1' UTF8 || JCS(payload))`; verifier re-canonicalizes/re-hashes and rejects extra/mutated fields. Sync dogfood/manifest/version/marketplace/registry; extend the all-writers test with the receipt writer and add `test:SiHarvest.ResolverReceiptIssuanceAndMutation`, `test:SiHarvest.FullScanSelectedWindowCompleteness`, `test:SiHarvest.HostileStoredContentIsFenced`, and `test:SiHarvest.SoleFreeTextReadPath` (REQ-6, REQ-7, REQ-8, RISK-1, RISK-3, RISK-7, RISK-8) [after: 4.1] `L`
- [ ] 4.3 Add `test:SiHarvest.ConsumerInstallExecution` that installs only declared dependencies into a foreign repo and executes paging, overflow, state, malformed-source, and forged-marker cases without skalary source-tree paths (REQ-6, REQ-8, RISK-1, RISK-8) [after: 4.2] `M`

## Phase 5: Headless enqueue and next-completion surfacing
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Make autopilot explicitly depend on self-improvement and invoke the Phase-1-installed `Enqueue-SiDue.ps1` only after its plan branch has persisted the complete source commit, using due ID `sha256(repo-id|plan-id|source-commit|si-due-v1)`; amend the closed allowlist, never run `/si`, report writer failure as non-blocking degradation, sync SI/autopilot/dogfood/manifests/versions/marketplace/registry, and add mixed-version/standalone install coverage in `test:SiDue.HeadlessDependencyInvocationAllowlistAndDedup` (REQ-2, REQ-3, REQ-7, REQ-8, RISK-1, RISK-2, RISK-8) [after: 1.3] `L`
- [ ] 5.2 Add plugin-owned `plugins/self-improvement/scripts/Invoke-SiLifecycle.ps1` mapped to `skills/si/scripts/Invoke-SiLifecycle.ps1`; implement metadata-only `Surface`, update interactive CI completion to call that installed dependency, fetch/pin main, classify fixed due/repair branches, and expose no free text; sync SI/CI/dogfood/manifests/versions/marketplace/registry and add `test:SiDue.InteractiveInstalledSurfaceTransitionMatrix` (REQ-2, REQ-3, REQ-7, REQ-8, RISK-2, RISK-3, RISK-4) [after: 4.3, 5.1] `L`

## Phase 6: Merge-based run lifecycle and trusted proposal gate
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Extend the mapped `Invoke-SiLifecycle.ps1` with `Begin/RecordChoices`, consuming `Test-SiResolverReceipt.ps1`; require current pinned OID/snapshot and same due/run replay, create/resume fixed `si/<due-id>`, persist exactly 0-5 receipt candidates plus choices, and reject absent/stale/fabricated/omitted/extra/duplicate/rewritten input; sync SI dogfood/manifest/version/marketplace/registry and add `test:SiState.ResolverReceiptCandidateRefusalMatrix` including replay/staleness (REQ-1, REQ-2, REQ-3, REQ-6, REQ-7, REQ-8, RISK-1, RISK-3, RISK-4) [after: 5.2] `L`
- [ ] 6.2 Add plugin-owned `plugins/self-improvement/scripts/Invoke-SiProposalSync.ps1` mapped to `skills/si/scripts/Invoke-SiProposalSync.ps1`; merge current main, re-derive state, enforce the closed trust-anchor deny set in `trust-anchor-deny-set.md`, reject hand edits, validate/push the exact OID, and confirm remote-head equality. Sync SI dogfood/manifest/version/marketplace/registry; add `test:SiScope.TrustedBasePassesAllowedProposal`, `test:SiScope.ProtectedTrustAnchorsAllRefused`, and `test:SiScope.StaleRemoteHeadRefused` (REQ-2, REQ-7, REQ-8, RISK-1, RISK-4, RISK-9) [after: 6.1] `L`

## Phase 7: External PR reconciliation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Add plugin-owned `plugins/self-improvement/scripts/Complete-SiProposal.ps1` mapped to `skills/si/scripts/Complete-SiProposal.ps1`; from detached trusted-base code fetch the live draft head, rerun scope/trust-anchor/state/receipt enforcement against that OID, then invoke provider merge with `expectedHeadOid` in the same process; `/si` never invokes it. Journal repair backups by observation ID before mutation and support rollback without final receipt. Sync SI dogfood/manifest/version/marketplace/registry; add `test:SiState.AuthoritativeFixedBranchLifecycleMatrix`, `test:SiState.PrFailureReconciliation`, `test:SiState.AllDeclinedRecordPr`, `test:SiState.CorruptionIndependentRepairLifecycle`, `test:SiState.RepairCrashJournalRollback`, `test:SiState.RepairReceiptGatesAuthoritativeMerge`, and `test:SiScope.ExpectedHeadMergeEnforced` (REQ-1, REQ-2, REQ-3, REQ-7, REQ-8, RISK-2, RISK-3, RISK-4, RISK-9, RISK-10) [after: 6.2] `L`

## Phase 8: Distribution, documentation, and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 8.1 Create `test:LearningLoop.PayloadOwnershipAndDrift` and `test:LearningLoop.StructuralEvals`; update self-improvement, plan-workflow, autopilot, plugin-registry, ci-gates, and dev-rules design notes; prove dependencies, plugin-canonical SI schemas/scripts, shared CI/autopilot bundles, installed invocations/allowlists, sole free-text resolver, scaffolds, per-step versions, marketplace, and registry are synchronized without adding a new validate gate (REQ-8, RISK-8) [after: 3.3, 4.3, 7.1] `L`
- [ ] 8.2 Add tracked `scripts/skalary/Get-SuiteInputFingerprint.ps1`, `test:LearningLoop.MaximumBoundRuntime`, and `test:LedgerStore.ScalarBatchParity`. Fingerprint every regular `git ls-files` path, including the producer; exclude only generated profile/runtime/XML. Use the canonical framing already specified. Measurement mode computes the current fingerprint and sets a process-only token containing protocol tag, fingerprint, random nonce, parent PID, and HMAC from a process-local random key; the gate verifies every field and still enforces ceilings while permitting stale rows only for that run. Successful measurement emits/imports a candidate row afterward; ordinary mode rejects stale rows. Add `test:SuiteBudget.MeasurementModeRefreshesStaleRows`, `test:SuiteBudget.MeasurementModeRejectsMismatchedOrReplayedToken`, and `test:SuiteBudget.OrdinaryModeRejectsStaleRows` (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8) [after: 8.1] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 9.1 Review the durable-state, trusted-base, merge-authority, and untrusted-input boundaries, record `review:cr`, and approve or return the plan before archival (REQ-2, REQ-7, REQ-8, RISK-1, RISK-4, RISK-9) @human [after: 8.2] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `@cr` over the completed branch, asking it to focus on state-file confinement/recovery, authoritative merge transitions, trusted-base guard execution, untrusted candidate text, non-blocking headless behavior, bounded costs, and proof that no capture path silently loses data.
  2. Triage every finding. Return blocking findings to the owning phase; otherwise record the review result in the evidence receipt and confirm the draft PR/state records match the reviewed branch.
  3. Complete every remaining fingerprinted mutation: review/evidence/log updates, ledger harvest, this step's `[x]` mark, design-note reconciliation, and the archive move. Commit that final tree before measuring.
  4. From that exact commit, run measurement mode on every supported platform and import both rows. Only excluded generated outputs (`tools/suite-runtime.json`, `tools/suite-profile.json`, `testResults.xml`) may change afterward.
  5. Run ordinary `npm test` once more. It must reject stale rows and pass with every row matching the final tree fingerprint; no fingerprinted mutation is allowed after this check.
     6. Commit the imported generated outputs by explicit path. Assert the commit diff contains only the excluded outputs, rerun the ordinary fingerprint/ceiling check against the committed tree, and require `git status --short` to be empty.

     **Verify:** `review:cr` is recorded as passed, every required marker in `assets/evidence.md` is `✓`, both platform runtime rows are committed and match the archived final-tree fingerprint, the generated-output commit touched no fingerprinted input, ordinary `npm test` plus structural evals are green, and the worktree is clean.

  **Rollback:** Before the archive commit, do not approve or archive: mark the affected step `[~]`, record the finding, and rerun focused checks. After the archive commit, any failed/stale measurement requires a follow-up commit that restores the plan to active `[~]` state before changing fingerprinted inputs and repeating the full final sequence.

  </details>
