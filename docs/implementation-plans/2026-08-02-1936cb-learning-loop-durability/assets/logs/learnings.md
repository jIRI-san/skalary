## Learnings Capture
Phase: 1
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 2
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 3

- [3.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:8bf61c3b3c6111065e7ac79fb6de718dd4f99e88e9f2d69974cd9986bfc9665b] A phase receipt is durable only when complete or empty gates completion and its receipt plus ledger delta are committed before runtime teardown.
- [3.3] [trigger:rework>1] [concern:testing-evidence] [req:REQ-4,REQ-7] [review:cr] [source-record:4ce53563bb1e59b45dc2f53b1133a770e48b866aace9bf88b1967333f787f56f] Concurrency evidence must contend on the same store and exact capacity boundary; distinct categories or sequential prechecks prove weaker invariants.
- [3.1] [trigger:rework>1] [concern:performance] [req:REQ-4] [review:cr] [source-record:4556b5bb16e5bb63fb0564029056edccb32fa501a6fc47ea717cc06af6c5a5e0] Batch writers must index idempotence and recurrence keys once; per-candidate scans become quadratic at the legal final-sweep boundary.
- [3.3] [trigger:rework>1] [concern:testing-evidence] [req:REQ-7] [review:cr] [source-record:5a9538cc4bd4865bce799ecec59f4009e9f83c89f4eb02c4d1ad6d937d4ddc67] Concurrency regressions need an observable synchronization point or a deterministic state path; fixed sleeps cannot prove which side of a precheck ran.

## Learnings Capture
Phase: 4
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

- [4.1] [trigger:rework>1] [concern:performance] [req:REQ-6] [review:cr] [source-record:22b6d59cfa3ab3cb7c20186510b6eea50b6698df9214931655d2ecf938eb7f1a] Bounded pagers must persist and fully validate the selected window; continuation cannot rescan maximum-size sources, and object sizes must be preflighted from tree metadata before blob allocation.

## Learnings Capture
Phase: 5

- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-3,REQ-8] [review:none] [source-record:fd463b4883053cb24a5bb30d63036f8e52e8b380ffb996485cff886cd6ebb715] Headless SI tests must distinguish running a proposal from enqueueing a durable due; the old 'queues nothing' invariant blocked the planned handoff.
- [5.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-2,REQ-3,REQ-8] [review:none] [source-record:2a69326264281c5fbb4c2f8634e7c439bbb0a0607a8bbcac2ec676bfc7fec78e] Installed lifecycle tests must build the full CI dependency closure and encode omitted nullable JSON fields explicitly; direct SI fixtures can miss both integration and schema-coercion defects.

## Learnings Capture
Phase: 6
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 7

- [7.1] [trigger:rework>1] [concern:security] [req:REQ-7] [review:cr] [source-record:ce492a8bb93a32cbb7c32967b14a9e417a199fd9ac537efab4019d2a5b54efa3] Content-addressed repair artifacts are not authority; merge gates must replay the transition from pinned authoritative state and compare the complete result.

## Learnings Capture
Phase: 8

- [8.1] [trigger:reusable-pattern] [concern:testing-evidence] [req:REQ-8] [review:cr] [source-record:cb80a59e2dda1be2b1ce61566d76996a8d9ca91192b8f5b5931d5fb5dae4c114] Cross-surface drift proofs must bind complete install metadata and canonical source bytes, not only destination names and hashes.
- [8.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-8] [review:cr] [source-record:6c18b57ce1f34a8ac1d3d3069dbd853223e36bd8298b73ab4b8b0cc4cbbab3b6] A freshness protocol must support absent-row bootstrap, consume authorization at an existing process boundary, and preserve path bytes exactly.
