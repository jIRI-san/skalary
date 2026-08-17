## Capture
Phase: 1

- [2.2] [src:note] [sev:Critical] dr: plan-folder mutation needs one lock, durable journal, under-lock revalidation, kill recovery, and a distinct no-retry recovery-required exit
- [4.1] [src:note] [sev:Critical] dr: every post-move lifecycle boundary must re-resolve canonical plan identity or it can recreate the old folder
- [3.2] [src:note] [sev:High] dr: dry-run and apply require persisted candidate fingerprints, set-digest equality, and candidate-to-record bijection

## Capture
Phase: 2

- [2.2] [src:note] [sev:Critical] dr: recovery authority for namespace mutation must live in a verified host-mounted session root and survive kill, teardown, and fresh-clone relaunch
- [4.3] [src:note] [sev:Critical] dr: self-migration requires a host relaunch boundary because the already-running entrypoint cannot consume newly installed exit handling
- [5.1] [src:note] [sev:Critical] dr: complete gates and platform tier receipts must run after corpus rename on the exact migrated commit

## Capture
Phase: 3

- [5.1] [src:note] [sev:Critical] dr: terminal apply must be invoked by the updated host through the cip-owned command and authorized by a single-use operation-bound capability
- [2.1] [src:note] [sev:Critical] dr: namespace lock order must include review and ledger-store locks and amend the existing review-run architecture boundary
- [5.2] [src:note] [sev:Critical] dr: post-migration authority requires exactly four same-commit platform-tier receipts and fix-forward-only handling after a completed rename
