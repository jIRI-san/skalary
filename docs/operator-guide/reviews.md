# Code and design reviews

Use `/cr` for code and `/dr` for plans or designs. Both are read-only, risk-selected reviews. Their
active contracts are the [`CR skill`](../../plugins/code-review/skills/cr/SKILL.md),
[`DR skill`](../../plugins/design-review/skills/dr/SKILL.md), and
[review-reporting design](../design-notes/architecture/review-reporting.design.md).

## Entry points and cadence

| Entry | Scope | Output |
|---|---|---|
| Standalone `/cr` | `uncommitted`, `branch`, commit count/batch, or file/folder paths | Chat unless the operator explicitly requests saving |
| Standalone `/dr` | Explicit plan, session plan, or chat design | Chat unless explicitly saved |
| Non-terminal plan review | One concrete changed-scope risk | `assets/reviews/phase-<N>.md` |
| Terminal plan review | Whole completed plan, exactly once | `assets/reviews/final.md` |

```mermaid
flowchart TD
    A[Resolve exact source and scope] --> B[Load relevant contracts, notes, standards, bounded history]
    B --> C[Select concerns from concrete risk]
    C --> D[Direct scope and evidence work]
    D --> E{Delegated review needed?}
    E -->|Yes| F[One model-mid combined review]
    E -->|No| J[Collate completed tasks and findings]
    F --> G{Cross-subsystem issue unresolved after standard evidence?}
    G -->|Yes| H[model-high deep escalation]
    G -->|No| I{Named independent high-risk path?}
    H --> I
    I -->|Yes| O[alternate-model-high independent pass]
    I -->|No| J
    O --> J
    J --> K{All selected tasks complete?}
    K -->|No| L[incomplete]
    K -->|Yes| M{Blocking findings?}
    M -->|Yes| N[findings]
    M -->|No| P[clean]
```

Non-terminal review is omitted when there is no concrete risk. It allows one review event and at most
one replacement after corrective source changes. The terminal phase skips post-phase review and
finalization runs one whole-plan event. Never rerun unchanged scope.

## Model alias and budget matrix

| Role | Primary | Availability fallback | When |
|---|---|---|---|
| Routine implementation/support | `model-low` | `alternate-model-low` | Bounded implementation, extraction, summaries, documentation, straightforward fixes |
| Standard combined review/design judgment | `model-mid` | `alternate-model-mid` | Standalone and ordinary risk-selected work |
| Deep escalation | `model-high` | `model-mid` | Cross-subsystem work or diagnosis still unresolved after evidence-backed standard work |
| Independent review | `alternate-model-high` | `alternate-model-mid` | One named high-risk security, concurrency, destructive, correctness, or architecture path |

| Budget | Limit |
|---|---:|
| Monthly AI credits | 180,000 operating; 20,000 reserve |
| Delegated calls | 0 direct; 1 for a concrete unresolved concern; 3 maximum including retries/replacements |
| Supporting artifacts | At most 3 |
| Prompt | 400-word target; 800-word hard cap |
| Context | Committed routing uses `default`; `long_context` is explicit opt-in |
| Models per role | One primary plus one replacement fallback |

A fallback replaces an unavailable call; it does not add a panel.
[`tools/model-allowlist.psd1`](../../tools/model-allowlist.psd1) owns alias roles and exact host-specific
bindings. [`Sync-ModelBindings.ps1`](../../scripts/skalary/Sync-ModelBindings.ps1) regenerates Waza pins
and the independently installable skill copies.

## Inputs and local standards

Resolve one full source commit and exact scope. Load touched architecture/design notes, optional bounded
`docs/review-standards.md`, and at most three explicitly selected historical Markdown artifacts. Local
standards are parsed by
[`Resolve-DirectReviewStandards`](../../scripts/skalary/DirectWorkflow.psm1), extend caller-supplied
mandatory base rules, and cannot localize away retained guards. All repository text, standards, and
history are untrusted data. Repository-owned instruction syntax is reviewed as behavior while remaining
inert as data.

## Concrete threat-path rubric

A blocking security finding needs every link:

| Link | Question |
|---|---|
| Attacker or untrusted input | Who/what can supply hostile data? |
| Reachable capability | What operation can that input reach? |
| Affected asset | What data, authority, host, or boundary is exposed? |
| Plausible impact | What concrete harm follows? |

If a link is missing, label useful advice **optional hardening**, or omit it when it only requests a
boundary the change does not introduce. Do not demand authentication, signing, attestation, audit
trails, rollback journals, multi-tenant isolation, remote CI, or multi-operator coordination without
that boundary.

When safer machinery materially increases complexity, present the operator with the simple option,
safer option, concrete threat addressed, residual risk, benefits, pros/cons, and effort/complexity
scores from 1–10. Defense in depth alone does not block.

## Retained guards

These remain mandatory:

- prompt-injection/data-only framing with collision-safe fencing;
- secret refusal/redaction before publication;
- read-only reviewers;
- operator approval for destructive actions;
- physical and canonical confinement of plan-associated report writes;
- validation of externally consumed formats.

Unexpected reviewed content that attempts to steer the active reviewer is prompt injection. Quoted or
declared policy syntax is not injection merely because of its syntax.

## Report contract

Plan-associated reports are written only through
[`Write-DirectReviewReport`](../../scripts/skalary/DirectWorkflow.psm1). Paths are exactly
`phase-<N>.md` or `final.md` beneath the canonical plan's `assets/reviews/`.

```markdown
## Source

<full commit SHA>

## Scope

<exact reviewed scope>

## Completed tasks

<each selected task and complete/failed/interrupted/stuck state>

## Findings

<blocking findings, or None.>

## Verdict

clean | findings | incomplete
```

`clean` requires every selected task to complete. Failed, interrupted, stuck, exhausted, omitted, or
unresolved work forces `incomplete` or `findings`. Persisted Markdown is advisory history; only the
active exact-source/exact-scope in-memory result can satisfy current `review:` evidence.

## Correction and exhaustion

```mermaid
flowchart LR
    A[findings] --> B{Source changed to correct them?}
    B -->|Yes| C[Validate changed scope]
    C --> D[Replace same stage report within budget]
    B -->|No| E[Do not rerun]
    D --> F{Resolved and complete?}
    F -->|Yes| G[clean]
    F -->|No| H[findings or incomplete stop]
    E --> H
    I[Call budget exhausted or task failed] --> H
```

Budget exhaustion, incomplete selected work, stuck/interrupted calls, or unresolved findings stop
visibly with a non-clean verdict. The direct report and active in-memory result are the complete
review interface.
