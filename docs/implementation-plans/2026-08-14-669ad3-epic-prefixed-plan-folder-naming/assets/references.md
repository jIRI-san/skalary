# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

Group plan folders by epic identity at the start of the folder name. Standalone plans use the literal
`standalone` in the same position. Migrate existing plans only when they already use the current hash-name
schema; legacy numbered plans stay untouched.

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turn 8: the operator requested the epic hash at the start of plan-folder names, `standalone` in the same position, and migration only for the new hash-name schema.
- Epic `bcece1` Plan-folder grouping section records the accepted creation, attachment, re-parenting, migration, and mixed-grammar behavior.

## Target grammar

- Epic child: `<epic-id>-<yyyy-mm-dd>-<plan-id>-<slug>`.
- Standalone: `standalone-<yyyy-mm-dd>-<plan-id>-<slug>`.
- `epic-id` and `plan-id` are canonical six-hex anchors; the prefix is navigation metadata, not identity.
- Epic folders remain under `epics/` with their existing grammar unless this child's `/cip` interview
  explicitly expands scope; this request concerns plan folders.

## Prior art relationship

- **Supersedes:** `7645b1` REQ-2 and its `<date>-<hash>-<slug>` decision with the grouped
	`<epic-id>-<date>-<plan-id>-<slug>` and `standalone-<date>-<plan-id>-<slug>` grammars.
- **Narrowly supersedes:** `7645b1`'s "dual-format, no renames" decision for folders matching the current
  hash schema. The no-rename rule remains for legacy `NNN-<slug>` plans.
- **Reuses:** `7645b1` REQ-1/REQ-3/REQ-12 and its stable canonical-ID decisions. Migration never changes a
  `plan-id`, ledger plan key, `depends-on` token, or evidence identity.
- **Reuses:** `b0c0d3` REQ-15 and its epic-layer decision. Epics remain indexes over independently
	resolvable sibling child-plan folders; membership remains marker-based.
- **Index limitation:** `Get-PlanIndex.ps1` could not index active folder
	`docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement` because it has no `plan.md`.
	No relationship is inferred from that unreadable record; `RISK-1` tracks the incomplete corpus view.

## Required lifecycle behavior

1. `New-Plan.ps1` accepts an epic/group context and writes the target grammar immediately. A direct `/cip`
	plan defaults to `standalone`; `/cep` supplies the epic ID while scaffolding children.
2. `New-Epic.ps1` attachment and `-Force` re-parenting rename an eligible hash-schema plan folder together
	with the membership-marker update. Both affected epic mirrors are refreshed after the move.
3. Resolution remains anchor-based. Hash prefix, plan slug, date, and canonical ID continue to work across
	old hash, target hash, and legacy numbered grammars during migration.
4. Archival preserves the group prefix while moving the folder under `archived/`.
5. A dedicated script-owned migration handles active and archived current-hash folders, supports `-WhatIf`,
	preflights collisions and ambiguous membership, is idempotent, and emits an old-to-new manifest.
6. Current-hash folders with one valid `<!-- epic: ... -->` marker receive that epic ID; those without one
	receive `standalone`. Missing or unresolvable epic IDs fail loud rather than guessing.
7. Legacy `NNN-<slug>` folders and loose-file migration behavior remain unchanged.

## Surfaces to reconcile

- `PlanState.psm1`: inventory grammar, date/slug parsing, resolution, epic rollup, archive detection.
- `New-Plan.ps1`, `New-Epic.ps1`, and a dedicated folder migration command.
- `/cip`, `/cep`, `/ci`, autopilot archival, plan-index output, evidence/ledger references, and tests.
- Plan templates, design notes, bundled scripts, dogfood copies, plugin manifests, registry, and marketplace.

## Review-ledger guidance

- **Security:** a declared confinement control must be shipped and invoked by the owning command; tests bind
	canonicalization and reparse rejection to the migration and membership paths.
- **Consistency:** payload edits regenerate `registry.json` and marketplace metadata in the same phase.
- **Testing:** fixtures assert the arranged pre-migration state is the state actually exercised and bind
	helper existence checks to real call sites.
- **Performance:** use minimal synthetic fixture trees rather than cloning the full repository per case.

## Safety and evidence direction

Use canonicalize-then-confine checks for every source and destination. Compute the complete rename set and
reject any collision before moving the first folder. Tests cover mixed legacy/old-hash/target-hash inventories,
active and archived plans, standalone attachment, cross-epic re-parenting, rollback after a failed preflight,
idempotent replay, and stable plan resolution before and after migration.

## Operation and recovery contract

- Physical host authority root: `%LOCALAPPDATA%/skalary/autopilot-state/<repo-key>` on Windows and
	`${XDG_STATE_HOME:-$HOME/.local/state}/skalary/autopilot-state/<repo-key>` on POSIX. It is the only
	authoritative root for this protocol; clone-local `.github/.skalary/` remains unrelated plugin state.
- Mount map: `<root>/namespace/` to `/run/skalary/namespace/` read-write;
	`<root>/sessions/<session-uuid>/recovery/` to `/run/skalary/recovery/` read-write; and the single-use
	capability file to `/run/skalary/capability.json` read-only. No repo, Git metadata, home, or parent root is
	exposed, and a missing/invalid mount never falls back to local storage.
- Lock order: namespace lock, review-run lock, then ledger/store lock. Never acquire an outer lock while
	holding an inner lock. Authoritative discovery occurs under the namespace lock; acquisition is capped at
	30 seconds and hold time at 120 seconds. `ARCH-Review-Run-V1` records the namespace outer boundary.
- Journal transitions: `Prepared -> ActionPending -> ActionApplied -> Compensating -> ReceiptCommitted ->
	Completed|RecoveryRequired`. Operation ID, declared actions, bounded fingerprints, snapshots, and derived
	paths are schema-validated before any recovery mutation; an undeclared transition or tamper fails closed.
- Operation IDs and `-ApprovedDryRunId` are lowercase UUIDs validated before path composition. Apply validates
	that exact `Ready` dry-run receipt. Every derived path is canonicalized, confined, and reparse-rejected. Optional
	export is fixed to `exports/<operation-id>.json`; existing non-identical output is never overwritten.
- Recovery: startup under the same lock completes reverse same-volume directory renames and restores only
	bounded marker/mirror snapshots. It never recursively copies a plan folder. Failed recovery returns typed
	`RecoveryRequired`, exits `44`, lists affected paths, and forbids launcher retry.
- Git reconciliation binds repository fingerprint, branch, base commit, progress commit, and apply commit.
	A branch still at the progress commit classifies destroyed-clone mutations as discarded and re-preflights;
	the exact pushed apply commit resumes verification; any divergent, partial, or conflicting head is
	`RecoveryRequired` and performs no compensation until operator repair.
- Limits: 512 candidates, one 1 MiB active journal, 2 MiB per receipt, 20 retained terminal receipts, 64 KiB
	diagnostics, one active operation, eight child processes, 30 seconds per fault case, and ten minutes per
	process-heavy test file. Fingerprints cover namespace identity and edited metadata, not recursive payloads.
- Readiness: malformed/untracked plan-shaped residue, reparse ancestors, live review/workflow locks, or a
	changed dry-run candidate digest block apply. Read-only inventory reports typed diagnostics; mutators fail.
	Before terminal self-migration, the host checks the initiating workspace, completed review authority is
	finalized, and only state owned by the current `669ad3` operation is exempt under the namespace lock.

## Runtime relaunch contract

- Canonical plan ID is the launcher input. Mutable folder basename is resolved in each checkout and does not
	define branch, worktree, transcript, or session identity.
- Exit `44` means `RecoveryRequired`: preserve host state, stop all phases/finalization, and never retry.
- Exit `45` means planned relaunch: push committed progress, preserve host state, stop the old process, update
	the host checkout, resolve the plan by canonical ID, and launch the next phase in a fresh runtime. One
	progress-bearing relaunch is allowed per operation under the original cumulative deadline.
- Initial rollout uses one `@human` exit-42 boundary after Phase 4 because today's running entrypoint cannot
	consume code `45` installed during that process. Once the host is updated, Phase 5 and future planned
	relaunches use `45` automatically.

## Grammar authority and compatibility

- Header-scoped `plan-id` and `epic` markers remain authoritative. An epic prefix must equal the resolved
	marker ID; no marker requires `standalone`; mismatch is malformed, not a fuzzy-match fallback.
- Group tokens are removed before slug matching. Epic IDs and prefixes are canonical lowercase six-hex.
- Old unprefixed hash folders are accepted only for rollout and migration input. Target creation never emits
	them; permanent read-only compatibility remains after the terminal corpus gate rejects repository instances.
- Active instructions, templates, launchers, and links use the shared parser/resolver. Historical archived
	prose and finalized review artifacts may retain old paths as non-authoritative provenance.
- `Test-HistoricalManifest.ps1` keeps pinned-commit lookup on historical paths but resolves current-tree plans
	by canonical ID. Active and archived `file:` markers are inventoried; authoritative current targets are
	rewritten or resolver-backed before the corpus move.

## Test and verification map

- A committed map records marker ID, stable scenario ID, Pester file/test identity, and Fast/Slow tier.
- Parser/formatter tests are Fast. Lock, process, kill, migration, Windows handle, and fresh-clone tests are Slow.
- Discovery rejects absent, skipped, unloaded, duplicate, undeclared, and scenario-missing cases.
- Post-apply aggregation accepts exactly one passing receipt for each of Windows Fast, Windows Slow, Linux
	Fast, and Linux Slow, all bound to the same commit SHA, operation UUID, and candidate digest.
