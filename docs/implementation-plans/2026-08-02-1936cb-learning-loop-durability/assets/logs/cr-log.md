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
