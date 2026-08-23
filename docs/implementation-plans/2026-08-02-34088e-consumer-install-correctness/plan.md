# 34088e: Consumer install correctness
<!-- plan-id: 34088e -->
<!-- cip-stage: drafted -->
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

## Phase 1: Foreign consumer fixture and reference closure
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Build one foreign-repository fixture from active plugin manifests by invoking the production installer and existing test helpers. Poison skalary source paths, derive expected installed files from manifests, and add `test:ConsumerInstall.ForeignFixtureInventory` for missing, extra, hash-mismatched, escaping, and stale mappings (REQ-1, REQ-5, RISK-1, RISK-4, RISK-5) `L`
- [x] 1.2 Extend the current runtime-reference scan to reject source-tree assumptions and undeclared runtime assets across the supported reference grammar. Pair static findings with the foreign fixture and add `test:ConsumerInstall.RuntimeReferenceClosure` for installed, bundled, scaffolded, missing, and dynamic-reference cases (REQ-2, REQ-5, RISK-1, RISK-2, RISK-5) [after: 1.1] `L`

## Phase 2: Installed behavior and scaffold lifecycle
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add one representative installed smoke per active plugin, deriving attendance from active manifests and using existing Pester/process helpers. Each smoke must load installed payloads and either exercise deterministic behavior or reach its expected offline preflight without source, network, or credential fallback; add `test:ConsumerInstall.ActivePluginSmokeMatrix` (REQ-3, REQ-5, RISK-1, RISK-3, RISK-5) [after: 1.2] `L`
- [~] 2.2 Execute every declared first-use scaffold owner in the foreign fixture and verify starter content, idempotence, modified-target preservation, confinement, hostile input refusal, and retry using `test:ConsumerInstall.FirstUseScaffoldLifecycle` (REQ-4, REQ-5, RISK-3, RISK-4, RISK-5) [after: 2.1] `L`

## Phase 3: Distribution proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Use current plugin sync, version, registry, marketplace, dogfood, and test infrastructure to converge changed payloads. Add `test:ConsumerInstall.DistributionDrift` and run focused install tests, structural evals, and normal repository validation without introducing a separate probe schema or hosted proof protocol (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 2.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review the manifest-derived fixture, runtime-reference closure, active-plugin smoke attendance, scaffold confinement, and distribution drift; record `review:cr` before archival (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) @human [after: 3.1] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Run `@cr` over the consumer fixture, runtime-reference scanner, smoke matrix, scaffold lifecycle, generated distribution, and updated owning notes.
  2. Return blocking findings to the owning phase; otherwise record the review result and rebuild the evidence receipt.

  **Verify:** `review:cr` is recorded; every required marker in `assets/evidence.md` is `✓`; the manifest and smoke sets match; source-path canaries remain untriggered; scaffold refusal cases fail before unsafe mutation; and drift checks pass without mutation.

  **Rollback:** Do not approve or archive. Mark the affected step `[~]`, repair the fixture or installed owner, and rerun focused checks.

  </details>
