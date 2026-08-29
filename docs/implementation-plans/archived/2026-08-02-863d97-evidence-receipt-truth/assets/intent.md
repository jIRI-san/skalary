# Intent

> Preliminary context captured from epic `33b1f9` and the `b0c0d3` enforcement-gap review. `/cip` must confirm and refine it.

## Goal

Make evidence receipts state what actually ran and distinguish clean proof from skipped, unrun, failed, stale, or degraded verification.

## Desired outcome

The current evidence pipeline carries explicit `passed`, `failed`, `skipped`, `unrun`, `stale`, `degraded`, and `waived` outcomes into its deterministic receipt grammar. A requirement can pass only when every required marker passed or carries a visible exact plan-local waiver; partial execution is never counted as passed.

## Success signals

- A skipped test is never rendered as a passed test.
- Missing, stale, malformed, failed, and unrun evidence remain distinguishable in the receipt.
- Partial execution and degraded verification cannot satisfy the archival gate silently; an allowed waiver remains visibly waived.
- The shared formatter remains format-only and does not rerun evidence.
- Focused Pester execution reports structured per-test outcomes through the existing test runner.

## Non-goals

- Replacing deterministic evidence with reviewer judgment.
- Folding review-report attendance and collation into the evidence-receipt contract.
- Treating platform-specific unavailability as failure when an explicit, policy-approved skip is intended.
- Replacing the current receipt lifecycle, hashing the whole tree, defining new exit-code families, or making GitHub API results an evidence authority.

## Definition of done

- Receipts produced by `/ci` and autopilot tell the same truthful story about every required marker, while `/cip` drafts and validates that same evidence contract. Completion blocks whenever required proof is absent and no exact plan-local waiver applies.
