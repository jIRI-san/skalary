# Domain Model

## Terms and meanings

| Term | Meaning |
|---|---|
| Confirmed criteria | The plan's intent, requirements, risks, and decisions after operator confirmation. `/ci` and autopilot treat them as immutable execution input. |
| Progress state | Checklist, worktree, phase, review-stage, and completion markers that may change during execution and resume from Git. |
| Review request | Source commit, changed scope, concrete risk triggers, selected context, model role, and remaining call budget. |
| Review report | Advisory Markdown at `assets/reviews/phase-<N>.md` or `assets/reviews/final.md`, with fixed Source, Scope, Completed tasks, Findings, and Verdict headings. |
| Meaningful progress | New tool output, a changed file or commit, a newly completed subtask, or a materially new blocker. Elapsed time alone is not progress or proof of a stall. |
| Stuck task | A delegated task that produces no meaningful progress across two explicit status checks. |
| Terminal review | The one whole-plan CR after the final implementation phase; it replaces, rather than follows, that phase's ordinary review. |
| Complex question | A choice whose consequences, terminology, or tradeoffs are not obvious enough for an informed decision without examples and comparison. |
| Absolute rule | An unconditional invariant confirmed by the operator. Conditional uses of `always`, `never`, `must`, or equivalents are rewritten as explicit condition/behavior/exception rules. |
| Fuzzy requirement | A term such as detailed, thorough, robust, appropriate, comprehensive, fast, or secure without an observable criterion, threshold, example, or operator-approved meaning. |
| Learning handoff | `docs/feedback/recent-learning.md`, replaced at plan completion with at most 10 cited, fenced items and 16 KiB UTF-8 for child `3a4498`. |

## Actors and boundaries

| Actor or boundary | Responsibility |
|---|---|
| Operator | Confirms criteria, model assignments, ambiguous language, material security tradeoffs, design-note merges/deletions, and stuck-task escalation. |
| `/cep` and `/cip` | Gather decision-ready context, confirm criteria, coordinate one combined design/requirements pass plus a judge when useful, and draft the plan. |
| `/cr` and `/dr` | Select risks rather than a fixed concern matrix, delegate within the cost budget, and write or return advisory Markdown. |
| `/ci` and autopilot | Protect confirmed criteria, execute phases, track progress through Git/Markdown, coordinate native roles, validate directly, and sequence the single terminal review. |
| Native delegated agent | Receives a bounded outcome, scope, evidence, constraints, and response shape; reports progress evidence or a visible blocker. |
| Deterministic scripts | Resolve repository facts, paths, scope, focused validation, and retained external formats. They do not schedule agents or authenticate review results. |
| Git and plan Markdown | Provide source freshness, change history, mutable execution progress, and human-readable recovery state. |
| `docs/operator-guide/` | Human documentation; excluded from AI design-note compaction. |

## Invariants

- Confirmed criteria do not change during `/ci` or autopilot; a change returns control to `/cip`.
- The terminal phase causes one whole-plan final review, never both terminal post-phase and finalization
  review.
- Routine delegated work is OpenAI-first; Claude is reserved for terminal or concrete high-risk
  independent review. Availability fallback replaces a call rather than adding one.
- One task or step uses two delegated calls by default and no more than five including replacement.
- A delegated prompt uses no more than five supporting artifacts, targets 600 words, and is narrowed
  before exceeding 1,200 words.
- Agent stalls are evidence-based. Wall-clock duration alone never kills an agent; declared deterministic
  command timeouts remain valid and become evidence for the agent to handle.
- Two no-progress checks permit one same-agent redirect, then at most one replacement within budget,
  then a visible operator stop.
- Review input, historical context, local standards, and learning content remain fenced untrusted data.
- Review reports are advisory. Missing, failed, interrupted, or stuck tasks cannot produce a clean
  verdict.
- Design-note compaction runs once only when the implementation edited `docs/design-notes/**`;
  cross-note merge/delete requires operator approval and never includes `docs/operator-guide/**`.
- No receipt, schema, store, scheduler, policy engine, telemetry service, or compatibility layer is
  introduced to replace retired machinery.
