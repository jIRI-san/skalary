# Intent

> Preliminary context captured from the 2026-08-08 review comparison and the 2026-08-14 `bcece1` fleet discussion. `/cip` must confirm and refine it.

## Goal

Make every orchestrated planning, implementation, and review fleet declare its intended work before dispatch and bound concurrent provider load without silently dropping coverage.

## Desired outcome

One shared fleet scheduler serves `/cip`, `/ci`, `/cr`, `/dr`, and `/cep` coherency review. Before calls begin it reports selected roles or concern/model pairs, omissions, total invocations, a maximum of four in flight, wave order, and throttling policy; after execution it reports attendance against that declaration.

## Success signals

- The operator can see what will run, what was omitted, and why before the first invocation.
- No orchestrated fleet has more than four agent invocations in flight.
- Larger fleets run in declared waves without reducing selected independent coverage.
- Provider throttling pauses or boundedly retries later admission and remains visible in the outcome.

## Non-goals

- Reopening the seven-concern review taxonomy.
- Treating reading batches as new concern passes.
- Unlimited parallel fanout or silent replacement calls after throttling.

## Definition of done

- Planning, implementation, code review, design review, and epic review use one tested dispatch-plan, admission, wave, attendance, and degradation contract.
