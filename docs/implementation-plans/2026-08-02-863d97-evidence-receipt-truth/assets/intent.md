# Intent

> Preliminary context captured from epic `33b1f9` and the `b0c0d3` enforcement-gap review. `/cip` must confirm and refine it.

## Goal

Make evidence receipts state what actually ran and distinguish clean proof from skipped, unrun, failed, stale, or degraded verification.

## Desired outcome

The evidence pipeline carries explicit execution outcomes into one deterministic receipt grammar. A requirement can pass only when every required marker either genuinely passed or carries a visible, exact policy waiver for skipped or mixed pass/skip execution; platform skips and interrupted or partial runs are never counted as passed.

## Success signals

- A skipped test is never rendered as a passed test.
- Missing, stale, malformed, failed, and unrun evidence remain distinguishable in the receipt.
- Partial execution and degraded verification cannot satisfy the archival gate silently; an allowed waiver remains visibly waived.
- The shared formatter remains format-only and does not rerun evidence.

## Non-goals

- Replacing deterministic evidence with reviewer judgment.
- Folding review-report attendance and collation into the evidence-receipt contract.
- Treating platform-specific unavailability as failure when an explicit, policy-approved skip is intended.

## Definition of done

- Receipts produced by `/ci` and autopilot tell the same truthful story about every required marker, while `/cip` drafts and validates that same evidence contract. Completion blocks whenever required proof is absent and no exact plan-local waiver applies.
