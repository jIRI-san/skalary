# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 0-1 (2026-08-14): the operator required vertical phases, high-level Mermaid design, optional call stacks, relentless end-user-experience elicitation, MVP discovery, decision capture, and full-plan completion rather than MVP-only scope.
- Epic `bcece1` Goal, Decomposition notes, MVP checkpoint, and Initial execution policy.
- `docs/design-notes/explorations/intent-and-domain-capture.design.md`: provenance, rephrase-and-confirm interviewing, and domain-knowledge gaps captured during `b0c0d3`.
- `docs/design-notes/explorations/design-rfc-artifacts.design.md`: concise Mermaid-backed design proposal, approval, trigger, and staleness questions.
- `docs/design-notes/architecture/plan-workflow.design.md`: plan layout resolution, stage-aware validation, typed evidence, intent, prior-art, and script-only mutation contracts.
- `docs/design-notes/project/copilot-customizations.design.md`: `/cip`, `/ci`, review, bundling, and dogfood distribution boundaries.
- `docs/design-notes/architecture/plugin-evals.design.md`: deterministic Tier-1 structural enforcement and report-only Tier-2 boundary.
- `docs/design-notes/architecture/plugin-registry.design.md`: independent plugin versioning, payload declaration, script/schema bundling, dogfood, registry, and marketplace closure.
- `docs/design-notes/architecture/autopilot-execution.design.md` and `autopilot-skill.design.md`: installed script boundary, dependency admission, progress retention, and exit-42 operator handoff.
- `docs/design-notes/architecture/review-reporting.design.md`: bounded DR context handoff and direct-read authority limits.
- Prior plan `b0c0d3` REQ-4: the current `intent.md` substrate and intent gate that this plan extends.
- Dependency `4dd933`: supplies bounded related-plan artifact context before this interview flow consumes prior intent and designs.

## Cross-plan index reconciliation

- Consulted `.github/skills/cip/scripts/Get-PlanIndex.ps1` on 2026-08-21 with the confirmed topic filter; the result contained 8 plans, 3 requirements, 2 risks, and 12 decisions.
- `4dd933` and `6a629b` are extended; `25aa23` and `21f21d` are reused; `34088e`, `9fda0b`, and `a5ad22` contribute limited sequencing principles only. Exact relationships are recorded in `assets/decisions.md`.
- The index returned `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. Prior-art coverage is explicitly incomplete for that folder; no silent inference was made.
- Current plan `57cc2c` appeared only through its scaffold placeholders and preliminary decisions, so it was not treated as external prior art.
