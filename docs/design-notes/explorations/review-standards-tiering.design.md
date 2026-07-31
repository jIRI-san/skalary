---
description: Deferred exploration — two-tier code and design review standards (generic in this repo, per-consumer-repo overrides), unified with the review ledger and fed by cr/dr logs, with promotion from consumer repo to generic via the self-improvement loop. Load before changing review agent concerns or review-ledger structure.
globs:
  - plugins/code-review/**
  - plugins/design-review/**
  - docs/review-ledger/**
---

# Review Standards Tiering

Operator note captured 2026-07-31 during `b0c0d3` execution. **Not yet analysed** — recorded for the align phase.

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
