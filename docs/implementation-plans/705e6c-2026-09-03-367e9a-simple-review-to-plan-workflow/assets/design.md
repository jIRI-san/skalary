# Approved Design

## Components and boundaries

| Component | Responsibility |
|---|---|
| Planning flow | `/cep` and `/cip` confirm intent and language, run a bounded combined design/requirements pass, draft vertical work, and request a strategic DR only for unresolved design risk. |
| Review flow | `/cr` and `/dr` build one bounded request, select combined or specialist concerns from concrete risks, call OpenAI by default and Claude only for terminal/high-risk independence, then emit direct advisory Markdown. |
| Execution flow | `/ci` and autopilot locate the Git commit that introduced the current planning-confirmation marker, compare the four confirmed criteria assets to that tree, execute the current phase, coordinate native roles directly, run focused validation, and choose no review or one risk-selected review for non-terminal phases. |
| Terminal flow | The final phase skips ordinary post-phase review, optionally compacts edited design notes, runs final focused validation, then writes exactly one whole-plan `assets/reviews/final.md`. |
| Stuck recovery | For observable background delegation, the orchestrator compares progress evidence across two explicit checks, redirects the same agent once, permits one replacement within budget, then stops for the operator. A synchronous call either returns or is interrupted by the host/operator; the skill does not claim it can poll an opaque blocked call. |
| Evidence | Existing `test:`, `file:`, and `review:` markers are verified directly during the active crosscheck against current files, commands, and Markdown reports; no evidence or review receipt is written. |
| Learning handoff | `/ci` or autopilot completion replaces `docs/feedback/recent-learning.md` with a bounded cited summary. Child `3a4498` owns collision-safe fencing and untrusted treatment when `/si` reads it. |
| Human documentation | `docs/operator-guide/README.md`, `planning.md`, `implementation.md`, and `reviews.md` document artifacts, gates, sequencing, budgets, models, retries, and stop/resume paths with Mermaid diagrams. |

## Program flow

```mermaid
flowchart TD
    A[Start /cep or /cip] --> B[Confirm intent, criteria, absolute and fuzzy wording]
    B --> C[Combined design and requirements pass]
    C --> D[Draft MVP-first plan]
    D --> E{Concrete unresolved design risk?}
    E -->|Yes| F[Bounded strategic DR]
    E -->|No| G[Plan ready]
    F --> G
    G --> H[/ci or autopilot admission]
    H --> I{Confirmed criteria changed?}
    I -->|Yes| X[Refuse and return to /cip]
    I -->|No| J[Execute next phase with native roles]
    J --> K{Meaningful delegated progress?}
    K -->|Yes| L[Focused validation and commit]
    K -->|No across two checks| M[Redirect same agent once]
    M --> N{New progress?}
    N -->|No| O[One replacement within call budget]
    O --> P{New progress?}
    P -->|No| Y[Visible operator stop]
    N -->|Yes| L
    P -->|Yes| L
    L --> Q{Terminal phase?}
    Q -->|No| R{Concrete phase risk requires CR?}
    R -->|Yes| S[One bounded risk-selected CR]
    R -->|No| H
    S --> H
    Q -->|Yes| T{Design notes edited?}
    T -->|Yes| U[Compact once; approve cross-note merge/delete]
    T -->|No| V[Final focused validation]
    U --> V
    V --> W[Exactly one whole-plan terminal CR]
    W --> Z{Corrective changes?}
    Z -->|Yes| AA[Replace stale final report within budget]
    Z -->|No| AB[Replace bounded recent-learning handoff]
    AA --> V
    AB --> AC[Complete and archive or stop visibly]
```

## Model and dispatch strategy

| Work | Default | Independent escalation | Bound |
|---|---|---|---|
| Planning and implementation | Current orchestrator plus one OpenAI combined design/validation or judge call when needed | Another specialist only for a concrete unresolved risk | 2 calls default, 5 maximum |
| Non-terminal review | No review unless changed scope has a concrete risk; otherwise one combined OpenAI review | Claude only for a stated high-risk concern | One event plus one changed-scope replacement |
| Terminal review | One OpenAI whole-plan review plus one Claude independent pass inside the same final review event | No additional vendor panel; corrective changes replace the stale event | 5 total calls maximum |
| Availability fallback | Approved replacement model | Replaces the unavailable call | Never adds a pass |

Exact model names are selected after recording representative cost, latency, availability, and
usefulness observations. No telemetry service or runtime model broker is added.

The observations and selected bindings live in the agent-cost design note plus the canonical model
policy assets, not in confirmed plan criteria. Step 1.1 therefore cannot make the running plan stale.

## Review report contract

Plan-associated reports use `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`. A corrective
rerun after source changes replaces the same stage file; Git retains older versions. Standalone review
returns chat output unless the operator explicitly asks to save it.

```markdown
## Source
## Scope
## Completed tasks
## Findings
## Verdict
```

`None.` under Findings is valid only when every selected task completed and found nothing. A failed,
omitted, interrupted, or stuck task is listed under Completed tasks and forces a non-clean verdict.
`## Source` contains one full reviewed commit SHA; `## Verdict` contains exactly `clean`, `findings`, or
`incomplete`. During the active crosscheck, `review:cr` passes only from a complete clean result for the
current requested scope. The persisted report is advisory history, not an authenticated receipt.

Plan-associated writes first resolve the canonical plan and its `assets/reviews/` directory through the
retained plan path resolver; agents never derive a writable path from reviewed content. The direct
CR/DR agents retain read-only review behavior, secret redaction, collision-safe untrusted framing, and
the rule that repository directives are data.

## Criteria baseline

The confirmation marker remains the human-visible planning checkpoint. `/ci` and autopilot locate the
unique Git commit that introduced its current value in `plan.md`, read intent, requirements, risks, and
decisions from that tree, and compare them byte-for-byte with the working tree before mutation. Missing,
uncommitted, ambiguous, or changed criteria refuse execution. Stage/checklist/worktree edits remain
outside those four files. This reuses Git history and the existing marker without a new baseline field,
receipt, or store.

## Cutover order

1. Add the direct report, criteria-baseline, native-delegation, retained-guard, and direct-evidence paths
   alongside the still-active workflow.
2. Prove those dormant paths with focused tests.
3. Prepare every CR/DR/CIP/CI/autopilot and historical-context consumer to use the new shapes without
   removing the old path.
4. In one activation step, switch all consumers, update manifests/dogfood/docs, and delete the old
   producers, schemas, Fleet/generated concern assets, receipts, and repair paths. Commit only when the
   focused installed-consumer and residue checks pass. An interrupted working tree remains visible and
   the last committed workflow remains usable; Git revert is the rollback.

The bounded historical adapter keeps current intent/design/decision/learning Markdown. Its Reviews
kind reads the stable advisory stage files directly or is removed when no active consumer needs it; it
never retains receipt verification as a hidden dependency.

## Decision-ready questions

A complex choice states the current context, concrete examples, benefits, pros/cons, and 1-10 effort
and complexity. Include a Mermaid diagram when relationships or sequencing affect the decision. Active
skills, agents, instructions, design notes, and architecture notes are audited for absolute and fuzzy
language; archived plans remain historical.

## Security boundary

A security finding identifies attacker or untrusted input, reachable capability, affected asset, and
plausible impact. Prompt injection, secrets, destructive actions, physical write confinement, and
externally consumed formats remain reviewed. Auth, signing, attestation, audit trails, rollback
journals, multi-tenant isolation, remote CI, or multi-operator coordination are requested only when a
change introduces that boundary. Material extra machinery is presented as simple versus safer options
with residual risk for operator choice.

These retained guards ship in the direct review path before activation. They are not deferred to a
later hardening phase.

## Closed review and recovery outcomes

- A non-terminal review permits one initial event and one replacement only after corrective changes.
- The terminal review event uses the selected OpenAI and Claude calls inside the five-call task budget.
- Findings require a corrective change before replacement; unchanged scope is not rerun.
- Exhausted calls, incomplete attendance, repeated findings without an accepted correction, or a stuck
  replacement produces `incomplete` or `findings` and stops for the operator.
- Optional local `docs/review-standards.md` remains a bounded Markdown input. Generated generic-standard
  JSON and concern registries are retired with the old engine.

## Rejected alternatives

| Alternative | Reason |
|---|---|
| Keep Fleet and simplify its schema | Retains scheduling, attendance, retry, and state concepts that native orchestration already provides. |
| Fixed concern/model matrix | Repeats context and cost without a concrete risk trigger. |
| Time-based agent watchdog | Kills slow but progressing work; progress evidence is the relevant signal. |
| Keep both terminal phase and final reviews | Duplicates the same effective scope; `2aa7ec` demonstrated six terminal-phase plus three finalization cycles. |
| Automatic cross-note merge/delete | Risks semantic loss; operator approval is cheap and proportionate. |
| Replace receipts with another digest or report store | Recreates the removed authority machinery instead of using current Git and readable Markdown. |
