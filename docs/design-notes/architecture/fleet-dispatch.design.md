---
description: Run-scoped fleet planning, deterministic task waves, pre-dispatch declarations, and attendance adapters used by orchestrated skills.
globs:
  - scripts/skalary/FleetDispatch.psm1
  - tests/skalary/FleetDispatch.Tests.ps1
  - plugins/*/skills/**
---

# Fleet Dispatch

## Architecture

`scripts/skalary/FleetDispatch.psm1` is the canonical source for one invocation-local dispatch
contract. `New-FleetDispatchPlan` normalizes an ordered descriptor list and returns selected and
omitted tasks, projected waves, stable ready order, retry policy, and empty attendance.

| Boundary | Contract |
|---|---|
| Descriptor | Lowercase stable `Id`, one-line `Label` and caller-owned `Key`, explicit Boolean `Selected`, explicit reason when omitted, ordered `DependsOn` ids |
| Validation | Reject duplicates, malformed or unknown ids, duplicate/self dependencies, cycles, and selected tasks whose prerequisite is omitted |
| Projection | Stable caller order; each wave admits at most four tasks whose selected prerequisites are in earlier waves |
| Rendering | `Format-FleetDispatchPlan` prints all selected and omitted tasks, cap, waves, ready order, retry policy, and that provider-global concurrency is unobserved |
| State | The plan is pure run-local data. It creates no files, locks, leases, scheduler records, or recovery state |

The returned plan is the sole admission source for the orchestration adapter. Callers must not
recompute task selection or waves after rendering the plan.

## Design Decisions

The helper is canonical under `scripts/skalary/` because multiple independently installed plugins
consume it. Distribution uses the existing `Sync-PluginScripts.ps1` managed-copy path; plugins do
not depend on a common runtime installation.

Projected waves use stable Kahn ordering with a fixed cap of four. This describes orchestrator
admission inside one workflow run, not actual host execution overlap or provider-global
concurrency.

Omissions are input, not inferred output. A caller must name every omitted task and reason before
dispatch, and must also omit a task whose prerequisite is omitted. Runtime prerequisite failures
are different: the adapter records cancellation of only transitive selected dependents.

The retry policy is declared in the plan but enforced by the adapter: one retry is permitted only
for an explicit structured throttle outcome. Error text and timing never imply throttling.
