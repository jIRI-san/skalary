# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08), which prints
an invocation plan before the review run: concerns selected, model per concern, what was dropped by
the cap, and estimated waves.

## Epic discussion provenance

- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 90-92 (2026-08-08): selected as an independent child because declaring dispatch before a run delivers value without the corroboration work.
- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 2-5 (2026-08-14): the operator broadened the contract from review throttling to one shared Designer/Requirements Validator/Judge/Implementor/reviewer fleet for `/cip`, `/ci`, `/cr`, `/dr`, and later `/cep` review, with at most four calls in flight.
- Epic `bcece1` Initial execution policy records the accepted cap, wave, attendance, and provider-throttling behavior.

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

## Review-run contract boundary

This child depends on `c21cdc review-report-as-data`. `c21cdc` owns the versioned frozen-task/result schemas,
validation, persistence, derived attendance, and report rendering. This child owns the shared fleet scheduler
and therefore later **produces** the frozen task-plan records before admission/dispatch; it does not define a
second attendance or artifact format. `ca8ba8` remains the later consumer that evaluates similarity and
corroboration truth. The three ownership seams are plan, record/render, and corroborate.
