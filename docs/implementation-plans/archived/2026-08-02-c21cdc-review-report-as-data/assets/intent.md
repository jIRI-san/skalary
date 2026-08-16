# Intent

<!-- Captured during the /cip interview and reconstructed from session 8706d364-f92e-4056-bb1b-40a59b015d38. -->

## Goal

Make code- and design-review collation produce a trustworthy, bounded data artifact instead of prose assembled through generated PowerShell source.

## Desired outcome

`/cr` and `/dr` pass validated structured findings and actual dispatch outcomes to one generic formatter through a stable, once-approved command. The formatter emits a compact chat summary and a complete durable report that distinguish no findings from missing, failed, degraded, or incomplete review work.

## Success signals

- Reviewer text is written as data and never parsed as PowerShell source.
- The report derives attendance, invocation counts, and completion state from the dispatched task set rather than accepting model-authored totals.
- Empty findings from a completed reviewer are distinguishable from a reviewer that failed, was omitted, or never returned.
- Chat output is materially smaller than the measured 66 KB report while the durable report preserves every finding and useful reviewer detail.
- Duplicate bodies are collapsed only during rendering; reviewers still discover findings independently and corroboration evidence is not traded away for size.
- `/cr` and `/dr` use the same validated input and rendering contracts, with deterministic output across ordering and locale.

## Non-goals

- Detecting whether the runtime served the model that was requested; model identity remains unobservable from inside the session.
- Detecting near-identical outputs or deciding whether nominally distinct model results count as independent corroboration; sibling plan `ca8ba8` owns that policy.
- Changing the seven-concern review taxonomy, reviewer dispatch scheduling, fleet concurrency, or provider throttling.
- Dropping findings at dispatch time, priming one reviewer with another reviewer's output, or replacing the complete durable report with a lossy summary.
- Reworking unrelated evidence receipts, CI test-run transcripts, or the self-improvement harvest lifecycle.

## Definition of done

The same fixed invocation safely collates hostile and ordinary reviewer text for both `/cr` and `/dr`; malformed or off-roster input fails closed; the report truthfully records task attendance and terminal state; bounded summary and complete durable renderings are deterministic; independent discovery is preserved; consumer-installed copies, tests, guides, design notes, plugin metadata, marketplace, registry, and dogfood payloads are synchronized and green.
