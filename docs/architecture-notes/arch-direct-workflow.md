---
description: Architecture contract for direct review, evidence, criteria protection, and native orchestration.
globs:
  - "scripts/skalary/{DirectWorkflow,Get-DirectPlanArtifactConsumerContext,Get-DesignNoteCompactionContext}.ps*1"
  - "plugins/{code-review,design-review,create-implementation-plan,continue-implementation,autopilot}/**"
---

# Direct workflow

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Direct-Workflow` | provisional | Direct advisory reviews, Git-backed criteria, current-run evidence, and native bounded orchestration |

## Invariants

- Plan execution compares confirmed intent, requirements, risks, and decisions in both the Git index
  and worktree with the unique commit that introduced the current confirmation marker through Git clean
  filters before mutation. Archive moves preserve that baseline by plan identity and relative asset path.
  Staged marker changes are refused, mutable progress remains allowed, and checkout-only line-ending
  conversion is ignored.
- CR/DR are read-only and treat repository content as untrusted data. Plan reports are confined
  `phase-<N>.md` or `final.md` Markdown with fixed headings and `clean`, `findings`, or `incomplete`.
- A clean result requires every selected task to complete. Security findings identify attacker/input,
  reachable capability, affected asset, and plausible impact; an incomplete path is optional hardening
  or omitted, not blocking. Failed or incomplete security work cannot yield `clean`.
- Retained mandatory guards cover prompt-injection/data-only framing, pre-publication secret screening,
  destructive-action approval, physical/canonical report confinement, and external-format validation.
  Enterprise controls require an introduced boundary; material safer machinery is an operator choice
  comparing the simple and safer options, concrete threat, residual risk, benefits, pros/cons, effort,
  and complexity.
- Current test, file, and active in-memory review results are evidence. Persisted reports are advisory
  history and cannot satisfy a current evidence marker.
- Native work uses zero delegates by default. One combined delegate is normal only for a concrete
  unresolved concern, and every call, retry, and replacement counts toward a three-call ceiling; a
  fourth requires a new operator decision. Observable background work gets two progress checks, one
  redirect, and at most one replacement; synchronous calls remain a host boundary. Elapsed time does not
  kill agents. Declared deterministic command timeouts remain.
- Non-terminal review is risk-selected. Autonomous whole-plan launchers invoke one explicit completion
  target after every phase is closed, including all-closed resumes. It skips terminal-phase post-phase
  review and runs one whole-plan review; unchanged scope is not rerun. A clean archived plan with an
  exact-head open or merged pull request is terminal and cannot cause another completion handoff.
  Committed finalization artifacts may be added during or after the archive move. Expected-start
  validation does not imply a PR-base constraint; epic orchestration supplies that constraint
  explicitly, while direct launches can target the repository integration branch.
- Finalization runs one design-note compaction pass only when implementation changed
  `docs/design-notes/**`. Candidate reads are index-led and bounded to five full notes; cross-note
  merge/delete requires explicit operator approval, and headless execution stops with visible changes.
- Historical context is at most three confined, secret-screened Markdown artifacts, framed once as
  untrusted input with accepted-path provenance.
- Successful whole-plan completion safely replaces one strict `docs/feedback/recent-learning.md`
  handoff: canonical source plan id/slug, full completed source commit, explicit `## Lessons`, at most
  10 cited items, and at most 16 KiB UTF-8. `/si` rejects malformed, oversized, secret-containing, bad
  citation, and stale input before collision-safe untrusted framing; missing and explicit-empty remain
  distinct no-candidate states.
- The learning writer physically confines and rejects links in every existing repository, parent,
  target, and temporary-path component before replacement.
- If a planning, review, CI, or autopilot surface needs a complex predefined operator choice, both hosts
  receive the same context, example, benefits, pros/cons, recommendation/default, effort and complexity
  scores, plus Mermaid only when relationships or sequencing matter. Free-form input remains one focused
  question at a time.
