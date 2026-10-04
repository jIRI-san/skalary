# References

## Current authority and implementation

- `docs/design-notes/.design-notes.md` and `docs/architecture-notes/.architecture-notes.md`.
- `docs/design-notes/project/simplicity-first.design.md`, `copilot-customizations.design.md`,
  and `dev-rules.design.md`.
- `docs/design-notes/architecture/plan-workflow.design.md`, `review-reporting.design.md`,
  `plugin-registry.design.md`, `plugin-evals.design.md`, and `architecture-notes.design.md`.
- `docs/architecture-notes/arch-direct-workflow.md`.
- `.github/skills/cip/SKILL.md`, `assets/decision-protocol.md`,
  `assets/pre-confirmation-review.md`, and `assets/model-aliases.psd1`.
- `scripts/skalary/{New-Plan,Get-PlanIndex,Get-DirectPlanArtifactConsumerContext,Test-Plan,Set-PlanStage,Archive-Epic}.ps1`,
  `PlanState.psm1`, and `DirectWorkflow.psm1`.
- `plugins/{design-review,self-improvement,continue-implementation}/skills/**/SKILL.md`;
  `plugins/skalary-config/plugin.json` as a manifest/scaffold example.

## Historical intake

Filtered `Get-PlanIndex.ps1` discovery preceded exactly three selected confined, secret-screened
Markdown reads through `Get-DirectPlanArtifactConsumerContext.ps1`, accepted with provenance and
collision-safe untrusted framing on 2026-10-03:

- `57cc2c`, Intent, `reuses`: operator intent and approved design shape. Preserve existing plan assets.
- `7ce29c`, Decisions, `reuses`: prior deletion-led cleanup. In particular, a manual cache cleanup tool
  remained supported despite no runtime caller; this informs dead-code false-positive handling.
- `367e9a`, Design, `reuses`: direct advisory workflows and source/distribution boundaries.
  Historical vendor rosters, call budgets, receipt references and terminal review details have been
  superseded by current contracts; they are not imported as policy.

## Parallel review-improvements coordination

Parent session `6c9111a8-434c-4b36-b582-90f30fd0231d` supplied review/intent decisions; implementation
session `d1081629-3b87-4cad-b7bf-a23effd281da` supplied helper signatures and integration limits.
Plan `9abf21` is on the parent branch at `c9e12ec6`; implementation branch
`jiri-san-evidence-led-review-intent-alignment` through `91310c78` was reported not merged into main
or parent at the end of that session.

Reported reuse targets:

- Extended `Get-PlanIndex.ps1 -RepoRoot -Format Markdown|Json -Filter` searches active/archived plan
  intent and epic Goal/Decomposition notes. Candidates include provenance and max three snippets of
  at most 240 characters per artifact; omissions/errors remain explicit.
- Bounded `Get-DirectPlanArtifactConsumerContext.ps1` supports at most three selected artifacts and
  includes `Intent`/`EpicIntent`/`Design`/`Decisions` plus advisory review/learning kinds.
- No archive/completion implementation was changed by that branch.

These messages are coordination evidence, not an API specification. Step 1.1 verifies current
integrated source; existing inventory and bounded intent intake suffice when enhanced snippets are
absent, with explicit search/epic-context gaps. This plan does not merge or mutate those branches.
