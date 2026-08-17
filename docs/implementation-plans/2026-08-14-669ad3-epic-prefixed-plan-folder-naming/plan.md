# 669ad3: Epic-prefixed plan folder naming
<!-- plan-id: 669ad3 -->
<!-- epic: bcece1 -->
<!-- cip-stage: done -->
<!-- Folder naming target: <epic-id>-<yyyy-mm-dd>-<plan-id>-<slug> or standalone-<yyyy-mm-dd>-<plan-id>-<slug>; plan-id remains canonical. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
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

## Phase 1: Grammar and consumer foundation
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Add the shared parser/formatter, compatible `Scheme`, closed `FolderForm`/`EpicId`, typed read diagnostics, prefix/marker agreement, Fast fixtures, and anchored auto-approval mirror; remove duplicate grammar implementations and sync affected distributions (REQ-1, REQ-9, RISK-4, RISK-5) `L`
- [ ] 1.2 Move plan index/state, epic rollup, archive classification, current-tree historical lookup, and active path/link evidence onto canonical resolution; classify historical provenance and sync affected distributions (REQ-1, REQ-8, REQ-9, RISK-4, RISK-5) [after: 1.1] `M`

## Phase 2: Final-name creation and membership
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add protocol-v1 namespace locking, complete lock order, isolated host authority mounts, capability/journal schemas, operation allowlists, Git recovery classification, numeric bounds, exit-44 behavior, and mixed-version/interleaving/kill/tamper fixtures; amend `ARCH-Review-Run-V1` and sync every writer (REQ-3, REQ-6, REQ-9, RISK-3, RISK-5, RISK-7, RISK-8, RISK-10) [after: 1.1] `L`
- [ ] 2.2 Extend locked `New-Plan.ps1` and `/cip`/`/cep` contracts to resolve epic context and create only final epic-prefixed or `standalone` names; prove pending-journal recovery and no intermediate path, then sync affected surfaces (REQ-2, REQ-9, RISK-4, RISK-5) [after: 2.1] `M`

## Phase 3: Membership and migration commands
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Transact new-epic creation, multi-child attachment, forced re-parenting, folder moves, markers, and mirrors through protocol v1; enforce operation-kind allowlists, closed replay/mismatch classification, and fault every boundary (REQ-4, REQ-9, RISK-3, RISK-5) [after: 2.2] `L`
- [ ] 3.2 Add cip-owned prefix migration, prove its behavioral boundary from `Repair-Plans.ps1`, reuse installer transaction validation helpers, implement approved-UUID receipts/capabilities/Windows probes, and add bounded Slow recovery fixtures; sync distribution (REQ-5, REQ-6, REQ-9, RISK-1, RISK-3, RISK-5, RISK-6, RISK-7, RISK-8, RISK-11) [after: 2.1, 3.1] `L`

## Phase 4: Lifecycle and distribution closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Replace `PlanSlug` authority with canonical plan/branch/worktree/run handles; propagate bounded exits 44/45; attest isolated mounts and protocol generation; re-resolve review/log/evidence/archive/transcript writers; and sync affected payloads (REQ-3, REQ-7, REQ-8, REQ-9, RISK-2, RISK-4, RISK-5, RISK-7, RISK-8, RISK-10) [after: 1.2, 3.2] `L`
- [ ] 4.2 Add the marker/scenario/file/tier map, seeded discovery/drift failures, synthetic terminal verifier, exact four-tuple CI aggregation, and Fast-budget/Slow-runtime wiring; update every named design/architecture note and index (REQ-9, REQ-10, REQ-12, RISK-5) [after: 1.2, 2.1, 2.2, 3.1, 3.2, 4.1] `M`
- [ ] 4.3 Update the initiating host checkout and relaunch plan `669ad3` with the new canonical-ID launcher before terminal migration (REQ-7, RISK-2, RISK-9) @human [after: 4.2] `S`
	<details><summary>Details</summary>

	**Steps:**
	1. Let the current container stop through the existing exit-42 handoff; do not start Phase 5 in that runtime.
	2. In the initiating workspace, inspect `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement`; remove it only when Git reports it untracked and recursive inspection proves it empty. Stop and report any content.
	3. In the plan's host worktree, fetch the work branch and fast-forward to the Phase-4 commit.
	4. Resume `/ci 669ad3`, confirm this handoff, and let `/ci` mark 4.3 complete, commit, and push it before choosing whole-plan container mode.
	5. Verify the updated launcher capability receipt, then start Phase 5 by canonical plan ID.

	**Verify:** the pushed branch reports step 5.1 next; unmatched plan-shaped directory count is zero; the capability receipt reports protocol v1, canonical ID `669ad3`, exit-44/45 mappings, isolated mount identities, and one remaining relaunch; the old container is stopped.

	**Rollback:** stop before Phase 5 and reset the local host worktree to the pushed Phase-4 commit; no corpus rename has started.

	</details>

## Phase 5: Terminal corpus migration
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Finalize review authority, obtain and commit the dry-run UUID/readiness mapping, push a progress commit, and request the single exit-45 handoff; the host validates its capability, invokes the bundled cip apply, writes/pushes `assets/plan-folder-migration.json`, then relaunches so 5.1 closes from the exact apply receipt (REQ-5, REQ-6, REQ-7, REQ-8, REQ-11, RISK-1, RISK-2, RISK-3, RISK-6, RISK-7, RISK-8, RISK-11) [after: 4.3] `L`
- [ ] 5.2 Re-resolve `669ad3` on the migrated tree, run complete local gates, publish the migrated commit, collect exactly four same-identity CI tuples, and run the fail-closed terminal verifier; on red, block merge/finalization and fix forward from the committed mapping while resuming only missing gates (REQ-10, REQ-12, RISK-2, RISK-5, RISK-6, RISK-12) [after: 5.1] `L`
