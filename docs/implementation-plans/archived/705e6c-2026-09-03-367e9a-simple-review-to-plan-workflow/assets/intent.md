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
- `/cip`, `/ci`, autopilot, CR, and DR implement the operator-approved call, context, and delegated
  instruction budgets from `2aa7ec`, rather than leaving the RFC advisory.
- Routine work prefers cost-effective OpenAI models while independent review retains strategically
  selected non-OpenAI coverage; the choice is based on an operator-reviewed cost/latency/quality matrix.
- The terminal implementation phase causes exactly one whole-plan final review rather than a post-phase
  review followed by an overlapping finalization review.
- Delegated work cannot wait indefinitely: one progress check, one bounded recovery/replacement within
  budget, then an explicit operator-visible stop.
- Complex operator questions include examples, useful diagrams, benefits, pros/cons, and 1-10
  effort/complexity estimates before asking for a decision.
- `/cip` turns conditional absolute wording into explicit if/then/else rules and asks the operator to
  define fuzzy requirements with observable criteria or examples.
- Security review is concrete and threat-model-aware: retain prompt-injection, secret, destructive-action,
  external-boundary, and write-confinement protections without demanding enterprise controls for a
  trusted single-operator repository.
- Confirmed intent, requirements, risks, and decisions cannot be changed during execution; checklist
  and worktree markers remain mutable.
- Receipt, review-run, schema, fleet, generated-concern, JSON checkpoint, phase-evidence, and repair
  machinery is absent.
- `/ci` cannot weaken acceptance criteria in container or host autopilot.
- A bounded recent-learning Markdown output is available to child `3a4498`.
- If implementation edits AI-facing design notes, `/ci` performs one final compaction and deduplication
  pass without removing unique decisions, contracts, constraints, or representative examples.
- `docs/operator-guide/` explains the complete human-facing `/cip`, `/ci`, CR/DR, and autopilot flow,
  including artifacts, gates, sequencing, limits, stop/resume behavior, and Mermaid diagrams; it is not
  subject to AI design-note compaction.
- Focused tests cover successful review output, criteria-mutation refusal, retained input guards, and
  stale/interrupted behavior, duplicate-final-review prevention, and stuck delegation recovery without
  rebuilding a transaction system.

## Non-goals

- Owning SI proposal selection or write application.
- Owning plugin install/update/remove.
- Authenticating Markdown, signing evidence, preserving old receipt formats, or supporting concurrent
  operators.
- Retaining the fixed fourteen-reviewer matrix or adding another durable review authority.
- Building a scheduler, watchdog service, telemetry pipeline, or prose-policy compiler for delegation,
  language review, model choice, or design-note compaction.
- Adding a runtime cost-policy service; the selected budgets remain direct readable instructions with
  focused behavior checks.

## Definition of done

- Review, plan creation, and autonomous execution work end to end using Markdown and current Git; all
  subsystem-owned obsolete state and receipt machinery is removed; confirmed criteria remain intact;
  final review runs once; stuck work exits visibly; operator questions support informed decisions;
  active design notes stay compact; the operator guide describes the shipped flow; and the bounded
  learning handoff is ready for SI.
