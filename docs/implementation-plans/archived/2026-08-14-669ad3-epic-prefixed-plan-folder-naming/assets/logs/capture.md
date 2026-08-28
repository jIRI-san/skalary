## Capture
Phase: 1

- [-] [src:note] [sev:Critical] [concern:correctness-reliability] [req:-] [review:dr] [source-record:063f2e203a7bcc348de8d49ed55598ee4dd6209489affd9a4f927c5c6eae1b6a] dr (legacy step 2.2): plan-folder mutation needs one lock, durable journal, under-lock revalidation, kill recovery, and a distinct no-retry recovery-required exit
- [-] [src:note] [sev:Critical] [concern:correctness-reliability] [req:-] [review:dr] [source-record:20c1c5f848bab2d37681cc270a584059f66b33ecbf25f73b25c666ec297c0b00] dr (legacy step 4.1): every post-move lifecycle boundary must re-resolve canonical plan identity or it can recreate the old folder
- [-] [src:note] [sev:High] [concern:security] [req:-] [review:dr] [source-record:d09d99fc68aadba8d66843ddaf32e6b26b16b85c501fcef0ccba14e89bc2da73] dr (legacy step 3.2): dry-run and apply require persisted candidate fingerprints, set-digest equality, and candidate-to-record bijection

## Capture
Phase: 2

- [-] [src:note] [sev:Critical] [concern:architecture-patterns] [req:-] [review:dr] [source-record:b595beb9ff7579376226f654d3195a84c8a4955f766f84afe0a895b2e48b65f1] dr (legacy step 2.2): recovery authority for namespace mutation must live in a verified host-mounted session root and survive kill, teardown, and fresh-clone relaunch
- [-] [src:note] [sev:Critical] [concern:architecture-patterns] [req:-] [review:dr] [source-record:6d60567f504afb672263a03223364066bb11f3e665b7b01e6c7e1a131713b87d] dr (legacy step 4.3): self-migration requires a host relaunch boundary because the already-running entrypoint cannot consume newly installed exit handling
- [-] [src:note] [sev:Critical] [concern:testing-evidence] [req:-] [review:dr] [source-record:6706e7e0e0a5c07a1165d53d5d7a0184c007d47ab3c8e1dc9e4b815663e67f56] dr (legacy step 5.1): complete gates and platform tier receipts must run after corpus rename on the exact migrated commit

## Capture
Phase: 3

- [-] [src:note] [sev:Critical] [concern:security] [req:-] [review:dr] [source-record:9bfe67b9ea94a639a592ab8f276367cbecacb19ef73dc4cf076032972052ac4e] dr (legacy step 5.1): terminal apply must be invoked by the updated host through the cip-owned command and authorized by a single-use operation-bound capability
- [-] [src:note] [sev:Critical] [concern:correctness-reliability] [req:-] [review:dr] [source-record:a61cc1ccb4b4b14fd07043f87ed999c004fdfbd252864d97b3e8386122bbc761] dr (legacy step 2.1): namespace lock order must include review and ledger-store locks and amend the existing review-run architecture boundary
- [-] [src:note] [sev:Critical] [concern:testing-evidence] [req:-] [review:dr] [source-record:299f76a95a2df55326e3a05e5ac7cf3f6d486b3c6461d84e83a0c056dbacc58d] dr (legacy step 5.2): post-migration authority requires exactly four same-commit platform-tier receipts and fix-forward-only handling after a completed rename
