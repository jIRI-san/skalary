# Decisions

<!-- Key decisions made during planning — one bullet per decision. Historical detailed decision files are retained as review history; this file records the executable direction. -->

- **Simplicity decision: extend the files and writers already in use.** Phase learning continues through layout-resolved workflow notes and `Add-LedgerEntry.ps1`. SI durability adds one append-only activity file with typed `due` and `result` rows, not a general state platform.
- **Reuse the narrow atomic-write pattern locally.** The SI activity writer may reuse the lock, temporary-file, and replace approach already proven by the ledger and feedback queue. It does not migrate unrelated writers or introduce a shared atomic-store module.
- **Headless completion records intent, not authority.** It appends a deduplicated due and reports write failure as degraded, but never runs `/si`, opens a proposal, or changes completion authority. Interactive `/si` retains its current untrusted-input, scope, worktree, draft-PR, and never-auto-merge controls.
- **Record operator value, not a ranking protocol.** A result preserves the candidate choices presented by the normal `/si` flow and the operator's accepted, declined, or deferred outcome. It does not create ranked-set digests, resolver receipts, branch state machines, or merge-based consumption.
- **Finalization retries existing ledger writes.** Phase crosscheck performs the first durable promotion and finalization repeats it idempotently through the current ledger deduplication contract; no phase-harvest receipt hierarchy is added.
- **Rejected as overengineered and out of scope.** The sharded manifest/run topology, repair/quarantine receipts, cache or paging protocol, repo-wide writer migration, CAS/status family, trusted-base merge authority, PR reconciliation state machine, exact operational-limit platform, and suite fingerprint system are not part of this plan. Historical files under `assets/decisions/` describe superseded proposals and are not implementation instructions.
- **Cross-repo transport remains in `2366ad`.** This plan supplies durable local learning and SI activity only.
