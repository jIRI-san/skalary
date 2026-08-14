# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Make `/ci` implement plans as demonstrable vertical increments and repeatedly prove that confirmed intent and requirements still hold as the code evolves.

## Desired outcome

Execution follows the MVP-first vertical phase shape produced by `57cc2c`. Each phase leaves working end-to-end behavior, runs requirement and intent crosschecks, records agent decisions and uncertainty, and obtains operator input at meaningful checkpoints before later slices build on it.

## Success signals

- Every completed phase leaves an inspectable usable increment rather than an isolated layer.
- Applicable requirements and confirmed intent are rechecked at slice, phase, and plan boundaries.
- Independent implementation decisions, rejected options, and uncertainty are preserved for review.
- High-impact uncertainty about contracts, user experience, security, or irreversible structure stops for operator approval.

## Non-goals

- Replacing deterministic validators with agent judgment.
- Converting a complete implementation plan into an MVP-only execution.
- Concurrent writers sharing one implementation scope.

## Definition of done

- `/ci` can carry a complete plan from MVP through successive vertical increments to the full desired outcome, with evidence and decision history at every checkpoint.
