# Intent

> Context captured from the `bcece1` epic discussion on 2026-08-14 and confirmed by the operator on 2026-08-21.

## Goal

Make `/cep` run an independent coherency review of an accepted epic decomposition before finalizing its children.

## Desired outcome

After the operator accepts a proposed cut, `/cep` uses the shared bounded fleet to verify goal coverage, verticality, independent executability, ownership, overlap, dependencies, prior-art reconciliation, and the path from MVP to complete delivery. Findings revise the cut or return decision-changing questions to the operator.

## Success signals

- Missing, redundant, overlapping, horizontal, or non-revertible children are surfaced before implementation plans are drafted.
- Shared contracts have one owning child and dependency edges are necessary, direct, and acyclic.
- Both an early usable path and the epic's complete outcome are covered.
- The review uses the shared four-in-flight scheduler; verified review-run v1 authority records
  durable attendance and degradation while Fleet attendance remains invocation-local.

## Non-goals

- Detailed child requirements, typed evidence, steps, or code-level design.
- Replacing operator confirmation with an agent verdict.
- A separate epic-only dispatch implementation.

## Definition of done

- `/cep` cannot finalize a decomposition without a recorded coherency verdict and resolution of decision-changing findings.
