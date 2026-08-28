# 2366ad: Cross-repo si and review standards
<!-- plan-id: 2366ad -->
<!-- cip-stage: done -->
<!-- depends-on: 1936cb, 79cfe1 -->
<!-- epic: 33b1f9 -->
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

## Phase 1: Bounded consumer-to-upstream transport
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add one bounded typed export artifact produced from the existing `1936cb` capture, ledger, and SI activity records. Include source identity, candidate text, provenance, and disposition context; redact secrets, reject oversize input before writing, fence all imported text as untrusted, and add `test:CrossRepoSi.ExportBoundsRedactionAndReplay` (REQ-1, REQ-5, RISK-1, RISK-2, RISK-5) `L`
- [x] 1.2 Add the handoff that opens or accepts a clean upstream checkout, loads that checkout's instructions, imports the artifact as untrusted context, and invokes normal upstream `/si` for small changes or `/cip` for plan-sized work. Preserve existing `/si` scope, draft-PR, and never-auto-merge controls; add `test:CrossRepoSi.CleanUpstreamHandoff` (REQ-2, REQ-5, RISK-1, RISK-2, RISK-3, RISK-5) [after: 1.1] `L`

## Phase 2: Generic and repository-local review standards
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Extend the `79cfe1` concern source model with optional generic review-standard entries and add a bounded resolver for an optional repo-owned `docs/review-standards.md`. Local entries may extend or replace only explicitly localizable generic guidance; absence leaves generated CR/DR behavior unchanged. Add `test:ReviewStandards.GenericLocalResolution` (REQ-3, REQ-5, RISK-4, RISK-5) `L`
- [ ] 2.2 Feed the resolved standards into existing CR/DR dispatch inputs without changing review-run v1 publication or authority. Use existing generator, plugin sync, version, registry, marketplace, and dogfood writers; prove generic-only, local-extension, malformed-local, and installed-consumer cases with `test:ReviewStandards.InstalledConsumptionAndDrift` (REQ-3, REQ-4, REQ-5, RISK-4, RISK-5) [after: 2.1] `L`

## Phase 3: Integrated proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Run the focused transport and standards tests, required structural evals, generated-artifact drift checks, and normal repository validation; update only the owning self-improvement, review-reporting, and concern-generator notes (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.2, 2.2] `M`
- [ ] 3.2 Review the bounded export, upstream instruction boundary, optional local standards precedence, and unchanged review-run v1 authority; record `review:cr` and leave typed evidence ready for plan crosscheck (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `S`
