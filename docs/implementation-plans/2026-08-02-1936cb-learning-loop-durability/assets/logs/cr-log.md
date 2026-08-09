## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] Repair observation schema made observationId part of the exact bytes used to derive itself; move hash input into a separate payload.
- [1.1] [src:code-review] [sev:High] Run schema accepted completed records without complete ranked-set, choice, timestamp, or resolver-receipt invariants.
- [1.1] [src:code-review] [sev:Med] Manifest pending and in-flight arrays did not constrain entry status and runId to the containing state.
- [1.1] [src:code-review] [sev:Med] Run schema stored proposal PR only at run level, so candidate choices could not retain their proposal association; add candidate-level proposalPr.
- [1.1] [src:code-review] [sev:Med] Completed accepted choices still allowed proposalPr null; require a non-null candidate proposal association after completion while retaining null during proposal-pending.
- [1.2] [src:code-review] [sev:Critical] Repair lock guard was initialized inside the state-contract literal; moved it to module scope.
- [1.2] [src:code-review] [sev:High] Repair receipt rollback lacked content-address verification; rollback now validates schema and exact payload digest.
- [1.2] [src:code-review] [sev:High] Archive moved runs outside the shared lock and left stale manifest references; archive now locks, updates manifest, and rolls back failed moves.
- [1.2] [src:code-review] [sev:High] Lifecycle accepted run-id reuse and invalid predecessor states; updates now bind run to due and enforce a closed transition matrix.
- [1.2] [src:code-review] [sev:High] Active run ceilings were inspection-only; run writes now reject completed or in-flight plus-one before mutation.
- [1.2] [src:code-review] [sev:High] Rollback could delete state without an exact backup; repair now journals an explicit absent-manifest marker and otherwise refuses rollback.
- [1.3] [src:code-review] [sev:High] Repair checked total active files but applied separate completed and in-flight ceilings after quarantine mutation; inspection and pre-mutation repair checks now use the exact limits.
- [1.3] [src:code-review] [sev:Med] Receipt rollback verification depended on a coincidental backup-directory miss; every receipt path now verifies the receipt and after-digest unconditionally.
- [1.3] [src:code-review] [sev:High] Repair backup paths relied on observation text; Apply now rejects rooted or state-root-escaping observed paths before file access.
- [1.3] [src:code-review] [sev:High] Incomplete-apply rollback retained its journal and authorization; successful rollback now removes the journal and matching quarantine index entries.
- [1.3] [src:code-review] [sev:Med] Metadata paging threw on corrupt, legacy, or forward manifests; Get-SiState now returns inspection status with empty metadata for non-readable states.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:Med] Legacy case-varied retries could duplicate preserved 8-hex records; use ordinal-insensitive content migration matching.
- [2.1] [src:code-review] [sev:Med] Crash coverage only seeded an unrelated stale temp; fault the atomic temp-before-replace boundary and prove recovery.
- [2.2] [src:code-review] [sev:High] [concern:correctness-reliability] [req:REQ-5] [review:cr] [source-record:5df5cb8d1f2cb4deef43a8522575191bc2e00fef5508f1cc3e5f322d334b2a4b] Uncertain-commit replay could append an already durable source-record ID; deduplicate active and overflow records under the plan lock.
- [2.2] [src:code-review] [sev:Med] [concern:security] [req:REQ-8] [review:cr] [source-record:56d369e13fecd98dd2f387a71d7488050718fd193b3db27308ed21977a732d19] Lexical plan confinement did not resolve symlink targets; physically confine existing ancestors before writes.
- [2.2] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-5] [review:cr] [source-record:3e0865428bd948fe62c9399fe245717bdf39d0909d4100e3031b6ace53a375b7] Repository-root discovery did not advance its ancestor cursor and could loop forever.
- [2.2] [src:code-review] [sev:Med] [concern:testing-evidence] [req:REQ-4] [review:cr] [source-record:ed85ce3a57d7251e2da4609c6487ba2f6cf0eecbdc622f50cd93f86a3c89a766] Typed provenance evidence proved only kind domain separation; vary each provenance field and canonical requirement order.
- [2.3] [src:code-review] [sev:High] [concern:security] [req:REQ-7] [review:cr] [source-record:552b97808d99eb1d91a83ac17aae39ffa405ced91af794fea324de86b0662181] Unvalidated overflow markers could delete active records; verify schema, plan, filename, digest, count, and records before repair.
- [2.3] [src:code-review] [sev:High] [concern:correctness-reliability] [req:REQ-5] [review:cr] [source-record:496395205fa314d0ff0a9566295e17c326b6bfcd6ea2244581b2b04a43a98ea1] Active-log capacity was checked after overflow mutation; precompute every resulting store before the first write.
- [2.3] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-5] [review:cr] [source-record:84ee2a018eaff21fc54b0250b714725814ee9ab461d0e3913ee6ec74f92da658] Migrated records bypassed the 16 KiB per-record limit; validate every overflow record before mutation.
- [2.3] [src:code-review] [sev:Med] [concern:architecture-patterns] [req:REQ-7] [review:cr] [source-record:7ea6e7e5da0cb4028960beb7039fba58cb81f7a120445e5b2430e1884f3d51c9] Public lock and CAS parameters allowed values beyond exact 30-second and three-attempt maxima.
- [2.3] [src:code-review] [sev:Med] [concern:testing-evidence] [req:REQ-5] [review:cr] [source-record:06b32620aecea800a1c4d82bf9b91c5450bd5e7cd7d436451830dd5839365606] Boundary matrix used coarse values and lacked active-replace rollback evidence; cover exact maxima and plus-one.
