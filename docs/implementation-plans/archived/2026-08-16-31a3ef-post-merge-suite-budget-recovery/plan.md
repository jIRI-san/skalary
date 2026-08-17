# 31a3ef: Post-merge suite budget recovery [DONE]
<!-- plan-id: 31a3ef -->
<!-- cip-stage: done -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

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
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Restore coherent suite ownership
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Reconcile the independently merged review-run and architecture-test-retirement authorities: include active CR/DR parser bundles, compare epic unmet dependencies to computed incomplete dependencies, restore the exact c21cdc suite-removal ledger, and remove ignored retired plugin residue (REQ-1, RISK-1) `S`
- [x] 1.2 Add one tracked suite-tier manifest and make `Run-UnitTests.ps1` execute a closed `Fast`, `Slow`, or diagnostic `All` partition. Keep cannot-test, environment-leak, and skipped-required-evidence failures identical in both required tiers; apply the existing runtime budget only to `Fast`; add partition and runner behavior tests (REQ-2, REQ-3, RISK-2, RISK-3) `L`

## Phase 2: Require both tiers and prove the gate
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Keep `npm test` as the budgeted fast command, add `npm run test:slow`, and wire the slow tier as a separate blocking step in both registry CI matrix legs with separate NUnit evidence. Update the gate inventory and CI design note so every host and enforcement claim stays executable (REQ-3, REQ-4, RISK-2, RISK-4) [after: 1.2] `L`
- [x] 2.2 Run focused partition/runner/workflow checks, then one fast `npm test` and one slow-tier run; require both green, require the fast command below the Windows 600-second ceiling, and record measured totals without raising any budget (REQ-1, REQ-2, REQ-3, REQ-4, RISK-1, RISK-3, RISK-4) [after: 2.1] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [x] 3.1 Review the partition, mandatory CI execution, NUnit attribution, and preserved coverage before finalizing the recovery (REQ-1, REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3, RISK-4) @human [after: 2.2] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Confirm every discovered test belongs to exactly one required tier, except the already dedicated review-consumer install matrix.
  2. Confirm both Linux and Windows jobs invoke Fast and Slow through `Run-UnitTests.ps1`, and neither invocation uses `continue-on-error`.
  3. Confirm `npm test` remains below the bound Windows ceiling without changing `tools/suite-budget.psd1`.

  **Verify:** `test:SuiteTier.PartitionContract`, `test:RunUnitTests.TierExecution`, `test:CiGates.InventoryMatchesWorkflow`, and both complete tier runs pass; `review:cr` records no blocking finding.

  **Rollback:** revert the manifest, runner, package, workflow, tests, and design-note changes together; never leave a tier that CI does not invoke.

  </details>
