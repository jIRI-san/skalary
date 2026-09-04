---
description: Architecture note for Two-tier eval gate separation — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "scripts/skalary/{Test-Evals,Invoke-WazaEvals}.ps1"
---

# Two-tier eval gate separation — Architecture Note

## Boundary

Deterministic Tier-1 structural evals (Pester) are direct and plugin-focused; Tier-2 LLM (waza)
evals are **never** part of deterministic validation. The deterministic route stays offline and
zero-cost; the premium, auth-dependent LLM route is direct, explicit, and plugin-only.

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Eval-Gate-Separation` | provisional | No waza/LLM run may enter configured build/test or deterministic scripts; Tier-2 requires direct `Invoke-WazaEvals.ps1 -Plugin` |

## Invariants

- Configured build/test and deterministic scripts never invoke a waza/LLM run.
- Tier-1 routine use requires `Test-Evals.ps1 -Plugin`; selected mode runs only that plugin.
  `-FullRepository` is the direct operator route and checks exact required-case execution from
  `tools/structural-eval-required.json`.
- Tier-2 requires direct `Invoke-WazaEvals.ps1 -Plugin`, validates scope before provisioning or
  output, requires auth, and incurs premium cost.
- A Tier-2 run that executed zero evals is a distinct non-green outcome, not a silent pass.

## Depends On / Depended On By

- Depends on: `Test-Evals.ps1` (Tier-1), `Invoke-WazaEvals.ps1` (Tier-2), `Resolve-EvalToken.ps1` (auth).
- Depended on by: direct local operator invocations and every plugin's `evals/`
  (Tier-1 `*.Tests.ps1` + Tier-2 `waza/`); no hosted workflow depends on either route.
