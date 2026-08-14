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

The same gap exists for **simultaneous** work. The current guide bounds selected work to 6 or 14 reviewer
invocations and reports against an advisory 28-invocation round budget, but it defines no maximum number of
subagents in flight. A large `/cr` or `/dr` run can therefore launch the whole fleet together and trigger LLM
provider throttling. Todos make that fan-out visible only while it happens; they do not schedule it.

## Operator decision (2026-08-14)

- One shared fleet scheduler controls Designer, Requirements Validator, Judge, Implementor, and reviewer
  admission. `/cr` and `/dr` adopt that scheduler in the same change; they do not implement local throttles.
- Maximum simultaneous agent invocations: **4 per orchestrated fleet**, including review fleets.
- Total concern/model selection remains size-scaled at the existing 6 or 14 invocations; the cap creates
  bounded waves and does not reduce independent two-model discovery.
- The pre-run dispatch plan reports selected agents and roles, concern/model pairs where applicable, total
  calls, concurrency cap, wave order, and anything omitted before dispatch begins.
- Provider throttling stops admission of later waves and follows a bounded, visible retry policy. A missing
  reviewer remains an explicit degraded attendance state; it is never treated as "ran and found nothing."
- Reading batches still split reviewer input only. They never multiply concern passes or bypass the in-flight cap.

## Prior art

- `plugins/code-review/skills/cr/assets/dispatch-guide.md` §4 — scope tiers and concern sets.
- `tests/skalary/DispatchGuide.Tests.ps1` — `test:dispatch-guide-scaling-thresholds`,
  `test:dispatch-budget-reported`.
- `scripts/skalary/Build-ReviewReport.ps1` — post-run invocation count.
- `plugins/design-review/skills/dr/SKILL.md` — the same dispatch shape on the design-review surface;
  whatever lands here has to land there too.
- `b0c0d3` REQ-9 and RISK-4 — preserve size-scaled independent fan-out while addressing the recorded
  latency, credit-burn, and provider-pressure risk.

## Note

Independent of sibling `ca8ba8 review-corroboration-truth`. That plan makes the report honest about
what *did* happen; this one makes the run legible about what *will* happen. Neither blocks the
other, but the two together are what "the review describes itself truthfully" means.
