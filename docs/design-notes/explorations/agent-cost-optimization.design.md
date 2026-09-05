---
description: Advisory budgets for agent dispatch, model fallback, historical context, and delegated instruction size. Load when designing or reviewing multi-agent skill behavior.
globs:
  - plugins/**/skills/**
  - plugins/**/agents/**
  - .github/skills/**
  - .github/agents/**
---

# Agent Cost Optimization

Simplicity and useful output outrank additional review voices. These are operator-approved targets
for the later review/autopilot simplification child `367e9a`, not claims that the current CR/DR
dispatch already complies. They remain advisory and add no runtime gate.

## Advisory budgets

| Area | Default | Maximum | Escalate only when |
|---|---:|---:|---|
| Agent calls per task or plan step | **2 default** | **5 maximum** | Independent concerns need separate context or the first result identifies a concrete unresolved risk |
| Models per role | One primary model | Primary plus one availability fallback | The primary is unavailable; disagreement is not a reason to add a model panel |
| Supporting historical artifacts | Current plan or epic, plus directly relevant context | At most **5 supporting artifacts** | Each artifact matches an explicit concept, plan ID, dependency, or operator choice |
| Delegated task instructions | **600-word target** | **1,200-word cap** | A bounded specialist task cannot be made unambiguous by references to repository files |

Built-in file, search, and command tools are not agent calls. A retry consumes another call. Continue
with an already-open agent when the follow-up needs its context instead of dispatching a replacement.

## Dispatch shape

Direct repository work is the default. Use an agent only when a specialist is required or when an
independent investigation needs enough context to justify a separate window. A normal reviewed step
fits two calls: one combined design/validation pass and one final judge. Add implementor or specialist
calls only for concrete risk, not role attendance.

Use the configured primary model for a role. An availability fallback replaces it; it does not run in
parallel. Multi-model panels, duplicated review passes, and agents that merely repeat repository
searches are outside the default.

The current CR/DR dispatch is a known transitional exception: post-phase review still fans out by
concern, and plan finalization still adds a second model. Child `367e9a` owns reducing that existing
orchestration. New work must not copy or expand it.

## Context selection

Load current intent, state, and active contracts first. Select older material through the bounded
historical adapter using explicit concepts or canonical IDs, then keep no more than five supporting
artifacts. Prefer the smallest excerpts that preserve the decision. Do not preload sibling plans,
entire archives, or every design note.

## Instruction form

Delegated prompts state the outcome, closed scope, acceptance evidence, constraints, and expected
response shape. Reference authoritative files instead of copying them. Remove duplicated repository
rules already available to the role. If a prompt exceeds 1,200 words, narrow the task or split a
genuinely independent concern; do not create an instruction-summary service.

## Decision

The budgets remain advisory. Skills explain justified exceptions in normal prose when cost materially
exceeds them. No policy engine, receipt, schema, telemetry pipeline, or runtime budget service is
added. Revisit the numbers only from observed operator value and cost.
