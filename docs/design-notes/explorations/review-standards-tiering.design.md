---
description: Resolved exploration — plan 2366ad shipped bounded generic standards and optional repository-local extensions/replacements; automated ledger promotion remains intentionally deferred. Load before changing review agent standards or review-ledger promotion.
globs:
  - plugins/code-review/**
  - plugins/design-review/**
  - docs/review-ledger/**
---

# Review Standards Tiering

> **Resolved by plan `2366ad`.** Generic entries now live in the closed concern registry and ship
> with both review plugins. A bounded optional `docs/review-standards.md` may extend or replace only
> entries explicitly marked localizable. Resolved entries retain concern ownership, and dispatch
> sends each reviewer only its matching entries inside untrusted-input fences. Automated promotion
> from review logs or the ledger remains deferred rather than silently changing review policy.

Operator note captured 2026-07-31 during `b0c0d3` execution. The implemented subset is recorded
above; the remaining text preserves the broader promotion ideas and open questions as history.

## Proposal

Review agents should judge against **declared standards**, not only against whatever the model considers good practice.

Two tiers:

| Tier | Scope | Content |
|---|---|---|
| Generic | this repo, shipped with the plugins | language-level rules, general architecture and design patterns |
| Repo-specific | the consumer repo | that codebase's own rules, overriding or extending the generic set |

A rule that proves broadly valuable in a consumer repo gets **promoted** to the generic tier via `/si` — the self-improvement loop already being built in `b0c0d3` (REQ-14), which opens a PR against this repo.

## Why this matters

Today the concern agents (`b0c0d3` REQ-8) carry their focus lens as prose inside each `.agent.md`. That prose is the standard, and it is duplicated per agent, unversioned, and not overridable per repo. Splitting reviewers by concern makes this worse before it makes it better: seven agents each carrying their own implicit standard is seven places for drift.

## Unification with existing machinery

The operator's key point: this should **merge with the review ledger**, not sit beside it. Three artifacts currently hold overlapping knowledge:

| Artifact | Holds | Direction |
|---|---|---|
| `docs/review-ledger/<category>.md` | durable harvested lessons | written at plan completion, read before CR rounds |
| `assets/logs/cr-log.md` | per-plan CR findings + triage | written during execution, harvested at completion |
| concern agent prose | the standard being judged against | static, never updated by outcomes |

The third never learns from the first two. Closing that loop is the substance of this exploration: `cr` and `dr` logs should feed the standards, so a finding raised repeatedly becomes a codified rule rather than a recurring rediscovery.

## Open questions

| Question | Note |
|---|---|
| One file or per-concern files? | Operator leaned toward "same file" with categories per concern agent; needs weighing against the 7-agent split |
| Relationship to the concern→ledger map | `b0c0d3` REQ-10 already maps concern → ledger category; standards could key off the same taxonomy |
| Override semantics | Does repo-specific replace, extend, or narrow the generic rule? Silent replacement is a footgun |
| Promotion criteria | What evidence justifies promoting a consumer-repo rule to generic? Recurrence count already exists in the ledger contract |
| Distribution | Generic standards are plugin payload, so they install under `.github/`; repo-specific ones are consumer-authored and must not be overwritten on update |

## Interaction with shipped work

Depends on `b0c0d3` REQ-8 (concern agents), REQ-10 (concern→ledger map) and REQ-14 (`/si` PR loop). Best sequenced after that plan lands, since all three are its direct substrate.

## Confirmed as the missed intent at `b0c0d3` acceptance

At the step 10.7 operator gate the plan was accepted with a qualification: the requirements were **met**, but the operator "had slightly different idea about how we will do the CR/DR, and we did not dive into it during the planning, because I scoped it only as a split per concern and model change."

This note is that different idea. It was captured *during execution*, after the scope was already fixed — which is exactly the failure mode it now serves as evidence for. The plan asked *how* to split reviewers and got a correct answer. Nobody asked *why* the split was wanted; had they, declared standards would have surfaced as the actual goal and the concern split as one means to it.

Consequences for the sequencing above:

- This is no longer a speculative enhancement to `b0c0d3`. It is the **unstated requirement** `b0c0d3` was a partial implementation of, which raises its priority in the following plan.
- The seven-agent split is not wasted — a per-concern standard needs a per-concern reviewer to consume it. But the split shipped without the thing that gives it leverage, so the drift risk noted under *Why this matters* is live now, not hypothetical.
- Use this case as the **test case for rephrase-and-confirm** in [intent-and-domain-capture.design.md](intent-and-domain-capture.design.md). The concrete bar: would the mechanism have asked *why* the split was wanted, and would that question have surfaced declared standards before the plan was drafted? A mechanism that only echoes back "you want reviewers split by concern and two models" restates the request faithfully and still misses the intent — that is the standard to beat, not a passing grade.
