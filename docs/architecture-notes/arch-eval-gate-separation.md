---
description: Architecture note for Two-tier eval gate separation — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "scripts/skalary/{Test-Evals,Invoke-WazaEvals}.ps1"
---

# Two-tier eval gate separation — Architecture Note

## Boundary

Deterministic Tier-1 structural evals (Pester) are always-on; Tier-2 LLM (waza) evals are
**never** part of the deterministic gate. The always-on gate stays offline, deterministic, and
zero-cost; the premium, auth-dependent LLM tier is strictly opt-in.

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Eval-Gate-Separation` | provisional | No waza/LLM run may enter `npm test` / `validate.ps1` / `npm run eval`; Tier-2 is `eval:llm` only |

## Invariants

- `npm test`, `scripts/validate.ps1`, and `npm run eval` never invoke a waza/LLM run.
- Tier-1 runs as a blocking per-platform CI step via `Test-Evals.ps1` (structural Pester only), with
  exact required-case execution checked from `tools/structural-eval-required.json`; Tier-2 runs via `Invoke-WazaEvals.ps1`
  (`npm run eval:llm`), which requires auth and incurs premium cost.
- A Tier-2 run that executed zero evals is a distinct non-green outcome, not a silent pass.

## Depends On / Depended On By

- Depends on: `Test-Evals.ps1` (Tier-1), `Invoke-WazaEvals.ps1` (Tier-2), `Resolve-EvalToken.ps1` (auth).
- Depended on by: the CI gate; every plugin's `evals/` (Tier-1 `*.Tests.ps1` + Tier-2 `waza/`).
