## Capture
Phase: 1

- [1.1] [src:note] interview: execution status is immutable and separate from gate disposition; only an exact policy may waive skipped or mixed pass-skip evidence
- [1.3] [src:note] interview: one focused Pester runner executes every exact test-id match from committed suite scope and preserves skipped, degraded, missing, and error outcomes
- [1.1] [src:note] [sev:Critical] dr: a digest allowlist can omit the dependency that invalidates evidence; hash all tracked inputs and use only a closed lifecycle-output exclusion list

## Capture
Phase: 3

- [3.1] [src:note] [sev:Critical] dr: freshness bound to current HEAD self-invalidates when the receipt or finalization is committed; bind evidence-relevant inputs and exclude lifecycle-only outputs
- [3.1] [src:note] [sev:High] dr: replace an old green receipt with blocked running state before execution so interruption cannot leave stale success authoritative
- [3.3] [src:note] [sev:High] dr: introduce a new artifact contract dormant, migrate every caller, then switch authority atomically; a compatibility window creates two truths
- [3.1] [src:note] [sev:High] dr: atomic replacement protects bytes but not lifecycle races; serialize transitions and compare UUID state and digest tuple under one stable lock

## Capture
Phase: 4

- [4.2] [src:note] [sev:High] dr: tracked CI rows cannot authenticate their own provenance; verify trusted workflow run job SHA conclusion and artifacts through the provider API
