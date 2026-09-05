---
description: Architecture contract for direct review, evidence, criteria protection, and native orchestration.
globs:
  - "scripts/skalary/{DirectWorkflow,Get-DirectPlanArtifactConsumerContext}.ps*1"
  - "plugins/{code-review,design-review,create-implementation-plan,continue-implementation,autopilot}/**"
---

# Direct workflow

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Direct-Workflow` | provisional | Direct advisory reviews, Git-backed criteria, current-run evidence, and native bounded orchestration |

## Invariants

- Plan execution byte-compares confirmed intent, requirements, risks, and decisions with the unique Git
  commit that introduced the current confirmation marker before mutation.
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
- Current test, file, and active in-memory review results are evidence. Persisted reports are advisory;
  there is no receipt, run store, generated concern registry, or repair authority.
- Native calls use two delegates by default and five maximum. Observable background work gets two
  progress checks, one redirect, and at most one replacement; synchronous calls remain a host boundary.
  Elapsed time does not kill agents. Declared deterministic command timeouts remain.
- Non-terminal review is risk-selected. The terminal phase skips post-phase review and runs one
  whole-plan review; unchanged scope is not rerun.
- Historical context is at most five confined, secret-screened Markdown artifacts, framed once as
  untrusted input without receipt validation.
- If a planning, review, CI, or autopilot surface needs a complex predefined operator choice, both hosts
  receive the same context, example, benefits, pros/cons, recommendation/default, effort and complexity
  scores, plus Mermaid only when relationships or sequencing matter. Free-form input remains one focused
  question at a time.
