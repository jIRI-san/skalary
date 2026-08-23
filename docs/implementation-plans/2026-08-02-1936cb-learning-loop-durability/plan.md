# 1936cb: Learning loop durability
<!-- plan-id: 1936cb -->
<!-- cip-stage: dr-round-10 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
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

## Phase 1: Durable phase learning
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Update the existing CI and autopilot phase crosscheck paths to read the layout-resolved capture/learnings files and append selected lessons through `Add-LedgerEntry.ps1`; preserve its current taxonomy, sanitization, locking, deduplication, and finalization retry behavior. Add `test:LearningLoop.PhaseCaptureAndFinalSweep` for two phases, an intentionally empty phase, and replay (REQ-1, REQ-4, RISK-1, RISK-4) `L`

## Phase 2: SI due and outcome record
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Add one small append-only SI activity file and one script-owned writer for typed `due` and `result` records. Reuse the narrow lock/temp/atomic-replace pattern already used by `Add-LedgerEntry.ps1` and `Update-FeedbackQueue.ps1`; deduplicate a due by plan and source commit, preserve earlier rows, confine the first-use scaffold, and cover replay/interruption with `test:SiActivity.AppendDedupAndRecovery` (REQ-2, REQ-4, RISK-2, RISK-3, RISK-4) [after: 1.1] `L`
- [ ] 2.2 At successful headless completion append one non-blocking `due` record without running `/si`; at the next interactive completion surface one matching unresolved due. Update normal `/si` completion to append the operator's candidate choices and run outcome as a `result` record, without changing `/si` proposal or merge authority. Add `test:SiActivity.HeadlessDueAndInteractiveOutcome` (REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3) [after: 2.1] `L`

## Phase 3: Distribution and focused proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Distribute the writer through the owning self-improvement plugin using existing plugin sync, version, registry, marketplace, and dogfood writers; update only affected workflow/design notes. Prove an installed self-improvement/CI/autopilot fixture can append, deduplicate, surface, and record an outcome without source-tree paths using `test:LearningLoop.InstalledPayloadAndDrift` (REQ-4, RISK-4) [after: 2.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review phase-learning persistence, due deduplication, outcome recording, installed execution, and preservation of `/si` safety boundaries; record `review:cr` and approve or return the plan before archival (REQ-1, REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3, RISK-4) @human [after: 3.1] `S`
  <details><summary>Details</summary>

  **Steps:**
   1. Run `@cr` over the completed branch, focusing on confined append-only writes, replay behavior, non-blocking headless completion, untrusted stored text, and unchanged `/si` proposal safeguards.
   2. Return blocking findings to the owning phase; otherwise record the review result and rebuild the evidence receipt.

   **Verify:** `review:cr` is recorded as passed, every required marker in `assets/evidence.md` is `✓`, focused tests pass, generated plugin artifacts are synchronized, and the normal project validation is green.

   **Rollback:** Do not approve or archive. Mark the affected step `[~]`, record the finding, and rerun the focused checks after correction.

  </details>
