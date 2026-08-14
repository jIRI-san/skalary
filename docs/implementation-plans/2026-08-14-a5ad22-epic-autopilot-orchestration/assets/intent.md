# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Let one host-side `/ci` mode drive an eligible epic through isolated container-autopilot runs, one child plan at a time.

## Desired outcome

The host owns epic selection, durable state, deterministic `NextChild`, child branch and runtime lifecycle, terminal verification, merge handoff, and graph refresh. Each fresh container owns exactly one drafted child plan and cannot select siblings, mutate host state, or satisfy dependencies before its branch is merged.

## Success signals

- The loop resumes safely after an editor or process restart from schema-validated host state.
- Only drafted, valid, unblocked children launch, and one child runs at a time for the MVP.
- Failed, degraded, conflicting, or human-blocked children pause the epic instead of being skipped.
- After operator-approved merge, the host refreshes the target branch and recomputes the graph before advancing.

## Non-goals

- Parallel child containers in the MVP.
- Automatic merge or bypass of branch protection and operator approval.
- Replacing existing per-plan launchers, receipts, or package-rebundle behavior.

## Definition of done

- `/ci <epic-id>` can durably execute and hand off each eligible child in order, then finish only after merged-state rollup and epic-intent coherency pass.
