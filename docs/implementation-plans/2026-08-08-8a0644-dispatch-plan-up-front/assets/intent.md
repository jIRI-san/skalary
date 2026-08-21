# Intent

> Captured from the 2026-08-08 review comparison and the 2026-08-14 `bcece1` fleet discussion; confirmed by the operator on 2026-08-21.

## Goal

Make every orchestrated planning, implementation, and review fleet declare its intended work before dispatch, admit at most four task leases per workflow run, and report the limits of host/provider observability without silently dropping coverage.

## Desired outcome

One shared fleet scheduler serves `/cip`, `/ci`, `/cr`, and `/dr`, and supplies the activation handoff consumed by the later `/cep` coherency-review plan. Before calls begin it reports selected roles or concern/model pairs, omissions, budgets, projected waves, ready-order and throttling policy; after execution it reports attendance against that declaration. Provider concurrency is verified only when typed host telemetry exists and otherwise stays explicitly unverified.

## Success signals

- The operator can see what will run, what was omitted, and why before the first invocation.
- No orchestrated fleet records more than four active admission leases; actual host concurrency is never overclaimed.
- Larger fleets run in declared waves without reducing selected independent coverage.
- Provider throttling pauses or boundedly retries later admission and remains visible in the outcome.

## Non-goals

- Reopening the seven-concern review taxonomy.
- Treating reading batches as new concern passes.
- Unlimited parallel fanout or silent replacement calls after throttling.

## Definition of done

- Planning, implementation, code review, and design review use one tested dispatch-plan, admission, attendance, and degradation contract; epic review has a tested conformance and activation handoff to `25aa23`.
