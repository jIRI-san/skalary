# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08), which prints
an invocation plan before the review run: concerns selected, model per concern, what was dropped by
the cap, and estimated waves.

## The gap

`plugins/code-review/skills/cr/SKILL.md` L57 asks the orchestrator to add a todo per dispatch, so
the fan-out becomes visible *as it happens*. `scripts/skalary/Build-ReviewReport.ps1` L244 reports
`Dispatched N of M budgeted invocations` *after* the run. Neither is a statement of what the run
intends to do before it starts.

The part that matters most is **what was dropped**. `tests/skalary/DispatchGuide.Tests.ps1`
`test:dispatch-budget-reported` confirms the 28-invocation budget is *reported, not enforced*, and
concern selection scales with change size (dispatch-guide §4). So concerns can fall out of a run
with nothing stating which ones, or why. The operator cannot tell a deliberately narrowed review
from a silently truncated one.

## Prior art

- `plugins/code-review/skills/cr/assets/dispatch-guide.md` §4 — scope tiers and concern sets.
- `tests/skalary/DispatchGuide.Tests.ps1` — `test:dispatch-guide-scaling-thresholds`,
  `test:dispatch-budget-reported`.
- `scripts/skalary/Build-ReviewReport.ps1` — post-run invocation count.
- `plugins/design-review/skills/dr/SKILL.md` — the same dispatch shape on the design-review surface;
  whatever lands here has to land there too.

## Note

Independent of sibling `ca8ba8 review-corroboration-truth`. That plan makes the report honest about
what *did* happen; this one makes the run legible about what *will* happen. Neither blocks the
other, but the two together are what "the review describes itself truthfully" means.
