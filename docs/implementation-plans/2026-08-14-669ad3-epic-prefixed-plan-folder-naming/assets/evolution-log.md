# Evolution Log

## Round 1

- **Issues found:** 29 findings: 13 Critical, 7 High, and 9 Medium across command ownership,
	distribution cadence, confinement, concurrency/recovery, grammar authority, lifecycle re-resolution,
	receipt truth, test coverage, suite budgets, live state, and terminal corpus migration.
- **Issues fixed:** Defined disjoint migration ownership; same-step distribution sync; shared grammar API;
	reparse-safe confinement; cross-process lock; versioned write-ahead journal; exit `44`; mandatory internal
	receipts with optional fixed-root export; multi-child epic transactions; real-migration lifecycle tests;
	Fast/Slow tiers; readiness/runbook behavior; and terminal self-migration.
- **Operator decisions:** Keep `Repair-Plans.ps1` and prefix migration separate; add lock/journal; persist
	internal receipts while keeping export optional; keep the naming contract in implementation design notes.
- **Deferred/rejected:** No architecture-tier contract will be added. The operator explicitly retained
	design-note ownership; `plan-workflow.design.md` remains the authority.

## Round 2

- **Issues found:** 19 findings: 5 Critical, 11 High, and 3 Medium across disposable recovery authority,
	self-migration bootstrap, exit propagation, live-state ownership, namespace locking, journal transitions,
	dry-run selection, launcher identity, historical/evidence paths, test discovery, and post-migration gates.
- **Issues fixed:** Moved recovery authority to a host-mounted session root; expanded the lock to all namespace
	writers; defined journal transitions and tamper checks; required `-ApprovedDryRunId`; confined migration
	invocation to cip; added canonical launcher/run handles; propagated exits `44`/`45`; split phase-local and
	terminal evidence; added exact-commit Fast/Slow CI receipts; and made the full gate post-migration.
- **Operator decisions:** Use automatic exit `45` planned relaunch and an owner-bound terminal self-migration
	exception. Bootstrap the first rollout with one explicit exit-42 host-update handoff.
- **Deferred/rejected:** None beyond the retained round-1 decision against an architecture-tier contract.

## Round 3

- **Issues found:** 36 findings: 7 Critical, 19 High, 9 Medium, and 1 Low across apply authority,
	platform receipt aggregation, relaunch bounds, complete lock order, capability provenance, authority roots,
	Git recovery, protocol skew, evidence mapping, post-rename failure policy, and terminal resume boundaries.
- **Issues fixed:** Authorized host invocation of the cip command; required exactly four same-identity CI tuples;
	bounded exit `45` to one progress-bearing relaunch; completed lock order and amended `ARCH-Review-Run-V1`;
	added a single-use host nonce capability; unified the physical authority root; classified fresh-clone Git
	states; reused `EpicId`; added protocol-generation readiness, scenario/tier maps, numeric bounds, Windows
	probes, durable in-repo mapping, split apply/verification, and explicit fix-forward behavior.
- **Operator decisions:** Host invokes apply; one relaunch per operation; host-issued capability; fix forward
	after completed migration; reuse transaction schemas/verification without a generic engine; record Slow
	runtime without a ceiling; retain permanent read-only unprefixed-hash compatibility.
- **Deferred/rejected:** No new naming architecture contract and no inverse corpus migration. The existing
	provisional review-run contract is amended only for its outer lock boundary.