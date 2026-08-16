## Learnings Capture
Phase: 1
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
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
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 3
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 4
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 5

- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-3,REQ-8] [review:none] [source-record:fd463b4883053cb24a5bb30d63036f8e52e8b380ffb996485cff886cd6ebb715] Headless SI tests must distinguish running a proposal from enqueueing a durable due; the old 'queues nothing' invariant blocked the planned handoff.
- [5.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-2,REQ-3,REQ-8] [review:none] [source-record:2a69326264281c5fbb4c2f8634e7c439bbb0a0607a8bbcac2ec676bfc7fec78e] Installed lifecycle tests must build the full CI dependency closure and encode omitted nullable JSON fields explicitly; direct SI fixtures can miss both integration and schema-coercion defects.
- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-3,REQ-8] [review:none] [source-record:c8bd18cdce9c8271bc209b7bf358116985e54af5885f97297bdaeb5fa7e1a22e] Failure-path integration tests need a deterministic storage fault because SI repo identity intentionally falls back when origin is absent.
- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-8] [review:none] [source-record:1f01744ed0c7ce6ca108c9a3a1546fd7ba7407a99d5c3bb5308c7d2dfeb731e6] Suite measurement must run after every new file is tracked because the fingerprint intentionally ignores untracked paths outside git ls-files.
- [5.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-3] [review:cr] [source-record:e0554a17da63627724fad7d4ba7c7acf3ef942fd196318b0476af5f4d467daec] Non-blocking workflow evidence must execute the failing installed dependency and a durable continuation operation on the same path; separate failure and success fixtures do not prove continuation.

## Learnings Capture
Phase: 6
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 7

- [7.1] [trigger:rework>1] [concern:security] [req:REQ-7] [review:cr] [source-record:ce492a8bb93a32cbb7c32967b14a9e417a199fd9ac537efab4019d2a5b54efa3] Content-addressed repair artifacts are not authority; merge gates must replay the transition from pinned authoritative state and compare the complete result.
- [7.1] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-2] [review:cr] [source-record:5e6c7b966cde2ab06ff46d12c4989f35b8e9091e6859fda4f3a42782d54347f7] Provider metadata semantics must be checked against a live authoritative response before redesigning merge reconciliation around third-party summaries.

## Learnings Capture
Phase: 8

- [8.1] [trigger:reusable-pattern] [concern:testing-evidence] [req:REQ-8] [review:cr] [source-record:cb80a59e2dda1be2b1ce61566d76996a8d9ca91192b8f5b5931d5fb5dae4c114] Cross-surface drift proofs must bind complete install metadata and canonical source bytes, not only destination names and hashes.
- [8.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-8] [review:cr] [source-record:6c18b57ce1f34a8ac1d3d3069dbd853223e36bd8298b73ab4b8b0cc4cbbab3b6] A freshness protocol must support absent-row bootstrap, consume authorization at an existing process boundary, and preserve path bytes exactly.
- [8.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-8] [review:cr] [source-record:9142873c894ca15f824971b797f61f507cd9ad616530e197576090d24787b399] Process-scoped measurement authorization must be cleared before nested fixtures run against a different repository fingerprint.
