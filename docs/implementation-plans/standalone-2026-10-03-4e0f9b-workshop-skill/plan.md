# 4e0f9b: Workshop skill
<!-- plan-id: 4e0f9b -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:5a0289c5e62158bc6e1cc339cff437ffaa705db2517b1f6c38a452f1db4051a9 -->
<!-- execution-mode: manual -->
<!-- scope: step -->
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

## Phase 1: Workshop workflow and integration comparison
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Author and register the workshop with its consumer-smoke case (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-7, REQ-8, RISK-1, RISK-2, RISK-3, RISK-4, RISK-7, RISK-8) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** standalone source plugin covers interview, approved alternatives, isolated runnable
  vertical slices, inspection/integration maps, and operator selection.

  **Likely touchpoints:** new `plugins/workshop/plugin.json`, `skills/ws/SKILL.md`,
  `skills/ws/assets/worktrees.md`, existing `tests/ConsumerInstallFixture.psm1` smoke switch,
  focused `Workshop.ConsumerSmoke` test assertion.

  **Constraints:** inspect pinned stash read-only for reuse; no blanket restore. At most three variants,
  no workshop formal gates/reviews/new runtime machinery; use native tools and existing safety rules.
  Register the new plugin and its explicit consumer-smoke arm in one coherent change; no expanded
  global architecture contract. Default serial direct worktrees; approved native sessions when needed.

  **Verify:** `test:Workshop.ConsumerSmoke` and focused payload/scope/isolation/vertical-slice/
  integration-map skill contracts added in 1.2.
  Walk the instruction sequence against UI and component scenarios before proceeding.

  **Stop/escalate when:** a host cannot target isolated worktrees, a base mismatch occurs, or repository
  contracts demand a conflicting lifecycle. Ask for host action/scope decision; do not add adapters.

  </details>
- [ ] 1.2 Add explicit draft CIP handoff and focused behavior contracts (REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, RISK-2, RISK-3, RISK-5, RISK-6, RISK-9) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** CIP recognizes selected prototype input without treating it as confirmed criteria;
  focused tests protect vertical slices, integration explanations, approval order, retention, and identity.

  **Likely touchpoints:** CIP source skill, `tests/skalary/Workshop.Tests.ps1`,
  `tests/ConsumerInstallFixture.psm1`, existing skill contract tests.

  **Constraints:** changed/missing winner identity stops for confirmation; redesign allowed. Keep check
  IDs in requirements stable. Prompt contracts alone do not prove live host behavior.
  Transfer the handoff explicitly by app message or pasted CIP input; test corrections versus
  newly approved concepts and the lifetime cap, retaining replaced worktrees.

  **Verify:** smallest Pester selection covering Workshop tests and existing CIP contracts; fixture
  walkthroughs confirm central behavior is real and both comparison styles expose touched paths.

  </details>

## Phase 2: Distribution, documentation, and host verification
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Generate install surfaces and document the workshop boundary (REQ-1, REQ-8, RISK-7) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** source plugin is discoverable/installable; dogfood and human/agent docs reflect actual behavior.

  **Likely touchpoints:** design-note index/new workshop note, plan-workflow/customizations notes,
  operator-guide README/workshop page, `tests/skalary/OperatorGuide.Tests.ps1`, README, plugin
  manifests, generated registry/marketplace/dogfood.

  **Constraints:** use existing ordered generators, canonical source ownership and version bumps;
  do not restore stale generated files from stash or introduce scaffolds/state formats.
  Update the explicit guide inventory/link assertions, including its existing configuration omission.

  **Verify:** registry check, script/marketplace/dogfood detect-only modes, skill-size gate,
  `test:Workshop.ConsumerSmoke`, focused guide inventory/link checks, documented guide/design-note markers.

  </details>
- [ ] 2.2 Verify host walkthroughs and complete the normal plan workflow (REQ-3, REQ-4, REQ-5, REQ-6, REQ-8, RISK-1, RISK-3, RISK-5) [after: 2.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** small UI/component scenarios exercise approval, isolation, runnable slices,
  integration-map comparison, selection, and draft CIP handoff; available host behavior is verified.

  **Likely touchpoints:** existing focused test fixtures, new skill/docs, host-native worktree/session tools.

  **Constraints:** no premium eval campaign or broad suite. Request operator verification for unavailable
  hosts; do not mark live checks complete using regex tests. Respect explicitly approved fixture cleanup.
  Normal implementation-plan final review/compaction rules apply, not inside workshop prototypes.

  **Verify:** focused tests/gates and actual host walkthrough outcomes with interface or layout,
  entrypoint/connection/insertion/touched-path explanations. Normal whole-plan completion requirements.

  **Stop/escalate when:** a required host cannot be exercised or a runnable central slice is not observable;
  report the missing check and request operator action before claiming complete support.

  </details>
