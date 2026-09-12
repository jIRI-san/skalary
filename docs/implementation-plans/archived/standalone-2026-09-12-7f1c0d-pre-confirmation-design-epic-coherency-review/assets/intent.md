# Intent

## Goal

Make every `/cip` plan receive one lightweight design review before final planning confirmation, and add an epic-coherency lens to that same pass when the plan belongs to an epic.

## Desired outcome

- `secondary-model-high` reviews the complete draft and reports evidence-backed findings.
- `primary-model-high` evaluates which findings apply in the real project and recommends fix, simplify, defer, or ignore.
- The operator sees every finding, selects what to change, and `/cip` edits only the selected items.
- Epic children are checked against epic intent, sibling ownership/interfaces/dependencies, and relevant delivered behavior.
- The revised plan is confirmed and handed to `/ci` without a separate review lifecycle.

## Success signals

- The review always occurs after drafting and before `planning-confirmed`.
- Standalone plans use one design-review lens; epic children add coherency in the same reviewer call.
- Architectural-astronaut proposals remain visible but are not automatically adopted.
- Direct conflicts with implemented sibling work are clearly identified.
- The normal path uses exactly two model calls and no automatic rerun.
- No review receipt, source hash, confirmation ticket, finding registry, or coherency verdict is introduced.

## Non-goals

- Requiring every DR finding to be fixed or obtaining a clean verdict.
- Re-reviewing the plan after the operator-selected edits.
- Restoring review-run, receipt, attendance, corroboration, or durable epic-verdict machinery.
- Changing the existing `planning-confirmed` digest or `/ci` criteria-baseline behavior.
- Automatically editing an epic or sibling plan from a child `/cip` session.
- Changing implementation-time CR, terminal review, or general standalone `/dr` behavior beyond the explicit planning-review mode.

## Definition of done

- The canonical and installed planning/review skills implement the confirmed two-call flow.
- Epic context is targeted, current, and sufficient to detect direct conflicts without loading the entire corpus.
- The operator guide and active architecture/design notes describe the same behavior.
- Focused contract, behavior, consumer-install, and drift checks pass.
