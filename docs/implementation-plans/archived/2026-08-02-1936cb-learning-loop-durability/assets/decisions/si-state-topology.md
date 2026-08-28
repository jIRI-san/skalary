# SI State Topology

## Authority

Fetched `origin/main`, pinned by commit OID, is the authoritative committed SI state. A feature/worktree copy is a proposed transition, not proof that a due was consumed. Self-improvement owns canonical lifecycle sources outside its bundle-managed skill tree and maps them into the installed SI skill:

- `docs/self-improvement/state.json`: bounded pending/in-flight manifest plus recent run references.
- `docs/self-improvement/runs/<yyyy>/<mm>/<run-id>.json`: one schema-validated run; mutable while resumable, immutable after completion.
- `plugins/self-improvement/schemas/{manifest,run,resolver-receipt,repair-observation,repair-receipt}.schema.json`: plugin-canonical schemas mapped to `skills/si/schemas/`.
- `plugins/self-improvement/scripts/*.ps1` and `SiStateStore.psm1`: plugin-canonical lifecycle sources mapped to `skills/si/scripts/`; `Sync-PluginScripts` never owns or prunes the source directory.

## Local transaction order

Every mutation holds one repo-scoped lock and obeys [operational-limits.md](operational-limits.md). Completion writes and validates the run first, then atomically replaces the manifest. A crash before manifest replace leaves the due pending and an inspectable orphan/resumable run. Repair is inspect-only unless explicitly applied; Apply writes backup and journal under the observation ID before target mutation, then quarantine/index and final receipt. Rollback accepts observation ID before receipt creation and receipt ID afterward. Newer versions are read-only/refused, never downgraded.

## Git and PR order

Git state and an external PR cannot share a filesystem transaction. Use this recoverable order:

1. Fetch and pin `origin/main`; reject/reconcile local deltas.
2. Derive correlation from due ID and classify all remote PR/branch states.
3. Create/resume fixed `si/<due-id>` from the pinned base before mutation.
4. Persist complete ranked set and choices while the authoritative due remains pending.
5. Trusted-sync `proposal-pending`, merging current main and re-deriving the manifest before pushing the exact validated head.
6. Create/find the draft PR; trusted-sync its URL and completed run, then push the exact validated head.
7. Trusted-sync the run-first/manifest-second consumed transition and push the exact validated head.
8. Operator-only completion fetches the live head, reruns trusted enforcement, and merges with expected-head OID in the same process; merge makes consumption effective.

Before merge, the authoritative due remains pending; remote branch/PR classification marks it in-flight. Concurrent SI PRs fetch/merge/re-derive before each trusted push. Open PR resumes. Closed-unmerged PRs reuse the fixed branch; deleted branches recreate it. Merged without expected consumed state is integrity failure routed to a corruption-independent repair branch. If no candidate is accepted, the same fixed branch carries a state-only record PR; candidate `proposalPr` fields remain null.

## Inspection and bounds

`Get-SiState.ps1` provides metadata-only status/validation; candidate free text is available only through `Get-SiHarvest.ps1`. `Repair-SiState.ps1` implements versioned orphan/temp recovery and quarantine with receipts. Exact bounds and plus-one behavior live in `operational-limits.md`; exceeding any bound is explicit degradation, never truncation.