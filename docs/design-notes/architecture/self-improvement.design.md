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

`/si` is offered at plan completion by both `/ci` and the autopilot harvest mirror. **Autopilot does
not run it.** `/si` ends in a PR against the repo's own instructions; opening one with nobody having
asked is not an autonomous decision, so a headless run notes that `/si` is available for the next
interactive session and queues nothing.

The consumer-repo fork/upstream flow is documented as manual — `gh` fork entitlement is out of
scope, and skalary is itself the registry, so the PR target is this repo.

## Durable SI state ownership

Self-improvement owns its state schemas and lifecycle commands directly under
`plugins/self-improvement/{schemas,scripts}/`. They are mapped one-for-one into
`.github/skills/si/{schemas,scripts}/`; `Sync-PluginScripts.ps1` must not generate or prune these
plugin-owned sources. `SiStateStore.psm1` is the single owner of the closed schema versions, status
codes, operational limits, topology segments, and run-before-manifest transaction order.

The hot manifest is bounded to 128 pending dues, 16 in-flight runs, 64 recent references, and
256 KiB. Active history is sharded per run and bounded to 32 completed plus 16 resumable files;
archive history is bounded to 4,096 files and 256 files per year/month shard. Every plus-one
operation returns `capacity-blocked` before mutation. Lifecycle commands fail loudly on invalid,
stale, forward-version, or exhausted state rather than exposing partial behavior.

`scripts/skalary/AtomicStore.psm1` is the root-canonical persistence primitive. It provides the
30-second repo-scoped lock, random same-directory temp writes, validation before replace,
generation-digest CAS, and the closed `complete` / `lock-timeout` / `cas-conflict` /
`cas-exhausted` status vocabulary. SI receives that module as a generated bundle closure while
its schemas and lifecycle scripts remain plugin-owned. `SiStateStore.psm1` is the only lifecycle
module that calls the primitive: manifest updates retry at most three generation conflicts, run
completion persists and validates the run before the manifest, and repair Snapshot/Apply/Rollback
share the same state lock.

`Get-SiState.ps1` exposes metadata only. Inspection classifies absent, valid, orphaned, corrupt,
legacy, forward-version, capacity-blocked, and incomplete-apply stores without mutation.
`Repair-SiState.ps1 -Mode Snapshot` content-addresses exact sorted observation bytes; Apply refuses
stale or altered observations, writes the backup and apply journal before replacing state, and
writes the receipt last. Rollback accepts the observation before receipt creation or the receipt
afterward. A v1 migration preserves existing due/run identifiers and arrays; forward versions
remain read-only.

All runtime state paths outside `.github/` are first-use scaffolds declared by
`plugins/self-improvement/plugin.json`: the manifest; year/month active and archive run shards;
observation-keyed backup and quarantine trees plus the quarantine index; repair observations and
receipts; and resolver receipts. Parameterized paths route through `Resolve-SiStatePath`.
`Get-SiState` pages only `{dueId,runId,status}` plus counts/generation; it never returns candidate
text. Local repair copies every observed artifact under the observation-keyed backup before
mutation, reconstructs bounded manifest references from valid run files, quarantines corrupt runs
with an indexed digest, and refuses Apply/Rollback when the exact observation/receipt chain is
stale, altered, or missing. Successful rollback emits its own content-addressed receipt.

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
