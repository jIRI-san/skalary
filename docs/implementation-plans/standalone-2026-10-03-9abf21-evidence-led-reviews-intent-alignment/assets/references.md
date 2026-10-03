# References

## Current authority and implementation

- Operator conversation, 2026-10-03, this planning session: research, alignment, historical comparison and explicit focused/local-only validation decisions. Selected wording is in intent.md.
- `docs/design-notes/project/simplicity-first.design.md`
- `docs/architecture-notes/arch-direct-workflow.md` and `arch-eval-gate-separation.md`
- `docs/design-notes/architecture/{plan-workflow,review-reporting,plugin-evals,plugin-registry}.design.md`
- `docs/design-notes/project/ci-gates.design.md`
- Planning decision/pre-confirmation protocols; current CR/DR, CI and autopilot instructions.
- Canonical `New-Plan.ps1`, `Get-PlanIndex.ps1`, `Get-DirectPlanArtifactConsumerContext.ps1`, `Invoke-WazaEvals.ps1`, `DirectWorkflow.psm1`.

## Selected historical context

- `57cc2c`, intent/RFC: archived intent confirms original outcome; preserve existing assets, not old lifecycle mechanics.
- `367e9a`, decisions: simple advisory Markdown, current Git evidence and bounded native review. Archived larger budgets are superseded by current contracts.
- `2aa7ec`, intent: local-only/focused baseline; no hosted or replacement aggregate gate.

These three full historical artifacts were consulted alongside the filtered plan index. Other candidate titles were discovery only, not claimed complete historical reconciliation.

## Research grounding

- [Ambig-SWE](https://arxiv.org/abs/2502.13069), February 2025; revised February 2026, ICLR 2026. Detection, targeted clarification and answer use are separate capabilities; gains are benchmark-specific.
- [GitHub agentic code review](https://github.blog/changelog/2026-03-05-copilot-code-review-now-runs-on-an-agentic-architecture/), 5 March 2026: targeted repository context.
- [GitHub review engineering](https://github.blog/ai-and-ml/github-copilot/60-million-copilot-code-reviews-and-counting/): useful findings and developer signals, not comment volume.
- [Anthropic Code Review](https://claude.com/blog/code-review), March 2026: candidate verification/risk-adaptive depth; vendor-reported quality/cost, not local proof.
- [Agent eval guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): outcomes versus traces, regression/capability suites, human-calibrated semantic grading.
- [Context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): just-in-time high-signal context.
- [Agent safety guidance](https://developers.openai.com/api/docs/guides/agent-builder-safety): external text/private-data boundaries; framing is not a complete injection defense.
- [Empirical review-agent study](https://arxiv.org/abs/2604.03196), April 2026, MSR: observational noise/abandonment association, not causal proof or a current-model ranking.

Public research informs heuristics only. It does not authorize model changes, added controls, costs or runtime web access.
