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
