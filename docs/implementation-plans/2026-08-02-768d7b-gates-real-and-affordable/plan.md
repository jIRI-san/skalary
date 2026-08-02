# 768d7b: Gates that are real and affordable
<!-- plan-id: 768d7b -->
<!-- cip-stage: dr-round-2 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: phase -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:none; npm:none -->

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

## Phase 1: Profile, bind the ceiling, baseline coverage
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Instrument `New-RepoClone`, `Install-Plugin`, `Build-Registry`, `Test-Registry` with call counts and aggregate seconds; emit `tools/suite-profile.json` across the whole `tests/` tree (REQ-1) `M`
- [ ] 1.2 Capture the test-name inventory for the whole tree as the coverage baseline (REQ-3) `S`
- [ ] 1.3 Create `tools/suite-budget.psd1` with `HardCeilingSeconds = 600`, `TargetSeconds = 480`, measured against `npm test`; add the test that rejects any raise without a recorded justification (REQ-2) `M`

## Phase 2: Shrink the fixture, then copy it
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Replace the full-history clone with a minimal synthetic `git init` fixture carrying `git tag` data for version resolution (REQ-3, REQ-4, RISK-11, RISK-12) [after: 1.1] `L`
- [ ] 2.2 Give each case its own filesystem copy of that minimal template, under a fresh random root that fails hard if it exists (REQ-4, RISK-1) [after: 2.1] `M`
- [ ] 2.3 Record Phase 2's achieved saving against its declared target; escalate rather than continue if missed (REQ-4) [after: 2.2] `S`

## Phase 3: Reduce the residue
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Scope `Build-Registry` calls to the plugins under test rather than all 11 (REQ-4) [after: 1.1] `M`
- [ ] 3.2 Apply the same pattern to the next-costliest files from 1.1 (`ReviewScope`, `Add-LedgerEntry`, `Test-Plan`, `SiWriteScope`) (REQ-4, RISK-9) [after: 1.1] `L`
- [ ] 3.3 Assert a randomised-order run gives identical results, and the fixture still carries tags (REQ-3, RISK-1, RISK-12) [after: 2.3, 3.2] `S`

## Phase 4: Prove the ceiling holds
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Measure `npm test` end to end and record the achieved figure with its environment (REQ-2, REQ-4) [after: 3.3] `S`
- [ ] 4.2 Tighten `tools/suite-budget.psd1` to the achieved figure plus stated headroom. The ceiling may only fall — unless the measured floor makes 600s unreachable, in which case raise it once to at most 900s with the justification written into `assets/decisions.md` (REQ-2, RISK-14) [after: 4.1] `M`
- [ ] 4.3 `Run-UnitTests.ps1` reads the budget and fails an over-budget `npm test`, reporting measured and budgeted values (REQ-2) [after: 4.2] `M`

## Phase 5: The test command fails when it cannot test
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 `Run-UnitTests.ps1` exits non-zero when Pester is absent, with a message naming the install command (REQ-5, RISK-3) `S`
- [ ] 5.2 Same when Pester is present but zero tests are discovered (REQ-5, RISK-3) [after: 5.1] `M`

## Phase 6: Plan stages are a closed, ordered set
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Define the ordered, closed stage set in `PlanState.psm1`; an unrecognised value fails loudly (REQ-6, RISK-6) `M`
- [ ] 6.2 `New-Plan.ps1` stamps the scaffold stage through `Set-PlanStage` rather than becoming a second writer of the anchor (REQ-6) [after: 6.1] `S`
- [ ] 6.3 `Validate-Plan.ps1` skips below `drafted` with a distinguishable signal; a missing anchor still means `drafted` (REQ-6, RISK-7) [after: 6.2] `M`

## Phase 7: Determinism and platform parity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Build a collation fixture that genuinely diverges (Czech `ch`, accents, mixed case); demonstrate it red against pre-fix code (REQ-7) `M`
- [ ] 7.2 Replace every culture-sensitive comparison in `Build-Registry.ps1` and `Build-Marketplace.ps1` with an ordinal comparer; regenerate catalogs in the same change (REQ-7) [after: 7.1] `M`
- [ ] 7.3 `validate.ps1` enumerates payload roots by allowlist, canonicalises, rejects reparse points; negative test asserts `.git` is not enumerated (REQ-8, RISK-5) `M`

## Phase 8: Wire and harden CI
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 8.1 Entry check: run the budget check and stop the phase on a non-zero result — `[after:]` proves sequence, not success (REQ-2, REQ-9) [after: 4.3] `S`
- [ ] 8.2 `registry-ci.yml` invokes `Run-UnitTests.ps1` and `validate.ps1` as separate named steps on both platforms, never chained (REQ-9, RISK-10) [after: 8.1] `M`
- [ ] 8.3 Harden: `permissions: contents: read`, `persist-credentials: false`, SHA-pinned actions, version-pinned modules with `-SkipPublisherCheck` and repository-trust removed, per-leg `timeout-minutes` above the hard ceiling, `concurrency` (REQ-9, RISK-8, RISK-4) [after: 8.2] `M`
- [ ] 8.4 Deterministic per-OS NUnit path and per-OS artifact name; upload with `if: always()` and write a summary line (REQ-9) [after: 8.2] `S`

## Phase 9: Inventory, docs, and finalization
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 9.1 Land `test:Ci.SeededFailureIsRed` as durable proof, replacing a one-off manual revert (REQ-9) [after: 8.3] `S`
- [ ] 9.2 Write `docs/design-notes/project/ci-gates.design.md`, register it in the index with `globs`, retire the clusters this plan resolves, record the constants deferral against `34088e`, and add `test:CiGates.InventoryMatchesWorkflow` (REQ-10, RISK-13) [after: 8.3] `L`
- [ ] 9.3 Plan crosscheck: re-run the budget check against the final tree, rebuild `assets/evidence.md`, verify every REQ marker (REQ-2, RISK-9) [after: 9.1, 9.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 9.4 Operator acceptance gate (REQ-2, REQ-3, REQ-4, REQ-10, RISK-2, RISK-9) @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Read `tools/suite-budget.psd1`. The ceiling was bound at 600s hard / 480s target before any work started, and step 4.2 may only have tightened it. Confirm the final value is one you accept.
  2. Run `npm test` yourself and confirm the reported figure is under the ceiling on comparable hardware.
  3. Confirm `test:SuiteCoverage.TestNameInventoryPreserved` passes, then read the enumerated removal list — every removed test must carry a reason you accept.
  4. Confirm `test:SuiteFixture.CarriesTagsForVersionResolution` passes; the inventory cannot detect that loss on its own.
  5. Open the most recent PR run: both platforms, separate named steps, per-OS artifacts attached.
  6. Confirm `test:Ci.SeededFailureIsRed` exists as a test rather than a prose claim.

  **Verify:** ceiling never raised, coverage inventory preserved with reasons, tags retained, both platforms green with per-OS diagnosable output, and the seeded-failure proof durable.

  **Rollback:** each phase lands as its own commit with catalogs regenerated inside the phase that changes them, so any single phase reverts cleanly.

  </details>
