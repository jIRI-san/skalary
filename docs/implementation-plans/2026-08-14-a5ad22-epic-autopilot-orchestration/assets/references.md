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
2. The host asks shared plan state for the explicit epic-autopilot selector mode, takes one topologically ready
	 child from a clean target snapshot, and stops on terminal/non-clean or unresolvable dependency states.
3. One child runs at a time in a fresh container against an isolated child branch. The existing
	 `launch.ps1 -PlanSlug <folder> -Mode whole-plan -Runtime container` path remains the child executor,
	 extended to export a bounded Git bundle while withholding repository-write credentials.
4. The host imports and audits the bundle, verifies child completion and evidence, then performs the
	 expected-old-OID branch push and explicit-base PR creation before stopping for operator-approved merge.
5. After merge, the host fetches the target branch and recomputes the epic rollup. It never advances from
	 stale pre-merge state or treats an unmerged completed branch as satisfying a dependency.
6. Repeat until all children are merged and an epic-level intent/coherency crosscheck passes.

## Ownership boundary

**Host owns:** topological epic selection, target/toolchain/graph authority, eligibility gates, durable run
state, child branch and runtime lifecycle, host-mediated remote refs/PRs, terminal verification, graph refresh,
operator-authorized resume, and epic completion.

**Child container owns:** exactly one plan's phases and steps, intent/requirements rechecks, build/test/review,
explicit-file commits, evidence receipt, and existing per-plan finalization behavior up to host handoff. It
receives no remote-write credential and cannot push or create a PR.

**Child container must never:** choose another child, edit host epic-run state, mark an unmerged dependency
complete, merge its own branch, launch another runtime, or continue after a host-level stop condition.

## State and stop contract

- Reuse `669ad3`'s external host authority and total lock order; publish bounded domain-owned state, receipt,
	and append-only transition/attempt/audit indexes using shared stateless JSON/digest/confinement/write helpers.
- Closed orthogonal fields represent run, child, wait, merge, coherency, reason, and process-exit state.
- Exit `42` remains operator wait; `43` rebundle exhaustion; `44` recovery; `45` planned relaunch; phase timeout
	`124`, preserved timeout `143`, and unknown exits have explicit failed reasons.
- Resume requires expected state digest, an allowed action, and changed verified facts. Reset starts a new epoch
	without erasing merge/review history or cumulative budgets.
- Status is verification-only and emits exact allowed actions, prerequisites, progress, and handoff guidance.

## Prior art relationship

- **Extends** the epic rollup from `b0c0d3` REQ-15 with an explicit autopilot selector mode that schedules one
	topologically ready child; existing `NextChild` consumers remain unchanged.
- **Reuses** plan `001`'s isolated host/container execution, branch safety, timeout, auth, and one-plan launch
	contracts rather than creating another runtime.
- **Reuses** `006`'s distinct mid-plan/finalization exit-42 semantics and `aaf29b`'s exit-43 rebundle ownership.
- **Reuses** `1936cb`'s trusted target-branch/OID and expected-head verification principles where merge
	handoff and durable state need authority, without importing `/si`'s domain state machine wholesale.
- **Extends** `7645b1`'s facts-only state scripts: deterministic scripts report epic/child/run facts while
	operator decisions and stop handling remain host-orchestrator judgment.
- **Reuses** `007`'s append-before-branch and escalation ordering; epic orchestration consumes child finalization facts and never invents another child PR sequence.
- **Extends** `25aa23` with owner-state family `epic-delivery@1`, mapped compatibly to review-run v1 `purpose=design` and `designSource.kind=rfc`; delivery reuses complete-attendance, epic-associated storage, and digest-bound verdict authority.
- **Reuses** `79cfe1`'s registry and generated-agent ownership for delivery variants; rejected: a separate hand-maintained `/ci` concern family.
- **Extends** `669ad3`'s canonical-ID, external host authority, namespace protocol, lock ordering, recovery exits 44/45, and bounded relaunch behavior; no mutable plan basename or worktree-local state becomes authority.

The generated index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md` on 2026-08-21. The operator accepted proceeding with that unrelated archived-record limitation; no `cda9da` record is treated as reconciled.

## Dependencies and related children

This child depends directly on `8a0644`, `25aa23`, `669ad3`, and `79cfe1`; `8a0644` transitively depends on
`6a629b`. It consumes the shared agent-fleet declaration/attendance policy, epic review authority, generated
concern ownership, canonical host-run handles, and the vertical requirement loop. Fleet dispatch does not
become a process semaphore: epic child containers retain their own fixed sequential cap of one.

Implementation is blocked until every direct dependency is lifecycle `done`, final-review approved,
typed-evidence clean, and digest-compatible with the interfaces consumed here. Step 1.1 generalizes the
installed dependency gate so later plans cannot bypass that precondition.

## Non-goals for MVP

- Parallel child containers.
- Automatic branch merge or bypass of human/branch-protection gates.
- Letting containers mutate epic orchestration state or select siblings.
- Replacing the existing per-plan launchers, agent, receipts, or package-rebundle loop.
- Executing scaffolded or structurally invalid child plans.
- Squash-only merge proof, automatic merge, host/sandbox epic modes, merge-wait polling, and automatic retry of non-clean child outcomes.
- Importing completed children without reconstructable target ancestry and required receipt proof.
- Live Azure DevOps epic orchestration; first delivery keeps only the provider-neutral seam.

## Design review round 1 (2026-08-21)

The review reported 35 merged findings. The plan was recut into provider-specific vertical slices and now
defines strict target snapshots, clone-wide manifest-last state, write-ahead runtime identity, orthogonal
state transitions, child write/ref capabilities, bounded provider adapters, exact evidence discovery, and a
provisional architecture contract. Operator decisions selected epic-associated review authority,
registry-generated concern variants, one blocking delivery audit, verified baseline import, opt-in Docker
smoke, GitHub plus ADO slices, and 60-second provider/five-minute reconcile limits.

## Design review round 2 (2026-08-21)

The review reported 33 findings, led by a Critical correction to blocked-first selection. The plan now keeps
global `NextChild` stable and adds a topological autopilot selector mode; pins host/reviewer/graph authority;
removes child remote-write credentials; reuses the external host authority and shared publication mechanics;
defines `epic-delivery@1`; composes reset/counters; seals finalization; and supplies numeric provider, Git,
artifact, image-cache, and epic-wide budgets. Operator decisions also added live Windows/Linux support,
verification-only rich Status, scope-change re-authorization, and parallel ADO/delivery implementation.

## Design review round 3 (2026-08-21)

The review reported two Critical and five High findings. The plan now transports commits through bounded
host-imported Git bundles with separate Copilot authentication, generalizes dependency preflight, splits
acceptance into phase-local requirements, maps owner-state `epic-delivery@1` to unchanged review-run v1,
defers live ADO, removes public `Recover`, reserves exit 5 for verified degradation, and limits publication
reuse to stateless helpers. No round-3 issue is deferred.
