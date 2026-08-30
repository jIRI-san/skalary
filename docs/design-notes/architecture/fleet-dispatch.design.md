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
| Execution | `Start-FleetDispatchRun` validates one private snapshot and atomically admits the first ready wave; native hosts settle that wave through `Step-FleetDispatchRun`, which validates one structured result per admitted task and admits the next wave; `Complete-FleetDispatchRun` refuses incomplete state and renders final attendance |
| Callback compatibility | `Invoke-FleetDispatchPlan` is a wrapper over the stepwise core for PowerShell callers; it maps launcher exceptions to bounded, control-sanitized, token-redacted failed outcomes |
| Result | Closed per-attempt outcomes are `completed`, `failed`, or explicit `throttled`; task terminals are `completed`, `failed`, or `cancelled` |
| State | The plan is pure run-local data. It creates no files, locks, leases, scheduler records, or recovery state |

The returned plan is the sole admission source for the orchestration adapter. Callers must not
recompute task selection or waves after rendering the plan. Before rendering, execution reconstructs
the canonical projection from `Tasks` and compares the schema, cap, provider note, retry policy,
selected/omitted ids, wave task membership, ready order, and empty attendance. Any mismatch fails
before admission.

The stepwise protocol is the native-agent boundary: Start returns the pre-view plus an already
admitted cloned wave, Step requires exactly one result for each admitted id before it admits anything
else, and Complete rejects pending or admitted work. A native timeout, crash, or missing result is
submitted as an explicit failed outcome rather than restarting the run and duplicating a lease.
Retry waves contain only explicitly throttled tasks and run before newly ready work. The caller-held
run is invocation-local state mutated in place by Start/Step and never persisted by the module. It
has no integrity digest or admission token and is not an authentication, attestation, or tamper-proof
mechanism. Internally inconsistent edits fail loud; a caller that coherently rewrites its own state
is fabricating attendance only about its own invocation, not crossing a privilege boundary.

`/cip` creates its fleet only after operator intent confirmation. Its ordered descriptors admit
Designer and Requirements Validator together, then Judge after both complete. Descriptor keys carry
the role/model bindings already resolved by the caller; the adapter does not change role prompts,
tools, model selection, operator checkpoints, script-owned plan mutations, Capture writes, or the DR
handoff. The complete plan view precedes every role call, and the final attendance is recorded through
the existing Capture writer. Judge is cancelled when either prerequisite fails, while an explicit
throttle result permits only the module-owned single retry.

`/ci` and autopilot use the same four-role graph per active implementation step: Designer and
Validator are initially ready, Implementor depends on both, and Judge depends on Implementor.
In-session `/ci` creates the fleet only after phase admission and worktree setup; autonomous `/ci`
hands off without creating a duplicate because the launched autopilot agent owns it. Implementor
retains the existing edit/build/test/format/design-note/fix loop, Judge retains acceptance judgment,
and commit, push, promotion, phase review, and harvest remain outside dispatch. Failed runs leave the
step in progress for a new invocation-local plan rather than issuing undeclared replacement calls.

`/cr` and `/dr` create Fleet descriptors only after review-run Freeze succeeds. Every frozen task is
selected in canonical frozen order, with its exact `taskId` as Fleet `Id`, frozen model as `Key`, and
no dependencies. The adapter calls New and Start once, renders Start's pre-view before reviewer
calls, submits exactly one structured projection for each task in each returned already-admitted
wave, and calls Complete only after Done before rendering the final view. A six-task fixture projects
to `4,2`; a fourteen-task fixture projects to `4,4,4,2`, but filters and profiles may freeze any
valid count. Each review skill imports only its fixed installed `scripts/FleetDispatch.psm1` sibling;
repository-root replacements are outside the review execution boundary.

Only an explicit structured throttle projection retries, once, as the same frozen task. Review
failures, timeouts, omissions, and host cancellations project to Fleet failure, while their richer
review outcomes remain in memory for publication. Error prose such as `HTTP 429` is an ordinary
failure. Fleet attendance is not added to review schemas or persistence: review-run Publish,
verified Summary/Full reading, and result rendering remain authoritative after Fleet completion.

The `/cep` decomposition guide also publishes an explicitly inactive epic-review extension boundary
for plan `25aa23 epic-coherency-review`. It projects any later frozen epic-review tasks through the same exact-id/order/model,
dependency-free descriptor and stepwise lifecycle contract, but creates no current `/cep` activation,
scheduler, state, or plugin dependency. The dependent plan retains ownership of its fixed review
scope, selection, rubric, richer findings and outcomes, compact verdict, operator blocking, and
activation timing; review-run Freeze/Publish and verified readers remain authoritative.

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

Each admitted wave contains at most four cloned ready descriptors, their ids, and an attempt number.
The native host may launch them concurrently or serially through its existing tool boundary, but
must submit exactly one `{ TaskId, Outcome, Detail }` record for every admitted task. Unknown,
duplicate, missing, or non-closed outcomes fail loud rather than producing success-shaped
attendance. `failed` and `throttled` outcomes require a non-empty diagnostic. The compatibility
callback scopes a launcher exception to that admitted wave and submits an explicit failed outcome
for each wave task, preserving bounded sanitized failure context and degraded attendance.

All caller-controlled display fields must be actual strings and are bounded to one line. Values are
never accepted through implicit object-to-string conversion. Control characters, Unicode
format/bidirectional controls, and line/paragraph separators are rejected; free text is JSON-quoted
before rendering. Result details use the same boundary, preventing task labels or host diagnostics
from injecting terminal control sequences or new attendance records. A plan contains at most 64
tasks and each task at most 64 dependencies, bounding projection work and rendered output.
Post-run formatting is reachable only through `Complete-FleetDispatchRun`, which revalidates closed
task-state values, admitted-wave coherence, and started/attempt conservation before rendering.

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
