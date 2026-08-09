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

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:a6d4bda57c80d9edc44ff1abb58c9f7f265f785000dc6e3487924caa7a0016c6] Receipt capacity checking was outside the receipt publication lock, allowing concurrent phase harvests to exceed the active ceiling after ledger mutation.
- [3.1] [src:code-review] [sev:High] [concern:correctness-reliability] [req:REQ-7] [review:cr] [source-record:21095dba517e5979d9b41491686502eafd7fbb0b1f548731a54393a6cf5c43d9] Ledger lock scopes did not normalize Windows root casing and CAS conflicts thrown during replace bypassed the bounded retry loop.
- [3.1] [src:code-review] [sev:Med] [concern:maintainability-consistency] [req:REQ-4] [review:cr] [source-record:0ba4204c14742d7a685a0792be6d0792ca9cb2e9966dbaa10a6744dee9bc3916] The harvester rejected writer-valid CrLog sources and the writer accepted hidden kind fields that could not be reconstructed for digest validation.
- [3.1] [src:code-review] [sev:High] [concern:security] [req:REQ-7] [review:cr] [source-record:49227a16e0abcc9173d08da1a4c44fe60337b9083d026ad19d959661a62c6d0f] Ledger path confinement was lexical only, so a symlinked review-ledger directory could redirect writes outside the repository.
- [3.1] [src:code-review] [sev:High] [concern:security] [req:REQ-7] [review:cr] [source-record:616fa18e5f2fabffc7fa958960a6e121590d02ec99a097773e0f4ae313d611e9] Physical ledger confinement compared paths case-insensitively on every platform, permitting case-distinct outside targets on case-sensitive filesystems.
- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:4c67c1437ab6f58b781765d53ab239bf1c6aabbadc5881bbbdc579edaea8d9e5] Overflow kind inference used ambiguous visible tokens; validate each compatible grammar against its domain-separated source digest instead.
- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:93c7782cb74aaa93fa05a0d6ff1d2b8aeb2e2ed31f17f09e4110f5c4d3bffbbe] Workflow-note writing accepted a step whose leading phase disagreed with the target section, guaranteeing harvest degradation.
- [3.1] [src:code-review] [sev:High] [concern:correctness-reliability] [req:REQ-7] [review:cr] [source-record:54a5a95dcd368f9fea1c2ea71654171244cdbe5853a8da59b78ba63c06bf9d07] Ledger mutex identity used the lexical repository path, so symlink aliases could acquire different locks for the same physical store.
- [3.1] [src:code-review] [sev:Med] [concern:security] [req:REQ-7] [review:cr] [source-record:1e3d88df7dd83d1d5fed0692be1db0828b4d034f566d65cbc32197180fc0afa4] Enumerated overflow and receipt child files were read without rechecking physical descent from their confined roots.
- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:755b480fd1bba55777bdd3364fe196894b36822850b660f501f4b2ed1d83406a] Existing-receipt replay occurred before rejecting an already over-cap active receipt set.
- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:a604c17183666a0d525054fb7ff8223c310009eb2921215d7a8b79918ce54de9] A step-less learning could overflow without phase provenance and make every later phase harvest degrade.
- [3.1] [src:code-review] [sev:High] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:49411d375debca313c0ce42a56ebdbe3872bd0140cc0db453a134b08667d0572] Phase harvest could publish a receipt from logs changed after collection because source writers and publication used different locks without a generation recheck.
- [3.1] [src:code-review] [sev:High] [concern:security] [req:REQ-7] [review:cr] [source-record:26f1436feaad6204c824a3262db3b57c34147f16263fee24f665bd12367506b6] Repository identity serialized the raw origin URL, which could persist embedded HTTPS credentials in a receipt.
- [3.1] [src:code-review] [sev:Med] [concern:correctness-reliability] [req:REQ-7] [review:cr] [source-record:677a5457f86194997a0ded4d34fa6da7c1348a02053eb9c6d8b7188dfeb3b46b] Receipt publication used a lexical plan lock identity, so physical aliases could bypass the active-receipt ceiling serialization.
- [3.1] [src:code-review] [sev:Med] [concern:security] [req:REQ-7] [review:cr] [source-record:c0d967235d246422351b394a88c87461aafc452da15e494d9b8216491e107acf] PlanState physical confinement used case-insensitive prefix comparison on Unix and could accept case-distinct escape targets.
