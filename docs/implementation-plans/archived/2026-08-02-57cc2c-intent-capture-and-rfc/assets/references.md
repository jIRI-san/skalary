# References

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 0-1 (2026-08-14): vertical phases, concise Mermaid design, optional call stacks, end-user experience, MVP discovery, decision capture, and complete delivery.
- Epic `bcece1` goal and accepted simplified cut.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): retain Markdown assets, three checkpoints, one confirmation marker, and invalidation; reject the Interview Gates platform.

## Existing owners reused

- `docs/design-notes/architecture/plan-workflow.design.md`: plan assets, lifecycle stages, layout resolution, typed evidence, `Get-PlanState`, and script-owned mutation.
- `docs/design-notes/project/copilot-customizations.design.md`: `/cip`, `/ci`, review, bundling, and dogfood boundaries.
- `docs/design-notes/architecture/plugin-evals.design.md`: deterministic structural coverage and report-only model evaluation.
- Existing `Set-PlanStage.ps1`, `Get-PlanState.ps1`, layout resolvers, plugin sync/generator scripts, and evidence receipt writer are reused rather than replaced.

## Dependency rationale

- No dependencies. Confirming local intent and design does not require the optional cross-plan artifact resolver or another child plan.
