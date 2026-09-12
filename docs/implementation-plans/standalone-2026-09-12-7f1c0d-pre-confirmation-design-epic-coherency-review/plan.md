# 7f1c0d: Pre-confirmation design and epic coherency review
<!-- plan-id: 7f1c0d -->
<!-- cip-stage: done -->
<!-- planning-confirmed: sha256:7d00db3f3914cc2cd8f76234cabe1f1384fdd9433366471f91982e43fc13d8fc -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- execution-mode: host-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Domain model — [assets/domain.md](assets/domain.md)
- Approved design — [assets/design.md](assets/design.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Review results — advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`
- AI-credit ledger — `assets/ai-credits.json` (created by autonomous execution)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Pre-confirmation design review
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Add the mandatory planning-owned review and applicability flow (REQ-1, REQ-2, REQ-4, REQ-5, REQ-6, REQ-7, RISK-1, RISK-2, RISK-5, RISK-6) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/cip` completes the draft, dispatches one `secondary-model-high` design review, dispatches one `primary-model-high` applicability evaluation, shows all findings and recommendations, asks the operator what to apply, edits only the selected plan changes, and only then performs final planning confirmation.

  **Likely touchpoints:** `plugins/create-implementation-plan/skills/cip/SKILL.md`, a concise CIP-owned review guide under `skills/cip/assets/`, and `plugins/create-implementation-plan/plugin.json`.

  **Constraints:** preserve reviewer read-only behavior; keep the user authoritative; use ephemeral fix/simplify/defer/ignore recommendations rather than persisted dispositions; do not rerun after edits; do not alter the existing `planning-confirmed` digest contract or add review state.

  **Verify:** focused skill-contract tests prove the ordering, exact aliases, all-findings presentation, one consolidated user-selection step, direct selected edits, and absence of automatic clean/rerun requirements.

  **Stop/escalate when:** the two-call workflow cannot be expressed without conflicting with the installed DR read-only contract; resolve that contract directly rather than adding a parallel reviewer or state machine.

  </details>
- [x] 1.2 Align the DR reviewer contract with the planning-owned pass (REQ-2, REQ-4, REQ-7, REQ-8, RISK-1, RISK-4, RISK-6) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the installed DR contract supports a caller-selected pre-confirmation mode in which `secondary-model-high` reports evidence-backed findings without treating them as mandatory fixes, while `/cip` retains applicability judgment and mutation ownership.

  **Likely touchpoints:** `plugins/design-review/skills/dr/SKILL.md`, its agent/prompt only if needed to preserve the thin-shim boundary, and review-policy structural tests.

  **Constraints:** standalone `/dr` remains read-only and useful; the planning mode must not create a judge panel, corroboration run, fallback fleet, report authority, or a requirement to obtain `clean`.

  **Verify:** focused tests distinguish ordinary standalone review routing from the explicit pre-confirmation reviewer role and retain mandatory security/confinement guards.

  </details>

## Phase 2: Epic coherency in the same pass
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add bounded epic context and coherency checks to the planning review (REQ-3, REQ-4, REQ-6, REQ-8, RISK-2, RISK-3, RISK-4, RISK-7) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** when the current plan has an epic marker, the same secondary review reads the epic intent and structure, targeted sibling intent/interfaces/dependencies/decisions, and relevant current implementation from completed siblings, then reports scope, ownership, dependency, interface, sequencing, duplication, and delivered-behavior conflicts beside the design findings.

  **Likely touchpoints:** the CIP review guide and skill, existing `Resolve-Epic`/`Get-EpicRollup` discovery, built-in read/search behavior, and focused epic fixtures in planning tests.

  **Constraints:** do not read every sibling artifact, replay historical logs, mutate the epic or sibling plans, or add a coherency command, helper service, verdict file, receipt, hash, or lifecycle stage. Prefer current code/contracts over completed-plan claims when checking delivered behavior.

  **Verify:** focused fixtures cover a compatible child, duplicated ownership, unnecessary dependency, and a direct conflict with an implemented sibling contract while proving standalone plans do not load epic context.

  **Stop/escalate when:** the epic marker cannot resolve or the relevant delivered interface cannot be established cheaply; surface the missing context to the operator instead of inferring compatibility.

  </details>
- [x] 2.2 Prove user-directed triage without review machinery (REQ-1, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, RISK-1, RISK-2, RISK-5, RISK-6) [after: 2.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** structural and behavioral tests prove that all findings remain visible, `primary-model-high` recommends fix/simplify/defer/ignore using wider project context and Simplicity First, the operator chooses, and `/cip` applies only selected changes without a second review.

  **Likely touchpoints:** `plugins/create-implementation-plan/evals/cip.Tests.ps1`, focused `tests/skalary/*` planning/review contract suites, and optional bounded Waza cases only where deterministic instruction checks cannot cover the behavior.

  **Constraints:** update obsolete cheap-first/risk-selected expectations narrowly; retain the global three-call ceiling for unrelated workflows while making this confirmed two-call gate explicit; do not make premium evaluation part of the focused default test path.

  **Verify:** focused Pester tests pass and fail on removal of any required ordering, model alias, epic lens, user-selection, no-rerun, or no-state clause.

  </details>

## Phase 3: Documentation and distribution
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Update architecture, design, and operator guidance (REQ-1, REQ-3, REQ-5, REQ-7, REQ-8, REQ-9, RISK-1, RISK-3, RISK-6) [after: 2.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** active architecture/design notes and operator guides describe the pre-confirmation ordering, two-model responsibilities, epic-context bounds, user authority, direct edit behavior, and explicit rejection of the retired coherency/review lifecycle.

  **Likely touchpoints:** `docs/architecture-notes/arch-direct-workflow.md`, `docs/design-notes/architecture/{plan-workflow,review-reporting}.design.md`, `docs/design-notes/project/copilot-customizations.design.md`, and `docs/operator-guide/{planning,reviews}.md`.

  **Constraints:** keep the explanation concise and consistent across surfaces; preserve existing implementation-time CR/finalization contracts and the unchanged Git criteria baseline.

  **Verify:** operator-guide and design-note contract tests recognize the new ordering and no-machinery boundary.

  </details>
- [x] 3.2 Synchronize consumers and validate the complete workflow (REQ-9, REQ-10, RISK-4, RISK-6, RISK-7) [after: 3.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** canonical plugin sources, manifest/version/catalog metadata, and dogfood `.github` copies converge; focused planning, review, model-policy, operator-guide, consumer-install, and drift tests pass.

  **Likely touchpoints:** `plugins/create-implementation-plan/plugin.json`, `plugins/design-review/plugin.json` if its payload changes, `scripts/skalary/Sync-PluginScripts.ps1`, registry/marketplace outputs, and `.github/skills/{cip,dr}/**`.

  **Constraints:** use existing lifecycle and sync commands; do not hand-maintain generated copies or broaden validation beyond affected plugins unless focused failures require it.

  **Verify:** focused suites plus bundle/dogfood no-drift checks pass with no undeclared payload or generated-output delta.

  </details>
