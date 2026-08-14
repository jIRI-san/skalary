# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

Allow one host-side orchestrator to implement a whole epic by selecting active child plans and invoking a
separate container autopilot for each plan. Keep epic orchestration on the host; each container remains a
single-plan executor.

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 11-13: the operator proposed driving a whole epic through separate child container-autopilot runs and accepted extending `/ci` with host-owned orchestration.
- Epic `bcece1` Epic autopilot section records the sequential MVP, state machine, ownership boundary, merge gate, and deferred parallelism.

## Agreed MVP

1. `/ci <epic-id>` offers a whole-epic autonomous mode in addition to existing single-plan modes.
2. The host reads `Get-PlanState <epic> -Json`, takes only its deterministic `NextChild`, and launches only
	 children at `drafted` or later whose dependencies are complete on the merged target branch.
3. One child runs at a time in a fresh container against an isolated child branch. The existing
	 `launch.ps1 -PlanSlug <folder> -Mode whole-plan -Runtime container` path remains the child executor.
4. The host verifies child completion, evidence/receipt state, pushed remote head, and clean termination.
	 It then stops for operator-approved merge rather than merging autonomously.
5. After merge, the host fetches the target branch and recomputes the epic rollup. It never advances from
	 stale pre-merge state or treats an unmerged completed branch as satisfying a dependency.
6. Repeat until all children are merged and an epic-level intent/coherency crosscheck passes.

## Ownership boundary

**Host owns:** epic selection, target-branch authority, eligibility gates, durable run state, child branch and
runtime lifecycle, terminal-state verification, merge handoff, graph refresh, retries, and epic completion.

**Child container owns:** exactly one plan's phases and steps, intent/requirements rechecks, build/test/review,
explicit-file commits, evidence receipt, branch push, and existing per-plan finalization behavior.

**Child container must never:** choose another child, edit host epic-run state, mark an unmerged dependency
complete, merge its own branch, launch another runtime, or continue after a host-level stop condition.

## State and stop contract

- Persist host-local, gitignored, schema-validated state sufficient to resume after process or editor restart:
	epic ID, target/base OID, selected child, child branch, runtime/run ID, last verified child OID, retry count,
	timestamps, and terminal outcome.
- Closed outcomes include `running`, `completed`, `blocked`, `failed`, `degraded`, `awaiting-human`, and
	`merge-conflict`; unknown or malformed state fails loud.
- Exit `42` remains `@human`/finalization escalation. Exit `43` remains child-local offline rebundling.
- A failed, degraded, conflicting, or human-blocked child pauses the epic. Never skip silently to later work.
- Resume reconciles persisted state against live container/process, remote branch, target OID, child plan
	state, and epic membership before taking action.

## Prior art relationship

- **Reuses** the epic rollup and `NextChild` selection from `b0c0d3` REQ-15 and `Get-EpicRollup`; the new
	orchestrator never implements a second dependency selector.
- **Reuses** plan `001`'s isolated host/container execution, branch safety, timeout, auth, and one-plan launch
	contracts rather than creating another runtime.
- **Reuses** `006`'s distinct mid-plan/finalization exit-42 semantics and `aaf29b`'s exit-43 rebundle ownership.
- **Reuses** `1936cb`'s trusted target-branch/OID and expected-head verification principles where merge
	handoff and durable state need authority, without importing `/si`'s domain state machine wholesale.
- **Extends** `7645b1`'s facts-only state scripts: deterministic scripts report epic/child/run facts while
	operator decisions and stop handling remain host-orchestrator judgment.

## Dependencies and related children

This child depends directly on `8a0644`, which transitively depends on `6a629b`. It consumes the shared fleet
admission/throttling policy and the vertical requirement loop. `669ad3` must ensure launcher plan resolution
survives epic-prefixed folder names before implementation reaches this child through the dependency chain.

## Non-goals for MVP

- Parallel child containers.
- Automatic branch merge or bypass of human/branch-protection gates.
- Letting containers mutate epic orchestration state or select siblings.
- Replacing the existing per-plan launchers, agent, receipts, or package-rebundle loop.
- Executing scaffolded or structurally invalid child plans.
