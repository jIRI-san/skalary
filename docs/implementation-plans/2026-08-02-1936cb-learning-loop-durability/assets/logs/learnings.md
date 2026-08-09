## Learnings Capture
Phase: 1

- [1.1] [trigger:plan-contradiction] Content-addressed observations require a separately hashed payload; placing the identifier inside its own exact hash input is impossible.
- [1.2] [trigger:rework>1] Multi-file state transitions must perform run-first writes inside the same repo-scoped lock as the manifest CAS.

## Learnings Capture
Phase: 2

No entries for this phase.

## Learnings Capture
Phase: 3

- [3.1] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-4,REQ-7] [review:cr] [source-record:402646ca907161c36a250d09b9b551735d2e3556aa01b779d8b7b1fd700f6cd7] A durable snapshot receipt must share the writers physically canonical lock and recheck every source generation before publication.
- [3.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:8bf61c3b3c6111065e7ac79fb6de718dd4f99e88e9f2d69974cd9986bfc9665b] A phase receipt is durable only when complete or empty gates completion and its receipt plus ledger delta are committed before runtime teardown.
- [3.3] [trigger:rework>1] [concern:testing-evidence] [req:REQ-4,REQ-7] [review:cr] [source-record:4ce53563bb1e59b45dc2f53b1133a770e48b866aace9bf88b1967333f787f56f] Concurrency evidence must contend on the same store and exact capacity boundary; distinct categories or sequential prechecks prove weaker invariants.

## Learnings Capture
Phase: 4

No entries for this phase.

## Learnings Capture
Phase: 5

- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-3,REQ-8] [review:none] [source-record:fd463b4883053cb24a5bb30d63036f8e52e8b380ffb996485cff886cd6ebb715] Headless SI tests must distinguish running a proposal from enqueueing a durable due; the old 'queues nothing' invariant blocked the planned handoff.
- [5.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-2,REQ-3,REQ-8] [review:none] [source-record:2a69326264281c5fbb4c2f8634e7c439bbb0a0607a8bbcac2ec676bfc7fec78e] Installed lifecycle tests must build the full CI dependency closure and encode omitted nullable JSON fields explicitly; direct SI fixtures can miss both integration and schema-coercion defects.
