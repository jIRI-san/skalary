# 79cfe1: Concern registry and generated agents
<!-- plan-id: 79cfe1 -->
<!-- epic: 33b1f9 -->
<!-- cip-stage: dr-round-5 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
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
- Evolution log — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Authoring policy and full-graph generator
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Commit the indexed concern-authoring design note and governing ownership updates, then add Git-bound migration provenance, the closed registry, independent schema, literal marker-bearing template, generated-inventory contract, refusal matrix, byte bounds, and Fast policy tests; verify `test:ReviewConcerns.RegistryPolicyAndRefusals` and `test:ReviewConcerns.MigrationProvenanceAndAgentSafety` (REQ-1, REQ-2, REQ-8, RISK-1, RISK-5, RISK-6, RISK-8, RISK-9) `L`
- [ ] 1.2 Implement full-graph render-before-write, marker/inventory adoption, type-specific boundaries, bounded statuses, shared manifest-writer locking, and atomic per-plugin version-first convergence; converge downstream artifacts and verify generator, payload-version, serialization, byte-parity, and safety focused tests before commit (REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-5, RISK-7, RISK-9) [after: 1.1] `L`

## Phase 2: Convergence, versioning, and installed-copy pruning
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Create `ReviewConcernsIntegration.Tests.ps1` and add it to Slow in one edit; add per-family mutation, hostile input/path, malformed marker, culture/order, capability, joint-writer, explicit-base, per-plugin, and bounded atomic-fault fixtures; run focused tests and `npm run test:slow`, then converge downstream artifacts (REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-7, RISK-9) [after: 1.2] `L`
- [ ] 2.2 In the same change, update `ARCH-Install-Confinement`, its source contract, human architecture output, and copy-only docs; then put dogfood copy/prune under the mutation lock with explicit-prior-base inventory, batched receipt/Git authority, total status shapes, preflight-zero-write refusals, and resumable partial failures; verify `test:ReviewConcerns.DogfoodAuthorityAndDistribution`, `test:ReviewConcerns.DogfoodRefusalMatrix`, `test:ReviewConcerns.DogfoodPartialRecovery`, architecture freshness, and `npm run test:slow`, then prove a clean second pass (REQ-6, REQ-8, RISK-2, RISK-3, RISK-10) [after: 2.1] `L`

## Phase 3: Consumer cutover, gate, and contracts
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Cut active consumers to registry-plus-policy joins; add `gate:review-concern-generation`, workflow-hosted `gate:review-concern-payload-version`, event-base plumbing for version and dogfood gates, all CI inventory rows/exits/remedies, per-host capability coverage, sub-5-second Fast-path evidence, and unchanged ceiling assertions; verify `test:ReviewConcerns.GateInventoryAndRuntime`, `test:ReviewConcerns.PayloadVersionGate`, `test:CiGates.InventoryMatchesWorkflow`, then run `npm test` and `npm run test:slow` (REQ-3, REQ-5, REQ-6, REQ-7, RISK-3, RISK-4, RISK-5, RISK-8, RISK-10) [after: 2.2] `L`
- [ ] 3.2 Finish indexed design-note authority updates, run focused review-run/consumer checks, converge every generated artifact, run `npm test` and `npm run test:slow`, then complete final CR/DR and repository validation (REQ-8, RISK-3, RISK-10) [after: 3.1] `M`
<!-- implementation-ready: 2026-08-17 -->
