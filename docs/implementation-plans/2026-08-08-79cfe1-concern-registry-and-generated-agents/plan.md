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

## Phase 1: Concern source and deterministic generator
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add one validated `tools/review-concerns.json` source for the settled seven concern ids, shared guidance, CR/DR variants, and concern-to-ledger mappings, plus one shared agent template that keeps injection guards, read-only tools, context order, and output shape outside free-form substitutions. Add `test:ReviewConcerns.RegistryAndTemplate` (REQ-1, REQ-4, RISK-1, RISK-2, RISK-4) `L`
- [x] 1.2 Implement deterministic `Sync-ReviewConcerns.ps1` generation for all 14 CR/DR concern agents and both mapping views. Validate and render all outputs before writing, confine managed paths, support `-WhatIf`, and preserve explicit per-surface differences; add `test:ReviewConcerns.DeterministicGeneration` (REQ-2, REQ-4, RISK-1, RISK-2, RISK-4) [after: 1.1] `L`

## Phase 2: Adoption and drift proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Generate the current CR/DR agents and mappings, update their manifest entries, and run existing plugin sync, version, dogfood, marketplace, and registry writers. Preserve current agent behavior and review-run v1 ownership; add `test:ReviewConcerns.GeneratedBehaviorAndDistribution` (REQ-2, REQ-3, REQ-4, RISK-1, RISK-3, RISK-4) [after: 1.2] `L`
- [x] 2.2 Add one detect-only drift test that reruns the generator in `-WhatIf` mode and fails on changed, missing, extra, or hand-edited generated agents/mappings. Include a registry mutation proving all expected outputs change and a clean second pass proving determinism: `test:ReviewConcerns.GenerationDrift` (REQ-3, REQ-4, RISK-2, RISK-3, RISK-4) [after: 2.1] `M`

## Phase 3: Documentation and integration
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Update concern-authoring, plugin-registry, and review-reporting design notes; run focused generator/agent tests, structural evals, installed-consumer checks, generated-artifact drift checks, and normal repository validation. Record `review:cr` and `review:dr` without changing review-run v1 (REQ-1, REQ-2, REQ-3, REQ-4, RISK-1, RISK-2, RISK-3, RISK-4) [after: 2.2] `M`
<!-- implementation-ready: 2026-08-17 -->
