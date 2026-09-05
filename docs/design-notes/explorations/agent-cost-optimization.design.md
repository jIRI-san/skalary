---
description: Advisory budgets, stable model aliases, context tiers, and delegated instruction size. Load when designing or reviewing multi-agent skill behavior.
globs:
  - plugins/**/skills/**
  - plugins/**/agents/**
  - .github/skills/**
  - .github/agents/**
  - tools/model-allowlist.psd1
  - scripts/skalary/Sync-ModelBindings.ps1
---

# Agent Cost Optimization

Simplicity and useful output outrank additional review voices. These are operator-approved direct
orchestration rules and focused-test expectations, with only a plan-local execution ledger—not a
telemetry service.

## Monthly operating contract

The GitHub AI-credit ceiling is **200,000 credits per month**: **180,000** for planned work and
**20,000** reserved for incidents and month-end completion. Review actual model-level use in GitHub's
AI-usage dashboard each week. Static repository instructions guide spend but cannot enforce an exact
monthly total.

Autopilot records exact CLI-reported target usage in `assets/ai-credits.json`. The Markdown transcript
does not contain billing totals, so the same invocation writes a temporary `--usage-output-file`
sidecar; the launcher folds it into the ledger and deletes it. Records retain model and token-class
breakdowns for later routing decisions. A plan total is stored directly; an epic total is the sum of
its child-plan ledgers. Activity outside Skalary-launched execution is intentionally out of scope.

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

| Tier | Primary alias | Replacement alias | Effort/context | Admitted work |
|---|---|---|---|---|
| Routine | `primary-model-low` | `secondary-model-low` | medium/default | Bounded implementation, extraction, summaries, documentation, straightforward fixes |
| Standard | `primary-model-mid` | `secondary-model-mid` | high/default | Planning, acceptance validation, ordinary CR/DR, complex bounded implementation |
| Deep | `primary-model-high` | `primary-model-mid` | high/default | Cross-subsystem orchestration or diagnosis unresolved after evidence-backed standard work |
| Independent | `secondary-model-high` | `secondary-model-mid` | high/default | One concrete high-risk security, concurrency, destructive, correctness, or architecture pass |

`tools/model-allowlist.psd1` is the canonical alias-to-host map. Skills and operator configuration use
aliases; `Sync-ModelBindings.ps1` materializes concrete identifiers only where a host format requires
them. A fallback replaces an unavailable call; it never adds a panel. High tiers are not routine
fallbacks. Escalation names unresolved evidence or concrete risk.

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

Both `default` and `long_context` remain supported. Every shipped config and workflow selects `default`;
`long_context` is an explicit operator opt-in for a concrete task that cannot be decomposed safely. It
increases token volume and, above published thresholds, doubles fresh-input and cache-write rates for
some models while increasing output rates.

Load current intent, state, and active contracts first. Select older material only through explicit
concepts or canonical IDs and keep no more than three supporting artifacts. Start a fresh session
between research, planning, and implementation when the prior transcript is no longer needed.

Direct repository work is the default. Planning may use one `primary-model-mid` design/requirements validator
when a choice remains unresolved. Routine implementation uses `primary-model-low` plus deterministic evidence.
A selected ordinary review is one `primary-model-mid` call. `primary-model-high` coordinates only cross-subsystem work
or unresolved diagnosis. `secondary-model-high` adds one independent pass only for a concrete high-risk
path.

Delegated prompts state the outcome, closed scope, acceptance evidence, constraints, and response shape.
Reference authoritative files instead of copying them. Narrow before 800 words; do not add an
instruction-summary service.

## Premium evals

Tier-2 waza execution is direct, explicit, and plugin-focused. Use the `primary-model-low` binding for skill
execution. Retain the `primary-model-mid` binding only where behavior is subjective; use deterministic graders
for observable output, refusal, injection, or tool-use behavior. Premium full-repository sweeps are
never routine validation.

## Decision

Skills use aliases directly and focused fixtures hold the boundaries. Repoint aliases from observed
quality, availability, current official pricing, and operator value, then regenerate host-required
bindings. Do not add a policy engine, telemetry pipeline, or runtime budget service.

## Dubious decisions

Generated copies of the alias map exist so independently installed skills can resolve aliases without
repo-root dependencies. `Sync-ModelBindings.ps1 -Check` fails drift; this small duplication is preferred
to a new routing plugin or service.
