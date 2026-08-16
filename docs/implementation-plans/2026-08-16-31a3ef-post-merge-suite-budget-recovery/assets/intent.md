# Intent

## Goal

Restore a trustworthy, affordable deterministic gate after merged review-run and retirement work expanded the Windows suite from 223 seconds to 1287 seconds and exposed four semantic merge defects.

## Desired outcome

Every deterministic test remains mandatory, but process-heavy integration suites run in an explicit slow tier while `npm test` remains the fast feedback and evidence gate governed by the existing per-platform ceiling.

## Success signals

- Every discoverable test belongs to exactly one of Fast or Slow, except the separately owned review-consumer install matrix.
- `npm test` passes below the Windows 600-second hard ceiling without changing the budget.
- The slow tier passes on both Linux and Windows CI and publishes attributable NUnit evidence.
- The four post-merge consistency failures remain fixed.

## Non-goals

- Deleting tests, weakening cannot-test semantics, or raising the runtime ceiling.
- Changing review-run behavior, container behavior, or plan `583308` implementation.
- Implementing the unrelated `1936cb` learning-loop plan.

## Definition of done

- The merge repairs are retained, the manifest-owned partition is structurally complete and disjoint, both required tiers are green through the canonical runner, CI and design-note inventories agree, and the fast tier satisfies the existing Windows budget.
