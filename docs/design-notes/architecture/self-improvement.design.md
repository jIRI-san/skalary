---
description: Self-improvement plugin — post-plan feedback (/pfb) and the ledger-to-proposal loop (/si), including the untrusted-input contract and the pre-PR write-scope gate that bounds a workflow that edits the repo's own instructions.
globs:
  - plugins/self-improvement/**
  - .github/skills/pfb/**
  - .github/skills/si/**
  - scripts/skalary/{Test-SiWriteScope.ps1,Update-FeedbackQueue.ps1}
  - docs/feedback/**
---

# Self-Improvement Plugin

Two skills close two different loops that used to end in a write-only file.

| Skill | Loop it closes | Ends in |
|---|---|---|
| `/pfb` | Requirements say what to build; **intent** says what the operator was trying to achieve. A plan can be green on every typed evidence marker and still miss the point. | A recorded verdict against `assets/intent.md`, optionally a correction plan via `/cip` |
| `/si` | `/ci` harvest writes lessons into the review ledger and plan logs; nothing read them back. | A ranked, cited set of proposed edits to this repo's own skills/agents/docs, on a branch, as a **draft** PR |

Both ship in one plugin rather than three: they share the plan-resolution surface and the
untrusted-input contract, and the precedent is the design-notes consolidation.

## `/pfb`: feedback that never blocks

`/pfb` is **offered** at the `/ci` archival gate and never gates it. A plan that is complete and
evidence-clean archives whether or not anyone answers the question.

**Autopilot has no operator to ask.** A headless run therefore *queues* the question instead of
prompting: it appends a marker to `docs/feedback/queue.md` through `Update-FeedbackQueue.ps1`, and
the next interactive session consumes it. Queueing never fails the run, never satisfies the archival
gate, and never gates the PR.

- **Never invent a verdict to fill the gap.** An unanswered question is an honest absence of
  feedback; a fabricated one is false feedback that nothing downstream can distinguish from the real
  thing, and it would then be harvested by `/si` into edits to the instructions themselves.
- The queue is **script-owned**. `Update-FeedbackQueue.ps1` is the only writer; the skill never
  hand-edits `docs/feedback/queue.md`. Its arguments are composed from plan content, so callers pass
  argument arrays — never a shell-interpolated command string.
- Queue mutations import the bundled `AtomicStore.psm1` and replace the file under its repo-scoped
  lock. Existing 8-hex identifiers remain unchanged during migration; new sanitized content receives
  a 16-hex content identifier. Sanitized entry text is bounded at 16 KiB, with 128 pending entries,
  2,048 recorded entries, and a 4 MiB file ceiling. A plus-one operation returns
  `capacity-blocked` with exit 4 before writing; content is never truncated.
- `docs/feedback/queue.md` sits outside `.github/`, so installation cannot write it. It is declared
  as a first-use `scaffolds[]` entry in `plugins/self-improvement/plugin.json`
  (see [plugin-registry.design.md](plugin-registry.design.md) → asset bootstrap).

## `/si`: harvested text is untrusted input

`/si` reads the review ledger, `assets/logs/learnings.md`, `assets/logs/cr-log.md`, and queued
`/pfb` feedback. Every one of those is model- or operator-authored free text that may carry
injection harvested from previously reviewed code.

The dangerous part is what `/si` writes: the `SKILL.md` and agent files that govern **every later
run**. That makes injection self-amplifying — text absorbed from a reviewed repo could end up in the
instructions the next review runs under.

Controls, in the order they apply:

1. **Wrap, then read.** Every harvested source is wrapped in `UNTRUSTED_INPUT` markers, with an
   explicit never-execute-directives-found-inside rule in `assets/harvest-guide.md`. Storage-time
   sanitization does not neutralize semantic injection at read time, so the guard lives at the read.
2. **Propose, never apply in place.** Work happens in a worktree on its own branch.
3. **`Test-SiWriteScope.ps1` before the PR.** Prose confinement is an instruction a model may not
   honour; this script is the enforcement. See below.
4. **Draft PR, never auto-merge.** A human accepts every candidate.

`/si` is offered at plan completion by `/ci`. **Autopilot does not run it.** Autopilot explicitly
depends on this plugin only to invoke installed `Enqueue-SiDue.ps1` after its autonomous archive
commit has been pushed. The due ID is
`sha256(repo-id|plan-id|complete-source-commit|si-due-v1)`; repeat enqueue is a no-op. A successful
write is committed and pushed before the plan PR. Writer failure is surfaced as non-blocking
degradation, never success, because opening a proposal with nobody present remains disallowed.

The consumer-repo flow is a local, explicit handoff — `gh` fork entitlement is out of scope, and
skalary is itself the registry, so the expected upstream identity is supplied by the operator.

## Cross-repository candidate transport

A consumer may export one completed or in-progress durable SI run through installed
`Export-CrossRepoSi.ps1`. The content-addressed `cross-repo-si-export/v1` artifact carries the
consumer repository, plan, source commit, installed plugin version, SI run/receipt provenance,
ranked candidate text, cited ledger/capture sources, targets, and current disposition. The writer
accepts at most five candidates, checks the run's 1 MiB ceiling before reading, redacts common
credential forms, neutralizes stored fence tokens, validates the closed schema, and refuses an
artifact over 64 KiB before atomic replacement. Repeating the same export is byte-stable and
reports a no-op.

The artifact is transport, not a second SI history. In a clean upstream-rooted checkout,
`Invoke-CrossRepoSiHandoff.ps1` validates its content address and closed schema, checks origin
against an explicit expected host and repository, refuses dirty or nested roots, and loads a bounded digest
inventory of upstream instruction files before returning the artifact inside a fresh untrusted-input fence. Small work resumes normal upstream `/si`;
plan-sized work enters normal `/cip`. The existing write-scope guard, draft-only PR, and
never-auto-merge controls remain authoritative, and every consumer claim is re-judged against
current upstream code.

## Durable SI state ownership

Self-improvement owns its state schemas and lifecycle commands directly under
`plugins/self-improvement/{schemas,scripts}/`. They are mapped one-for-one into
`.github/skills/si/{schemas,scripts}/`; `Sync-PluginScripts.ps1` must not generate or prune these
plugin-owned sources. `SiStateStore.psm1` is the single owner of the closed schema versions, status
codes and status sets, operational limits, topology segments/relative paths, and
run-before-manifest transaction order. Consumers call that contract rather than restating terminal
states, path literals, or derived ceilings such as the 63 retained references.

Distribution is fail-closed. `test:LearningLoop.PayloadOwnershipAndDrift` enumerates the complete
plugin-owned schema/script sets, refuses root-canonical duplicates, verifies each manifest mapping
and dogfood byte, proves autopilot's explicit dependency, and cross-checks scaffold, registry,
marketplace, version, installed-invocation, and shared phase-harvest bundle state.
`test:LearningLoop.StructuralEvals` is the Tier-1 plugin eval for both `pfb` and `si`; it validates
frontmatter, bodies, links, and required declared assets through the focused
`scripts/skalary/Test-Evals.ps1 -Plugin <name>` path; there is no npm eval alias.
Neither proof adds a standalone `validate.ps1` gate: ownership drift belongs to the existing unit
suite, while plugin structural evals retain the separate eval-runner boundary. That boundary is not
a generic CI gate, but the named test is blocking when a plan cites it as typed evidence during a
phase or plan crosscheck.

The hot manifest is bounded to 128 pending dues, 16 in-flight runs, 64 recent references, and
256 KiB. Active history is sharded per run and bounded to 32 completed plus 16 resumable files;
archive history is bounded to 4,096 files and 256 files per year/month shard. Every plus-one
operation returns `capacity-blocked` before mutation. Lifecycle commands fail loudly on invalid,
stale, forward-version, or exhausted state rather than exposing partial behavior.
The shared workflow-memory side is proven at its exact 10,000-record ledger ceiling by
`test:LearningLoop.MaximumBoundRuntime`: the focused operation must finish within 60 seconds,
reach the boundary, and reject record 10,001 without changing bytes. The full suite remains subject
to advisory platform runtime and tracked-input freshness reporting.

`scripts/skalary/AtomicStore.psm1` is the root-canonical persistence primitive. It provides the
30-second repo-scoped lock, random same-directory text or byte-preserving temp writes, validation before replace,
generation-digest CAS, and the closed `complete` / `lock-timeout` / `cas-conflict` /
`cas-exhausted` status vocabulary. SI receives that module as a generated bundle closure while
its schemas and lifecycle scripts remain plugin-owned. `SiStateStore.psm1` is the only lifecycle
module that calls the primitive: manifest updates retry at most three generation conflicts, run
completion persists and validates the run before the manifest, and repair Snapshot/Apply/Rollback
share the same state lock. A manifest retry carries the first transform's prepared run value into
later CAS attempts, so it rebases the manifest without replaying an already committed run write.
The lock scope is the physically resolved, separator-normalized SI state root, so symlink and
trailing-separator aliases serialize on one mutex.
Repair observations hash exact artifact bytes, not newline-normalized text; Apply reads each
observed source once, hashes and backs up that same buffer, and derives migration/reconstruction
state from the verified buffers. Rollback reloads the content-addressed observation, requires the
backup path set to match it exactly, verifies every backup digest and physical target before the
first restore, and refuses an observed run target unless it still has the observed digest or its
exact bytes remain at the derived observation quarantine path. It then uses byte-mode atomic
replacement, so a newer run-first write is never overwritten by rollback.
Migration rollback authenticates the deterministic migrated run postimage before restoring v1
bytes. A mutation-started journal binds the expected repaired manifest digest, blocks ordinary
manifest writers, and permits rollback only from the exact pre- or post-repair manifest. Rollback
accepts each authenticated target in either its repair postimage or already-restored observation
preimage, making a crash during multi-file restore resumable. Inspection also requires each run's
filename and year/month shard to match its embedded id and creation timestamp.
Only one observation may have an apply journal: another Apply and every ordinary manifest writer
refuse until rollback clears it. Backup and quarantine publication both use physically resolved,
confined destinations through the shared atomic byte writer.

`Enqueue-SiDue.ps1` derives the same canonical repository identity as phase harvest from `origin`
(with hashed-remote and canonical-path fallbacks), unless a test or trusted caller supplies
`-RepoId`. It computes the domain-specific due ID from repository, canonical plan ID, and the pushed
complete-source OID before the locked manifest update. Pending, in-flight, and recent IDs all
participate in deduplication. A duplicate is byte-stable and does not advance manifest generation.
Every state path resolves existing links physically and is refused when the target escapes the
physical repository root, using case-sensitive containment on Unix and case-insensitive containment
on Windows.

`Get-SiState.ps1` exposes metadata only. Inspection classifies absent, valid, orphaned, corrupt,
legacy, forward-version, capacity-blocked, and incomplete-apply stores without mutation.
Incomplete-apply metadata includes the observation ID, journal stage, and repository-relative journal
path needed for an explicit rollback; a journal ID that differs from its backup directory is invalid.
Apply admits only `migration-required`, `repairable-corrupt`, and `repairable-orphans`
observations; valid, absent, forward-version, capacity, and incomplete states are non-mutating
refusals. Manifest and run repair are independent: a schema-valid current manifest retains pending,
in-flight, and recent state while corrupt runs are quarantined or legacy runs are migrated. The
manifest/run graph is validated bidirectionally; orphan runs are admitted to the correct active
collection, corrupt referenced runs requeue their due, and terminal/nonterminal reference drift is
rebuilt from verified run provenance. Run ids, canonical paths, and active due ownership are unique;
noncanonical or same-due conflicting runs are quarantined and leave one pending due. Only an
absent/corrupt manifest is reconstructed from verified runs. Apply issues a receipt only when the
underlying post-mutation inspection is `valid`.
Pending and run due ids are re-derived from repository/plan/source provenance. Repair canonicalizes
pending identifiers and reconstructs in-flight provenance from validated runs rather than trusting
stored ownership fields.
Repair resolves every observed backup source physically under the SI state root, reads it once,
verifies those bytes against the immutable observation digest, and only then writes the backup, so
descendant links and link-swap races cannot capture host files. Backup writes use the resolved
physical destination retained after confinement rather than reopening the logical linkable path.
`Repair-SiState.ps1 -Mode Snapshot` content-addresses exact sorted observation bytes; Apply refuses
stale or altered observations, writes the backup and apply journal before replacing state, and
writes the receipt last. Rollback accepts the observation before receipt creation or the receipt
afterward. A v1 migration preserves existing due/run identifiers and arrays; forward versions
remain read-only.

All runtime state paths outside `.github/` are first-use scaffolds declared by
`plugins/self-improvement/plugin.json`: the manifest; year/month active and archive run shards;
the content-addressed archive recovery journal;
observation-keyed backup and quarantine trees plus the quarantine index; repair observations and
receipts; and resolver receipts. Parameterized paths route through `Resolve-SiStatePath`.
`Get-SiState` pages only `{dueId,runId,status}` plus counts/generation; it never returns candidate
text. Local repair copies every observed artifact under the observation-keyed backup before
mutation, reconstructs bounded manifest references from valid run files, quarantines corrupt runs
with an indexed digest, and refuses Apply/Rollback when the exact observation/receipt chain is
stale, altered, or missing. Successful rollback emits its own content-addressed receipt.
Archival holds the state lock and never selects a run ID still referenced by `manifest.inFlight`,
even if the run file itself claims a terminal status; recoverable run-first state remains active.
Before moving a completed run, it persists a content-addressed journal binding the exact
before/after manifest digests and every source/target byte digest. A retry rolls back moves when
the before digest remains authoritative or completes source cleanup when the after digest won.
Inspection surfaces the journal as `archive-incomplete` rather than misclassifying dangling
references as valid. State-tree discovery is lazy, reparse-point refusing, deadline-bound, and
stops at the exact active/auxiliary/archive plus-one before reading file content.

`Invoke-SiLifecycle.ps1 -Operation Surface` is the interactive remote-state entry point. It fetches
and pins `origin/main`, reads bounded schema-valid manifest/run blobs from that immutable commit, and
classifies fixed `si/<due-id>` plus `si-repair/<observation-id>` remote branches. Its result is a
closed metadata projection only: IDs, lifecycle states, defer timestamps, OIDs, and candidate
disposition/proposal counts. Candidate titles, rationales, sources, targets, choices, and stored
wrappers never reach the caller. Missing or malformed authoritative state fails explicitly rather
than returning partial success. Blob size is checked from Git object metadata before content is
materialized; tree/ref listings stop at their plus-one line; schema diagnostics are replaced with a
fixed error; canonical ranked-set integrity is rechecked; completed and in-flight limits are enforced
independently; manifest/run IDs and nonterminal states must agree; optional defer timestamps are
compared as absolute instants rather than host-local wall-clock values. The complete bounded active
run tree is scanned even when the manifest has no run references, and run-first/manifest-second
orphans surface by run/due ID and status as `repairable-orphan` metadata and make the overall result
non-empty. Pending plus in-flight dues share the 128-entry manifest ceiling.
Surface re-derives every content-addressed due from repository/plan/source provenance, binds
in-flight run provenance back to its manifest due, rejects duplicate due/run references across all
lifecycle arrays, and budgets fixed due branches for both 128 active dues and 64 retained completed
run references. Every manifest/run timestamp is explicitly parsed as RFC 3339 because JSON Schema
format annotations alone are non-asserting; parse failures return fixed errors. Every loaded run,
including an orphan, re-derives its due from provenance. Ranked states also re-run the shared JCS
candidate-ID and ranked-set-digest algorithm before any outcome counts are surfaced.

`Get-SiHarvest.ps1` is the bounded free-text scanner. It uses `PlanState`'s shared folder parser
to resolve one inventoried legacy, unprefixed-hash, or prefixed-hash plan, then enumerates
the closed active set (manifest, seven ledger categories, three layout-resolved logs, learning
overflow, phase receipts, recorded feedback, and active SI runs), and reads every present file once
when creating a snapshot from the pinned commit's immutable blobs, never from a concurrently
changing worktree. Plan identity and assets-versus-legacy layout are also resolved from that pinned
tree, so mutable worktree metadata cannot redirect or omit a source; duplicate pinned copies across
both layouts fail closed rather than silently selecting one. Git object sizes are checked
against source and aggregate ceilings before blob
content is materialized. A scan refuses more than 256 files, 160 MiB, or 60 seconds, streams
directory discovery to its plus-one boundary, validates manifest/run/phase-receipt integrity, and
enforces each source's smaller operational ceiling. Every Git child process shares the same
remaining scan deadline and is terminated on expiry; a blocked object read cannot outlive the
60-second contract. Archives and resolver outputs are absent unless
the operator supplies an exact pinned path under a closed auxiliary/archive root. The scanner
selects at most 1,024 records / 4 MiB in recurrence-severity-blast-radius order, proves each record
can fit a page before publication, pages at 64 records / 256 KiB, and wraps every returned record
with a fresh untrusted-input fence after neutralizing stored fence tokens in both content and source
metadata.

The selected window and source digest table are persisted in the single bounded
`docs/self-improvement/harvest-index.json` scaffold through `AtomicStore.psm1`; raw unselected
content is not copied. The index binds the resolved plan and pinned HEAD OID. Continuation cursors
also bind the snapshot and selected-window digests. Continuation pages validate the canonical index,
its closed source/record shapes, bounds, ranking order, and content-addressed digests, then page that
persisted window without rereading the bounded source set. Missing, replaced, or inconsistent index
content makes the cursor stale rather than mixing pages from different evidence sets.

The SI skill never opens those source files itself: installed `Get-SiHarvest.ps1` is the sole
free-text read path. After ranking, the resolver accepts only a closed 0-5 candidate JSON shape,
assigns content-addressed candidate IDs, and writes a resolver receipt through `AtomicStore.psm1`.
`SiResolverReceipt.psm1` is the shared JCS implementation for issuance and verification. Receipt IDs
are exactly `sha256(UTF8("si-resolver-receipt-v1") || JCS(payload))`; the payload binds due/run,
pinned OID, snapshot/selected/ranked-set digests, and ordered candidate IDs.
`Test-SiResolverReceipt.ps1` schema-validates, re-canonicalizes, and re-hashes the installed receipt,
rejecting additional fields, duplicates, mutations, or a filename/content mismatch.

`Invoke-SiLifecycle.ps1 -Operation Begin|RecordChoices` is the only interactive admission path for
ranked candidates and operator choices. Both operations refetch and pin `origin/main`, invoke the
installed receipt verifier, require the receipt and current harvest index to bind the same pinned
OID/snapshot/selected window and due/run, then create or resume the fixed `si/<due-id>` branch in the
detached SI worktree. New worktrees start at pinned main; resumes start at the surfaced fixed-branch
head so locally generated receipt/index files cannot collide with a checkout. `Begin`
re-canonicalizes the supplied 0-5 full candidate objects and persists
only an exact receipt match; `RecordChoices` requires one closed choice per receipt candidate and
keeps proposal references null until proposal creation. Same-input replay is byte-stable and reports
no mutation; absent, stale, fabricated, omitted, extra, duplicate, or rewritten input fails before a
state transition. Resumed run files receive the same byte, closed-schema, timestamp, and canonical
integrity validation as pinned runs. The lower-level state writer retains run-first/manifest-second
CAS ordering and admits a matching in-flight retry without consuming a second capacity slot.

`Invoke-SiProposalSync.ps1` is the GitHub trusted-base proposal transport. It must execute from a
clean installed checkout outside the proposal worktree whose HEAD exactly equals the fetched main OID. A
clean `si/<due-id>` branch supplies a lifecycle-only commit followed by proposal commits; sync
refuses any later `docs/self-improvement/**` edit and limits the lifecycle commit to the manifest,
one canonical run, one content-addressed receipt, and the transient harvest index. All mutation runs
in a disposable detached worktree, so refusal cannot strand merge/state commits on the operator
branch. Sync merges current `origin/main`, restores the complete SI subtree from that authority, then
regenerates only the schema/canonical/receipt-verified run, exact receipt, and derived manifest
through shared atomic/state writers in receipt/run/manifest order. Before transport it rejects the
closed trust-anchor set (canonical and installed SI scripts, schemas, guides, prompt, manifest, and
scope guard), then launches the trusted `Test-SiWriteScope.ps1` in a child process. HEAD is pinned
before final checks, and every merge/diff/restore/guard uses the captured main OID rather than its
mutable remote-tracking ref. Sync uploads the validated object through a unique staging ref, then
uses GitHub `createRef` for expected absence or `updateRefs` with `beforeOid` and `force:false` for
an existing branch. The provider therefore compares the expected old OID in the same transaction
that installs the validated OID; exact remote-head confirmation follows. Both disposable worktree
and remote staging-ref cleanup are checked, and either cleanup failure blocks success.

`Complete-SiProposal.ps1` is the separate operator-only merge authority; `/si` never invokes it.
It runs only from a clean detached installed checkout pinned to freshly fetched `origin/main`,
queries the live fixed-branch PR, fetches and cross-checks that head, and requires regular-file,
bounded, strict-UTF-8 manifest/run/resolver-receipt/repair artifacts before materializing the
untrusted tree. It then replays the trusted scope, trust-anchor, receipt, run, and manifest checks in
a disposable worktree.
For run PRs it writes the
recoverable run-first/manifest-second completed transition to the fixed branch before merging.
Provider failure therefore leaves a resumable completed branch, while authoritative main remains
pending. The operator passes the retained `lifecycleHeadOid`; completion verifies it is an ancestor
and that its exact candidate dispositions still match the live run, so a later branch push cannot
rewrite the operator's choices. Immediately before merge it refreshes the PR and requires the same
repository, `main` base name/OID, fixed branch, and head OID, then marks a draft ready and calls
GitHub's merge mutation with `expectedHeadOid` in the same process. An ambiguous provider response
is reconciled against the merged PR. Provider failures retain sanitized diagnostics capped at 4 KiB
so stale-head, checks, protection, authentication, and rate-limit failures remain distinguishable.
A later retry fetches the provider's immutable pull-request head
and binds the provider's historical base and merge commit as ancestors of freshly fetched
`origin/main` before rerunning the same lifecycle binding, scope, exact-state, or trusted repair
replay checks. The proposal-stored pinned base must equal that provider base; it never substitutes
the current mutable manifest for the historical merge tree. Repair PRs use
`si-repair/<observation-id>` and must carry an
exact content-addressed observation and final apply/rollback receipt whose after digest matches the
proposed state.

Repair Apply creates `backups/<observation-id>/apply-journal.json` at `backup-pending` before
copying backups, advances it to `backup-complete` before any target mutation, and records
`mutation-started` before quarantine or manifest replacement. Rollback by observation ID is valid
without a final apply receipt: pre-mutation journals are cancelled only when the authoritative
manifest digest is unchanged, while mutation-started journals restore the observation-keyed backup.

## `Test-SiWriteScope.ps1`: the write-scope gate

| Aspect | Contract |
|---|---|
| Diff base | `main...HEAD`, plus staged, unstaged, **and untracked** paths — an untracked file is exactly how an unreviewed write would arrive |
| Allowlist | `plugins/`, `docs/`, `.github/skills/`, `.github/agents/`, `.github/prompts/` |
| Denylist | `.github/workflows/` and `.github/actions/`, evaluated **ahead** of the allowlist |
| Confinement | Canonicalize per component, resolving symlinks, then confine — a link inside an allowed folder cannot redirect a write outside the repo |
| Verdict | Exit 0 = in scope. Exit 1 = refuse; the PR must not be opened |

**Why the denylist is not just a narrower allowlist.** `.github/` holds executable workflows, not
only documents. `/si` opens a **same-repo** (non-fork) PR, and a same-repo PR branch runs workflows
with repository secrets **at PR-open time** — before the draft-PR and human-review backstops apply.
A workflow edit that satisfied a coarse `.github/` allowlist would therefore execute
attacker-influenced code with full credentials. Draft-PR and never-auto-merge do not gate code that
runs on PR open, so the deny is checked first and independently.

## Gotchas

- The two skills look adjacent but have opposite failure modes: `/pfb` must never block, and `/si`
  must never proceed on a scope failure. Do not factor them into one "post-plan" workflow.
- A queued `/pfb` marker is consumed by the next **interactive** session. If autopilot runs several
  plans back to back, markers accumulate; that is intended — the queue is a log, not a mailbox with
  one slot.
- `Test-SiWriteScope.ps1` is a *pre-PR* gate, not a commit hook. It sees the whole proposal at once,
  which is the only point where "did this change stay in scope" is answerable.
