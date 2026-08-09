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
