# References

## Epic and dependency

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `367e9a`, which delivered the direct workflow, bounded native roles, and current
  review/planning/autopilot model surfaces this child will retune.
- Supersedes the economic assumptions, but not the simplicity boundaries, in
  `docs/design-notes/explorations/agent-cost-optimization.design.md`.

## Pricing and workflow guidance

- GitHub AI model pricing, authoritative current rates:
  <https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing>
- GitHub model comparison:
  <https://docs.github.com/en/copilot/reference/ai-models/model-comparison>
- GitHub AI-usage optimization:
  <https://docs.github.com/en/copilot/tutorials/optimize-ai-usage>
- Workflow recommendations supplied by the operator:
  <https://movarnell.github.io/Copilot-Links/models.html#workflow-flows>

The external workflow guide's GPT-5.6 Sol promotion ended on 2026-09-03. Planning must use the
official post-promotion prices current on 2026-09-05: Luna 20/120, Terra 200/1,200, Sol 400/2,000,
and Opus 5 500/2,500 credits per million input/output tokens. Sol and Terra long-context input rates
double above their published thresholds.

## Relevant repository guidance and surfaces

- `docs/architecture-notes/arch-direct-workflow.md`
- `docs/architecture-notes/arch-eval-gate-separation.md`
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/architecture/plugin-evals.design.md`
- `docs/design-notes/architecture/review-reporting.design.md`
- `docs/design-notes/explorations/agent-cost-optimization.design.md`
- `.autopilot.json`, `plugins/autopilot/`, and `.github/skills/autopilot/`
- `plugins/*/evals/waza/`
- `tools/model-allowlist.psd1`

## Operator provenance

On 2026-09-05 the operator reduced the available monthly budget from effectively unlimited usage to
200,000 AI credits. They required a new pass over model selection and skill structure, explicitly
retired long context because of its doubled cost, and asked that the active epic absorb the work
before continuing with self-improvement.
