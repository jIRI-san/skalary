# ca8ba8: Review corroboration truth
<!-- plan-id: ca8ba8 -->
<!-- depends-on: c21cdc -->
<!-- epic: 33b1f9 -->
<!-- cip-stage: done -->
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
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Observable corroboration derivation
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add one deterministic normalization helper for each raw finding's title, body, and action. Within an existing merge group and across distinct declared reviewers, flag exact normalized matches and clearly near-duplicate text using one documented conservative lexical rule with a minimum-content guard. Keep raw findings unchanged and add `test:ReviewReport.CorroborationNormalizationAndSimilarity` (REQ-1, REQ-5, RISK-1, RISK-2, RISK-5) `L`
- [x] 1.2 Extend current report collation to derive `corroborated`, `single-source`, `suspicious`, or `degraded` support for each finding from attendance and similarity. Suspicious or degraded support cannot elevate severity and suspicious support forces `needs-review`; add `test:ReviewReport.CorroborationSeverityAndVerdict` (REQ-2, REQ-5, RISK-1, RISK-2, RISK-3, RISK-5) [after: 1.1] `L`

## Phase 2: Existing report and retained evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Extend the existing review report's structured finding and rendered views with support count, attendance state, similarity flag, corroboration state, raw severity, effective severity, and reason. Preserve all raw findings and current review-run v1 publication, verification, replay, cleanup, and retained report/receipt behavior; add `test:ReviewReport.CorroborationRenderingAndRetention` (REQ-3, REQ-4, REQ-5, RISK-3, RISK-4, RISK-5) [after: 1.2] `L`
- [x] 2.2 Extend existing review-report fixtures for exact duplicates, clearly near duplicates, unrelated boilerplate, single source, incomplete attendance, malicious echo, input-order stability, and unchanged clean elevation. Prove callers cannot supply derived corroboration or effective severity with `test:ReviewReport.CorroborationMatrix` (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 2.1] `M`

## Phase 3: Distribution and integration evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Synchronize CR/DR bundles, dogfood, manifests, versions, marketplace, and registry through existing writers; update review-reporting guidance and run focused report tests, installed-consumer checks, structural evals, and normal repository validation. Record `review:cr` (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 2.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Finalization gate: run the plan crosscheck, verify suspicious/degraded support never elevated severity, retain the verified review/evidence pair through the existing v1 lifecycle, and archive only with an all-green receipt (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 3.1] `S`

## Known Plan Issues

- The conservative lexical rule can miss semantic paraphrases. Reports state only that no suspicious similarity was observed; they never claim served-model independence.
- A hostile reviewer can echo another output and force `needs-review`, suppressing otherwise valid elevation. This fail-closed denial of confidence is accepted: findings remain visible, raw severity is preserved, and suspicion can never approve or elevate.
