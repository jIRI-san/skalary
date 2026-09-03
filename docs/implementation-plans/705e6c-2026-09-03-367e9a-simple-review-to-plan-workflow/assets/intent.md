# Intent

Preliminary context captured by /cep; /cip must confirm and refine it.

## Goal

Replace the current receipt- and schema-heavy review, planning, and autopilot path with one small
human-readable workflow that preserves operator intent and safely treats reviewed content as data.

## Desired outcome

CR/DR produce direct advisory Markdown using strategically selected reviewers. `/cip`, `/cep`,
`/ci`, and autopilot consume the same simple plan conventions, refuse changes to confirmed criteria,
and use current Git plus mutable checklist/worktree markers for freshness and resume. SI receives one
bounded fenced recent-learning Markdown artifact rather than a durable harvest service.

## Success signals

- Review reports have fixed human-readable headings for source commit, scope, completed tasks,
  findings, and verdict.
- Reviewed and historical content remains fenced as untrusted data; reviewer failure cannot look like
  success.
- Agent/model calls obey the operator-approved budget from `2aa7ec`.
- Confirmed intent, requirements, risks, and decisions cannot be changed during execution; checklist
  and worktree markers remain mutable.
- Receipt, review-run, schema, fleet, generated-concern, JSON checkpoint, phase-evidence, and repair
  machinery is absent.
- `/ci` cannot weaken acceptance criteria in container or host autopilot.
- A bounded recent-learning Markdown output is available to child `3a4498`.
- Focused tests cover successful review output, criteria-mutation refusal, retained input guards, and
  stale/interrupted behavior without rebuilding a transaction system.

## Non-goals

- Owning SI proposal selection or write application.
- Owning plugin install/update/remove.
- Authenticating Markdown, signing evidence, preserving old receipt formats, or supporting concurrent
  operators.
- Retaining the fixed fourteen-reviewer matrix or adding another durable review authority.

## Definition of done

- Review, plan creation, and autonomous execution work end to end using Markdown and current Git; all
  subsystem-owned obsolete state and receipt machinery is removed; confirmed criteria remain intact;
  and the bounded learning handoff is ready for SI.
