---
description: Advisory budgets for agent dispatch, model fallback, historical context, and delegated instruction size. Load when designing or reviewing multi-agent skill behavior.
globs:
  - plugins/**/skills/**
  - plugins/**/agents/**
  - .github/skills/**
  - .github/agents/**
---

# Agent Cost Optimization

Simplicity and useful output outrank additional review voices. These are operator-approved direct
orchestration rules and focused-test expectations, not a runtime model router, price registry, credit
ledger, or telemetry service.

## Monthly operating contract

The GitHub AI-credit ceiling is **200,000 credits per month**: **180,000** for planned work and
**20,000** reserved for incidents and month-end completion. Review actual model-level use in GitHub's
AI-usage dashboard each week. Static repository instructions guide spend but cannot enforce an exact
monthly total.

One AI credit currently equals USD 0.01. This pricing snapshot is dated **2026-09-05**:

| Model | Input credits / 1M tokens | Cached input | Cache write | Output credits / 1M tokens |
|---|---:|---:|---:|---:|
| GPT-5 mini | 25 | 2.5 | — | 200 |
| GPT-5.6 Luna | 20 | 2 | 25 | 120 |
| GPT-5.6 Terra | 200 | 20 | 250 | 1,200 |
| GPT-5.6 Sol | 400 | 40 | 500 | 2,000 |
| Claude Sonnet 5 | 200 | 20 | 250 | 1,000 |
| Claude Opus 5 | 500 | 50 | 625 | 2,500 |

The earlier Sol 50%-off promotion ended on 2026-09-03. Use the
[official pricing table](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
as authority and the
[workflow guide](https://movarnell.github.io/Copilot-Links/models.html#workflow-flows)
as non-authoritative task guidance.

## Model ladder

| Tier | Primary | Replacement fallback | Effort/context | Admitted work |
|---|---|---|---|---|
| Routine | `GPT-5.6 Luna` | `GPT-5 mini` | medium/default | Bounded implementation, extraction, summaries, documentation, straightforward fixes |
| Standard | `GPT-5.6 Terra` | `Claude Sonnet 5` | high/default | Planning, acceptance validation, ordinary CR/DR, complex bounded implementation |
| Deep | `GPT-5.6 Sol` | `GPT-5.6 Terra` | high/default | Cross-subsystem orchestration or diagnosis unresolved after evidence-backed Terra work |
| Independent | `Claude Opus 5` | `Claude Sonnet 5` | high/default | One concrete high-risk security, concurrency, destructive, correctness, or architecture pass |

A fallback replaces an unavailable call. It never adds a panel. Sol and Opus are not routine
fallbacks. Escalation names the unresolved evidence or concrete risk; role attendance and disagreement
alone do not qualify.

## Advisory budgets

| Area | Normal | Maximum |
|---|---:|---:|
| Delegated calls per task or plan step | **0 direct**; **1** when a concrete concern needs separate context | **3**, including retries and replacements |
| Models per role | One primary | One replacement fallback |
| Supporting artifacts | Current criteria plus directly relevant context | **3 selected artifacts** |
| Delegated task instructions | **400-word target** | **800-word cap** |
| High-frequency skill entrypoint | Load only the selected decision path | **4 KiB** for `autopilot`, `cep`, `cip`, `ci`, `cr`, `dr`, and `si` |

Built-in file, search, and command tools are not delegated calls. Deterministic tests, parsers, linters,
and repository facts are the normal Judge. A fourth model call requires a new operator decision. Reuse
an already-open agent when follow-up needs its context instead of paying for a replacement.

## Context and workflow shape

Default context is the only active tier. Do not request or expose `long_context`: it increases token
volume and, above the published thresholds, doubles fresh-input and cache-write rates for Terra and
Sol while increasing output rates.

Load current intent, state, and active contracts first. Select older material only through explicit
concepts or canonical IDs and keep no more than three supporting artifacts. Start a fresh session
between research, planning, and implementation when the prior transcript is no longer needed.

Direct repository work is the default. Planning may use one Terra design/requirements validator when a
choice remains unresolved. Routine implementation uses Luna plus deterministic evidence. A selected
ordinary review is one Terra call. Sol coordinates only cross-subsystem work or unresolved diagnosis.
Opus adds one independent pass only for a concrete high-risk path.

Delegated prompts state the outcome, closed scope, acceptance evidence, constraints, and response shape.
Reference authoritative files instead of copying them. Narrow before 800 words; do not add an
instruction-summary service.

## Premium evals

Tier-2 waza execution is direct, explicit, and plugin-focused. Use Luna for skill execution. Retain
Terra judgment only where behavior is subjective; use deterministic graders for observable output,
refusal, injection, or tool-use behavior. Premium full-repository sweeps are never routine validation.

## Decision

Skills implement the table directly and focused fixtures hold the boundaries. Revisit bindings from
observed quality, availability, current official pricing, and operator value. Do not add a policy
engine, receipt, schema, telemetry pipeline, or runtime budget service.

## Dubious decisions

Removing the long-context option can force large tasks to be split even when one large request would be
more convenient. That simplicity and cost tradeoff is intentional for the single-operator 200K-credit
boundary. Revisit only if a concrete required task cannot be decomposed under default context without
losing correctness.
