## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] Repair observation schema made observationId part of the exact bytes used to derive itself; move hash input into a separate payload.
- [1.1] [src:code-review] [sev:High] Run schema accepted completed records without complete ranked-set, choice, timestamp, or resolver-receipt invariants.
- [1.1] [src:code-review] [sev:Med] Manifest pending and in-flight arrays did not constrain entry status and runId to the containing state.
- [1.1] [src:code-review] [sev:Med] Run schema stored proposal PR only at run level, so candidate choices could not retain their proposal association; add candidate-level proposalPr.
- [1.1] [src:code-review] [sev:Med] Completed accepted choices still allowed proposalPr null; require a non-null candidate proposal association after completion while retaining null during proposal-pending.
