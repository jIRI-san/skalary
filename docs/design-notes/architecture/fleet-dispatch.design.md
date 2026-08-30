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
| Execution | `Invoke-FleetDispatchPlan` rebuilds and validates one private snapshot, renders it first, passes only cloned descriptors in the next ready `{ Tasks, TaskIds, Attempt }` wave to a caller-owned launcher, validates one structured result per admitted task, and renders final attendance |
| Result | Closed per-attempt outcomes are `completed`, `failed`, or explicit `throttled`; task terminals are `completed`, `failed`, or `cancelled` |
| State | The plan is pure run-local data. It creates no files, locks, leases, scheduler records, or recovery state |

The returned plan is the sole admission source for the orchestration adapter. Callers must not
recompute task selection or waves after rendering the plan. Before rendering, execution reconstructs
the canonical projection from `Tasks` and compares the schema, cap, provider note, retry policy,
selected/omitted ids, wave task membership, ready order, and empty attendance. Any mismatch fails
before the first callback. Rendering and dispatch then use the private reconstruction, so callbacks
cannot mutate the declared plan through caller-held references.

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

The retry trigger, maximum, and description have one module-owned definition copied into each plan.
Rendering and execution consume that validated plan policy: one retry is permitted only for an
explicit structured throttle outcome. Error text and timing never imply throttling.

The caller-owned `InvokeWave` callback receives one wave object containing at most four ready
descriptors, their ids, and an attempt number. It may launch them concurrently or serially according
to its existing host boundary, but must return exactly one `{ TaskId, Outcome, Detail }` record for
every admitted task. Unknown, duplicate, missing, or non-closed outcomes fail loud rather than
producing success-shaped attendance. `failed` and `throttled` outcomes require a non-empty diagnostic.
A launcher exception is scoped to that admitted wave and becomes an explicit failed outcome for each
wave task, preserving degraded final attendance instead of discarding the run result.

All caller-controlled display fields must be actual strings and are bounded to one line. Values are
never accepted through implicit object-to-string conversion. Control characters, Unicode
format/bidirectional controls, and line/paragraph separators are rejected; free text is JSON-quoted
before rendering. Result details use the same boundary, preventing task labels or host diagnostics
from injecting terminal control sequences or new attendance records. A plan contains at most 64
tasks and each task at most 64 dependencies, bounding projection work and rendered output.
Post-run formatting stays internal to `Invoke-FleetDispatchPlan`; callers cannot pass fabricated
attendance to a public formatter.

Collection admission is streaming and bounded before normalization for task descriptors, plan
projections, dependencies, waves, and launcher results. A launcher pipeline is stopped on its first
result beyond the admitted wave cardinality. Execution formats its already validated snapshot
directly rather than reconstructing it through the public formatter.

An ordinary failure becomes terminal immediately. The adapter cancels only still-pending transitive
dependents, continues unrelated ready work, and never retries based on status-code prose. Launcher
exceptions become failed wave outcomes; locally generated result-cardinality violations are
distinguished by private object identity rather than caller-controlled exception metadata. An
explicit throttle outcome admits the same task once more before later work; a second throttle is
terminal. Attendance conserves every selected task across completed, failed, and cancelled states
while reporting started and retried counts separately.
