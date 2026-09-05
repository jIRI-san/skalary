---
description: Resolved exploration — `/si` cross-repository learning uses one bounded typed artifact and a clean upstream-rooted handoff into normal `/si` or `/cip`; rejected cache, container, credential, and publication alternatives remain as history.
globs:
  - plugins/self-improvement/**
  - .github/skills/si/**
  - scripts/skalary/Test-SiWriteScope.ps1
---

# `/si` Cross-Repo Proposal Protocol

> **Resolved by plan `2366ad`.** The implemented shape keeps the useful harvest/propose boundary but
> deliberately omits the cache, container, credential, and publication platform explored below.
> One bounded typed artifact is accepted by a clean upstream-rooted checkout, which then uses normal
> upstream `/si` for small work or `/cip` for plan-sized work. The historical alternatives remain
> below as exploration context, not executable direction.

Operator note captured 2026-08-01, immediately after the first real `/si` run. The simplified
resolution is recorded above; the remainder preserves the alternatives considered before plan
`2366ad`.

## The problem

`/si` harvests in the repo it runs in and proposes to the repo it runs in. That is correct only when
those are the same repo, which is true for skalary and false for every consumer.

The rule that covers the mismatch exists in exactly one place — `SKILL.md` Step 0.2:

> In a consumer repo the customizations arrive through the registry, so an improvement belongs
> upstream: harvest locally, then carry the candidate list to the source repo by hand. The
> fork/upstream round-trip is deliberately manual.

Nothing enforces it. `propose-guide.md` allowlists `plugins/**`, `docs/**` and
`.github/{skills,agents,prompts}/**`, and Step 4 cuts a worktree from the *current* repo's
`origin/main`. Run in a consumer repo, `/si` therefore does not refuse — it opens a PR against that
repo's **installed plugin copies**, which the next `Install-Plugin` run overwrites. The proposal is
silently discarded, upstream never receives it, and no control reports anything.

## Why "just tell the agent to follow the upstream rules" does not work

Instruction resolution is a property of the harness and the workspace, not of the prompt. A session
running in a consumer repo loads that repo's `copilot-instructions.md`, its design-note index, its
architecture-note tier, its validators. Reading skalary's `.design-notes.md` into that session as
*text* and asking the agent to comply is prose-level enforcement of a rule that governs how this
repo's own instruction files get edited — the exact failure mode this repo keeps rediscovering.

Executing the edit inside a skalary worktree makes the harness load skalary's rules. That is the
decisive argument for the split, independent of any security benefit.

## Proposed shape

Two phases joined by a typed artifact.

| Phase | Runs in | Reads | May write | Output |
|---|---|---|---|---|
| 1 — harvest | consumer repo | the four harvest sources | proposal artifact only | typed candidate record |
| 2 — propose | upstream worktree | the artifact + upstream's real code | current `/si` allowlist | draft PR |

Both phases run even when the two repos coincide, so there is one code path and the artifact is
always written.

Phase 1 needs a **different, much narrower write scope** than phase 2 — it may write the artifact
and nothing else. `Test-SiWriteScope.ps1` already enumerates, canonicalizes and refuses; it needs a
phase-scoped allowlist rather than new machinery.

## What this does and does not do for injection

It is **privilege separation, not sanitization**. Stating both halves, because the difference
decides what still has to be built.

Gained:

- The high-exposure step (reading N untrusted free-text sources) and the high-privilege step
  (writing files that govern every future agent run) are in different sessions with different
  allowlists. A fully injected phase 1 can only emit a document that lies; it cannot reach a
  governing file.
- Phase 2's untrusted input becomes **one artifact in a known shape** instead of ten free-text
  files. If the artifact is constrained to typed fields — source path, entry id, quoted evidence,
  defect class, enum severity — there is no free-text field phase 2 must interpret as instruction.
  That, rather than the split itself, is the actual hardening.
- A human gate falls naturally between the phases.

Not gained:

- Phase 2 still reads untrusted content and still needs the fence.
- Phase 1 can still be induced to emit a plausible-but-false candidate (*"relax the workflow
  denial"*). The `Test-SiWriteScope` allowlist remains the real backstop, exactly as today.

Net: injection narrows from *can it reach the file writer* to *can it survive reduction to a typed
record and re-judgement against the real upstream code*. The existing controls stay load-bearing.

## The asymmetry to design against

Same-repo, the artifact can be a **pointer**: phase 2 re-reads the actual cr-log and ledger and
verifies the claim. Cross-repo it cannot — phase 2 has no access to the consumer's records — so the
artifact must carry **quoted evidence as payload**. A payload is strictly weaker than a pointer:
nothing downstream can check it against its source.

Consequence: phase 2 should treat cross-repo evidence as *claim*, and promotion to the generic tier
should require corroboration from upstream's own history rather than the consumer's assertion alone.
That promotion decision requires corroboration from upstream history.

## Materializing the upstream checkout during phase 1

Operator variant, same session: rather than leaving the round-trip to the operator, phase 1
**locates or clones skalary into a cache directory outside the consumer repo**, creates the
`si/<slug>` branch from `origin/main`, writes the artifact there, and commits it. Phase 2 then has
both its input and its target tree already on disk.

Two advantages over the hand-carried version:

- **It kills the staleness problem.** The artifact and the target tree are materialized together, so
  phase 2 cannot be reasoning about a `main` that moved months ago.
- **A container mounting only the skalary checkout is a harder instruction boundary than a
  worktree.** In a worktree the harness may still resolve the consumer's `copilot-instructions.md`
  and design-note tier depending on how the workspace is rooted. In a container whose workspace root
  *is* skalary, the consumer's rules are absent rather than deprioritized. That is enforcement by
  construction, which is the distinction this repo keeps failing on.

The checkout must not live inside the consumer repo — it would pollute `git status` and risks being
committed. A cache directory with a reuse-or-clone decision is required.

## Executing phase 2 locally — and why not as a new autopilot mode

The tempting next step is to launch the autopilot container against that checkout with instructions
to run `/si` phase 2. **Autopilot's safety properties come from the plan contract** — phases, budget
points, per-step commits, current typed evidence, and the completion gate. Driving it from free-form
"instructions" instead of a `plan.md` keeps the autonomy and drops the guardrails, in the one place
with the highest blast radius in the system: unattended edits to the files that govern every future
agent run, triggered by a harvest of untrusted text.

The existing backstops still hold — `Test-SiWriteScope`, the absolute workflow denial, draft-only
PRs, never-merge. So the objection is not that it is unsafe; it is that it would be the only
autonomous writer in the pipeline with no plan-shaped bound, and the human gate degrades from
*review each edit* to *approve a launch whose shape you have not seen*.

**Resolution: if a proposal is big enough to want autopilot, it is big enough to be a plan.** Phase 2
gets two exits rather than a new execution mode:

| Proposal size | Phase 2 |
|---|---|
| Small — a rule in an existing asset, a script fix | interactive session rooted in the skalary checkout |
| Large | run `/cip` *in the skalary checkout* with the artifact as input, then autopilot the resulting plan normally |

The loop still runs end-to-end on the operator's machine, the container still supplies the
instruction boundary, and `/si` never becomes a second thing that can autonomously write to the repo.
The first `/si` run bears this out: all three accepted candidates were two script fixes and a guide
correction.

## Risks introduced by materializing and executing locally

| Risk | Note |
|---|---|
| **Credential escalation** | Phase 1 needs no upstream write access today. Launching a container that pushes means the consumer environment forwards skalary push credentials plus a Copilot token. This is the largest change to the threat model and must be an explicit per-run operator decision, never inherited from an autopilot config |
| **Version skew** | Findings are harvested against the *installed* plugin version; phase 2 edits upstream `main`. A defect already fixed upstream gets "fixed" again. The artifact must pin the installed version and phase 2 must check it |
| **Checkout location** | Outside the consumer tree, in a cache dir, with a reuse-or-clone decision |
| **Docker absent** | Degrade to the interactive or hand-carried path rather than failing |

## Free consequence: it closes Cluster F

The proposal artifact **is** the durable record that Cluster F and gate finding [17] say does not
exist. Today `/si` leaves no trace of what it proposed or what the operator declined — Cluster G of
the enforcement-gaps note had to be written by hand for that reason, an hour after the loop shipped.
Making the artifact the interchange format turns that record from a discipline into a by-product.

## Open questions

| Question | Note |
|---|---|
| How does the artifact travel? | Branch in a locally materialized upstream checkout (see above), a GitHub issue, or fully manual. The branch option reuses `Test-SiWriteScope` with a phase-1 allowlist |
| Does phase 1 need upstream credentials? | Cloning and branching locally does not require push. Pushing or launching a container that pushes does — keep that a separate, explicit decision |
| Staleness | Solved if phase 1 materializes the checkout; otherwise phase 2 must re-derive against current upstream state rather than trust the artifact |
| Does the finding generalize? | A defect under a consumer repo's own standards may be correct under the generic ones. The artifact needs an explicit "claimed to generalize because…" field |
| Artifact schema | Typed fields are the hardening; a free-text `notes` field would reintroduce the surface the split removes. Must also carry consumer repo identity, plan ref, and installed plugin version |

## Interaction with shipped work

Depends on `b0c0d3` REQ-14 (`/si`) and its `Test-SiWriteScope` guard, both of which are the
substrate rather than obstacles. The local-execution variant additionally reuses the `autopilot`
container and the `/cip` → autopilot pipeline unchanged, which is the point: no new execution mode.
Any later promotion rule must define when a consumer-repo observation earns generic status.
