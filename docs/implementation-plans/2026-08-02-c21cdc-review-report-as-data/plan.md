# c21cdc: Review report as data
<!-- plan-id: c21cdc -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual | host-autopilot | container-autopilot | sandbox-autopilot -->
<!-- scope: step | phase | plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:<list>; npm:<list> -->

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

## Phase 1: Name
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Step title (REQ-1) `S`
- [ ] 1.2 Step title (REQ-1, RISK-1) @human `M`
  <details><summary>Details</summary>

  **Steps:**
  1. Navigate to **Azure Portal > Resource Group > ...**
  2. Run: `az resource ...`

  **Verify:** the concrete, observable condition that proves the step worked.

  **Rollback:** Delete the resource / revert the setting to X.

  </details>

## Phase 2: Name
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Step title (REQ-1, RISK-1) [after: 1.1] `S`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] X.Y Finalization gate (REQ-1) @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. What the operator has to do, in order.

  **Verify:** what proves it worked.

  **Rollback:** how to undo it.

  </details>
