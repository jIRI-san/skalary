# 9fda0b: GitHub work hierarchy synchronization
<!-- plan-id: 9fda0b -->
<!-- depends-on: 57cc2c, 25aa23 -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: step -->
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

## Phase 1: Installable mocked work-hierarchy MVP
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Implement provider-neutral projection, typed port records, canonical vocabulary/fingerprints, and the algebraically checked limits descriptor through the canonical engine/parser closure (REQ-1, REQ-5, REQ-10, REQ-11, RISK-7) `M`
- [ ] 1.2 Implement consumer config ownership, the `25aa23` epic-resolver extension, bounded append store, and independent seam/evidence maps with seeded red controls (REQ-2, REQ-3, REQ-11, REQ-12, RISK-3, RISK-4, RISK-7) [after: 1.1] `M`
- [ ] 1.3 Ship and install the read-only mocked dry-run slice; close Phase-1 Fast/eval, sidecar bundle, consumer install, dogfood/registry/marketplace/catalog, and named-doc gates (REQ-2, REQ-7, REQ-9, RISK-7, RISK-9) [after: 1.2] `M`

## Phase 2: Bounded GitHub discovery and trusted adoption
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add immutable-target ambient-`gh` preflight plus bounded REST issue/sub-issue and GraphQL Projects v2 discovery, transport-policy parity, injectable time/process controls, raw-text isolation, and operation-class retries (REQ-5, REQ-10, REQ-11, RISK-1, RISK-5, RISK-6, RISK-11) [after: 1.3] `M`
- [ ] 2.2 Add explicit prelinks, confirmed marker hints, managed-region rendering, dependencies, typed fingerprints, and three-way conflict/refusal behavior (REQ-3, REQ-4, RISK-2, RISK-3, RISK-11) [after: 2.1] `M`
- [ ] 2.3 Close Phase-2 Fast/Slow/eval, installed payload, generated artifact, suite-map, transport-parity, and named-document gates (REQ-7, REQ-9, REQ-12, RISK-9) [after: 2.2] `M`

## Phase 3: Capability-bound apply and durable recovery
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Implement owner-only approvals, local plus atomic remote-ref exclusion, the normative state/exit matrix, pinned retention, read-only state inspection, and publication-wide redaction with the write descriptor absent (REQ-3, REQ-6, REQ-11, REQ-12, RISK-2, RISK-4, RISK-8, RISK-11) [after: 2.3] `M`
- [ ] 3.2 Implement disabled apply, immediate pre-state checks, append-only intent/results, uncertain-outcome reconciliation, residual-digest reapproval, terminal snapshots, and exhaustive fault/lock tests (REQ-3, REQ-6, REQ-11, REQ-12, RISK-3, RISK-4, RISK-6, RISK-8) [after: 3.1] `M`
- [ ] 3.3 Run the pre-enable gate, atomically publish the source/version/digest-bound write descriptor through `Enable-WorkHierarchySyncWrites.ps1`, prove real issue/sub-issue/project/Status writes, and close installed payload, generated artifact, eval, suite-map, and named-doc gates with automatic descriptor rollback on failure (REQ-6, REQ-7, REQ-9, REQ-11, REQ-12, RISK-6, RISK-9) [after: 3.2] `M`

## Phase 4: Live target preparation and approval
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Authorize a disposable organization namespace and protected hosted credential handoff (REQ-5, REQ-8, REQ-11, RISK-1) [after: 3.3] @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `gh auth refresh -h github.com -s repo,read:org,project` and complete GitHub's browser authorization.
  2. Choose an organization where the active account may create and delete a test repository and organization Project v2.
  3. Run `scripts/skalary/live/Set-WorkHierarchySyncSmokeTarget.ps1 -RepoRoot . -Organization "<organization>"`; this records only actor, organization ID, unique run namespace, expiry, and host credential source in ignored host state.
  4. Run `scripts/skalary/live/Test-WorkHierarchySyncSmokeTarget.ps1 -RepoRoot .`.

  **Verify:** deterministic host preflight reports the authenticated actor and immutable organization ID and proves repository/project create-delete capability for the unique namespace without persisting or printing the token.

  **Rollback:** run `scripts/skalary/live/Remove-WorkHierarchySyncSmokeTarget.ps1 -RepoRoot .`; revoke the added GitHub CLI OAuth grant under GitHub **Settings > Applications > Authorized OAuth Apps**, then restore prior `gh` scopes if needed.

  </details>
- [ ] 4.2 Through repo-root live-test tooling, pre-journal intended names, create disposable repository/project resources, discover immutable IDs, publish the initial product dry run, and stage an environment-protected exact-commit hosted workflow request without product mutations; close the Phase-4 evidence/distribution/doc gate (REQ-5, REQ-8, REQ-9, REQ-11, REQ-12, RISK-1, RISK-5, RISK-9, RISK-10) [after: 4.1] `M`
- [ ] 4.3 Confirm the exact created targets and dry-run capability (REQ-5, REQ-6, REQ-8, RISK-1, RISK-2) [after: 4.2] @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `scripts/skalary/live/Get-WorkHierarchySyncSmokeApproval.ps1 -RepoRoot .`.
  2. Verify the printed actor, immutable organization/repository/project IDs and URLs, source commit/tree, installed registry digest, action counts, action digest, expiry, and cleanup journal UUID.
  3. Approve the protected `work-hierarchy-sync-smoke` GitHub environment deployment for the exact workflow run, then run `scripts/skalary/live/Approve-WorkHierarchySyncRun.ps1 -RepoRoot . -RunId "<run-id>"`.

  **Verify:** the approval record is stored in the ignored host approval directory with owner-only access, binds the displayed immutable identities/digests and a single-use nonce, and reports `approved` without exposing raw remote content or credentials.

  **Rollback:** run `scripts/skalary/live/Revoke-WorkHierarchySyncRun.ps1 -RepoRoot . -RunId "<run-id>"`; no product mutation has occurred yet. Delete the pre-journaled disposable resources through `Remove-WorkHierarchySyncSmokeTarget.ps1` if the smoke will not resume.

  </details>
## Phase 5: Live execution and final integration
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Dispatch the protected hosted workflow with the approved run UUID, exercise bound apply, second-run no-op, confirmed recovery, managed-region conflict, uncertain-response resume, and cleanup; retrieve and independently reverify the uniquely bound API artifact, then close Phase-5 live/eval/distribution/doc gates (REQ-3, REQ-4, REQ-5, REQ-6, REQ-8, REQ-9, REQ-11, REQ-12, RISK-2, RISK-5, RISK-10, RISK-11) [after: 4.3] `L`
- [ ] 5.2 Run final requirement/evidence reconciliation and the complete configured Fast, Slow, validation, structural-eval, analyzer, installed-consumer, distribution-drift, live-receipt, CR, and DR gates on one source tree; record that no post-merge-only gate is claimed (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, RISK-9) [after: 5.1] `M`
