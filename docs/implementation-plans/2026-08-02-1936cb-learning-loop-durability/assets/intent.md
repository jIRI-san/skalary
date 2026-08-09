# Intent

## Goal

Make the learning loop retain and expose what each phase learned, whether `/si` is owed, and what the operator decided when `/si` ran.

## Desired outcome

Headless plans leave a durable self-improvement reminder without autonomously opening a proposal. The next interactive completion surfaces that reminder; a deterministic draft PR records the complete ranked set and outcome, and merge makes consumption authoritative. Every `/si` run leaves a structured, inspectable record of all ranked candidates and their rationale, sources, targets, and accepted, declined, or deferred outcomes. Capture limits never erase operator feedback or learning records without an explicit failure/degradation signal.

## Success signals

- A two-phase fixture batch-promotes durable ledger entries with source/phase/REQ provenance and finalization only replays receipts.
- A headless completion creates one deduplicated pending due; the next interactive completion surfaces it, and only merge of its deterministic SI/state PR consumes it on `origin/main`.
- An `/si` run records the original ranked-set digest and every candidate's rationale, cited sources, targets, disposition, and proposal PR when one exists; all-declined runs remain durable through a state-only record PR.
- Feedback up to the stated byte limit and overflow learnings round-trip sentinel text across concurrency/crash fixtures; oversize or incomplete input fails before mutation/ranking with explicit degradation.
- Installed SI and CI payloads execute state, phase-harvest, and fenced paged-harvest contracts in a consumer-like repo without skalary source-tree paths.
- A proposal that modifies its own guard and a denied workflow is rejected by the trusted-base guard.

## Non-goals

- Automating forks or upstream PR transport from consumer repositories; plan `2366ad` owns that protocol.
- Changing `/si`'s untrusted-input fence, write-scope allowlist, draft-PR-only rule, or never-auto-merge rule except where needed to persist state.
- Re-opening the seven-concern taxonomy or concern-to-ledger map settled by plan `b0c0d3`.
- Changing autopilot's exit codes, plan contract, or decision not to run `/si` headlessly.
- Solving evidence-receipt or review-report truth; sibling plans `863d97` and `c21cdc` own those artifacts.

## Definition of done

- Run the crash/concurrency multi-phase fixture, then an interactive `/si` flow through PR reconciliation and merge. Ledger receipts prove every eligible phase and provenance; authoritative state contains the complete ranked set and outcome with no pending duplicate; feedback/overflow sentinels remain recoverable; hostile content stays fenced; trusted-base scope validation, consumer-installed execution, suite budget, and the full deterministic gate pass.
