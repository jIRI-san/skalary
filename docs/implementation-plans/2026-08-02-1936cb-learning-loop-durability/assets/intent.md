# Intent

## Goal

Make the learning loop retain and expose what each phase learned, whether `/si` is owed, and what the operator decided when `/si` ran.

## Desired outcome

Each phase can retain selected learnings through the existing capture and ledger path. Headless completion leaves one deduplicated self-improvement reminder without running `/si`; the next interactive completion surfaces it, and a normal `/si` run records the operator's choices and outcome.

## Success signals

- A two-phase fixture persists selected phase learnings through the existing layout-resolved capture and ledger writers without duplicates on finalization retry.
- Repeated headless completion for the same plan commit creates one unresolved due record, and its write failure is visible but non-blocking.
- The next interactive completion surfaces the unresolved reminder; `/si` records accepted, declined, or deferred choices and the run outcome in the same append-only activity file.
- Installed plugin fixtures exercise the flow without skalary source-tree paths, while existing `/si` untrusted-input, scope, draft-PR, and never-auto-merge safeguards remain unchanged.

## Non-goals

- Automating forks or upstream PR transport from consumer repositories; plan `2366ad` owns that flow.
- Changing `/si`'s untrusted-input fence, write-scope allowlist, draft-PR-only rule, or never-auto-merge rule.
- Re-opening the seven-concern taxonomy or concern-to-ledger map settled by plan `b0c0d3`.
- Changing autopilot's exit codes, plan contract, or decision not to run `/si` headlessly.
- Solving evidence-receipt or review-report truth; sibling plans `863d97` and `c21cdc` own those artifacts.
- Migrating unrelated writers, replacing the existing ledger/capture formats, or introducing a general state store, repair protocol, ranked-set protocol, PR merge authority, or suite fingerprint system.

## Definition of done

- Focused tests prove phase capture and finalization replay, due deduplication, interactive surfacing, durable operator choices/outcome, installed execution, and synchronized generated plugin artifacts. Existing `/si` safety checks and the normal deterministic gate pass.
