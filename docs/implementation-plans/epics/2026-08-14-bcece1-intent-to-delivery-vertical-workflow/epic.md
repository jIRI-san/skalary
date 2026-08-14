# bcece1: Intent-to-delivery vertical workflow
<!-- epic-id: bcece1 -->
<!-- Folder naming: epics/<yyyy-mm-dd>-<6hex>-<slug> · epic-id is the canonical handle. New-Epic.ps1 fills these in. -->

## Goal

Make `/cip`, `/cep`, and `/ci` produce and execute complete, operator-aligned implementation plans whose
phases are demonstrable vertical slices, with high-level program design agreed before costly implementation.

**Desired outcome.** `/cip` still plans the whole implementation needed to reach the operator's desired
outcome. It organizes that work so the first phase delivers an end-to-end MVP, each later phase adds a
usable vertical increment, and the final phase completes the implementation. The workflow also elicits
end-user experience and MVP boundaries; approves concise Mermaid-backed code shape and optional call stacks;
records agent decisions and uncertainty; repeatedly checks requirements during execution; coordinates
specialized agents through bounded fleets; applies the same provider-aware orchestration contract to `/cr`
and `/dr`; makes `/cep` run an epic coherency review before finalizing a decomposition; and synchronizes
epic/feature/work item hierarchies to GitHub first through an Azure DevOps-extensible model. Planning and
review also reuse relevant assets and artifacts from related active and archived plans through bounded,
index-driven context selection. Plan folders sort by epic through an `<epic-id|standalone>` prefix while
stable plan IDs remain unchanged. A host-side epic autopilot can drive eligible child plans through separate
container-autopilot runs while preserving plan isolation and merge gates. Architecture tests are retired
while human-reviewed architecture notes and ADRs remain.

**Success signals.**

- Early phases produce usable end-to-end behavior the operator can inspect and redirect.
- Every `/cip` output covers the complete desired implementation, not only its MVP slice.
- Successive vertical phases build on the MVP until the final phase fulfills the complete requirement set.
- Approved design assets make program structure and important call flows unambiguous before implementation.
- `/ci` proves each applicable requirement and the confirmed intent remain fulfilled at slice checkpoints.
- Independent agent decisions and uncertainty are reviewable; high-impact uncertain decisions block for approval.
- Existing or new work can populate a GitHub Projects v2 and issue hierarchy with goals, purpose, and acceptance criteria.
- Designer, requirements-validator, judge, implementor, and reviewer roles improve throughput without concurrent writers sharing a scope.
- No orchestrated fleet launches more than four agent invocations at once; `/cr` and `/dr` use that same cap, and larger selected fleets run in declared waves without dropping independent coverage.
- `/cep` surfaces an independent coherency verdict on goal coverage, verticality, child ownership, overlap, and dependencies before it finalizes an epic cut.
- `/cip`, `/cep`, `/dr`, and plan-associated `/cr` can identify related plans and selectively reuse relevant intent, design, review, evidence, and learning artifacts with recorded provenance.
- Hash-schema plan folders use `<epic-id>-<date>-<plan-id>-<slug>` or `standalone-<date>-<plan-id>-<slug>`, and existing hash-schema plans migrate without changing canonical IDs.
- `/ci <epic-id>` can run a host-owned sequential whole-epic mode that launches one fresh child container at a time, resumes durably, and recomputes the graph after each approved merge.

**Non-goals.**

- Live Azure DevOps integration in the first delivery; only a provider-neutral contract and extension seam are required.
- Replacing deterministic validators with agent judgment.
- Reopening the existing seven-concern review taxonomy.
- Preserving the architecture-tests plugin, runner, receipts, or `arch:` evidence marker.
- Building horizontal layers that cannot be demonstrated and reviewed independently.
- Reducing `/cip` to an MVP-only or partial implementation plan.

**Definition of done.** A real, complete implementation plan can move from operator interview through
MVP-first vertical phases, approved program shape, specialized-agent implementation and review, requirement
crosschecks, decision review, and GitHub hierarchy tracking. Each phase leaves useful output for operator
feedback, and completing the final phase delivers the plan's full desired outcome.

## Child plans

<!-- child-plans:start -->
| Plan | Slug | Depends on |
|---|---|---|
| `57cc2c` | intent-capture-and-rfc | `4dd933` |
| `8a0644` | dispatch-plan-up-front | `57cc2c`, `6a629b` |
| `25aa23` | epic-coherency-review | `8a0644` |
| `4dd933` | cross-plan-artifact-context | `669ad3` |
| `669ad3` | epic-prefixed-plan-folder-naming | — |
| `6a629b` | vertical-implementation-requirement-loop | `57cc2c` |
| `9fda0b` | github-work-hierarchy-synchronization | `57cc2c` |
| `a5ad22` | epic-autopilot-orchestration | `8a0644` |
| `cda9da` | architecture-test-retirement | — |
<!-- child-plans:end -->

Membership is the `<!-- epic: bcece1 -->` marker in each child `plan.md`; the table above is a generated
mirror that `New-Epic.ps1` rewrites. Run `Get-PlanState bcece1` for live rollup and the next unblocked
child plan.

## Decomposition notes

**Plan completeness versus phase shape.** Vertical slicing changes how a complete plan is organized, not
what `/cip` ultimately plans. The plan captures all work needed for the desired outcome. Its first phase
contains the cross-layer steps needed to deliver an end-to-end MVP; later phases extend that working result
with additional end-to-end behavior; the final phase completes the implementation. A phase may contain
multiple steps across schemas, scripts, skills, agents, tests, and documentation when those steps together
produce one inspectable increment. Layer-only phases such as "all schemas" or "all agents" are rejected.

**MVP checkpoint.** The first usable increment is a complete plan organized into vertical phases: end-user
experience and minimum viable behavior are elicited, a concise Mermaid program design is approved, call
stacks are reviewed when they clarify control flow, decisions and uncertainty are recorded, and the full
sequence from MVP phase to completed implementation is explicit. Execution orchestration builds on that
accepted artifact instead of delaying feedback until every workflow layer exists.

**Seam chosen: operator-visible workflow capability.** Each child leaves one independently usable behavior:
planning a slice, executing and rechecking it, coordinating specialized agents, synchronizing work hierarchy,
or removing an unused enforcement subsystem. Schema, agent-definition, and transport work remain inside the
child whose behavior they enable; none is a layer-only child.

**Accepted cut.**

| Child | Slice delivered | Depends on |
|---|---|---|
| `669ad3` | Epic-prefixed and standalone plan-folder naming plus hash-schema migration | — |
| `4dd933` | Bounded cross-plan artifact context for planning and review | plan-folder naming |
| `57cc2c` | Complete operator-aligned plan organized as MVP-first vertical phases | cross-plan artifact context |
| `6a629b` | Vertical implementation and requirement loop | `57cc2c` |
| `8a0644` | Bounded specialized-agent and `/cr`/`/dr` review orchestration | planning MVP and implementation loop |
| `25aa23` | `/cep` epic coherency review | shared fleet orchestration |
| `a5ad22` | Host-orchestrated sequential container autopilot for a whole epic | shared fleet orchestration |
| `9fda0b` | GitHub work hierarchy synchronization | `57cc2c` |
| `cda9da` | Architecture-test retirement | — |

**Prior art reconciled.** *Supersedes* `7645b1` REQ-2 and its `<date>-<hash>-<slug>` naming decision with
the epic/standalone-prefixed hash schema, plus its "no renames" decision only for hash-schema folders that
the migration owns. *Reuses* `7645b1` REQ-1, REQ-3, REQ-12, and canonical-id decisions: random 6-hex IDs,
hash/slug/date resolution, ledger compatibility, and stable `plan-id` anchors do not change. Legacy
`NNN-<slug>` plans remain in place. *Extends* `b0c0d3` REQ-4 (intent capture), REQ-9 (model-agnostic agent fanout),
REQ-15 (epic indexing), and REQ-6 (the active-and-archived REQ/RISK/decision index) with selective artifact
discovery rather than a second plan-corpus scan. *Reuses* `1936cb` REQ-4 and its phase-crosscheck promotion decision without
absorbing that substantive plan. *Supersedes* `21f21d` REQ-8 through REQ-11, REQ-14, and REQ-17 only where
they require the architecture-tests plugin, runner, receipts, adapters, or `arch:` marker; its architecture-
notes tier and two-index decision remain. This retirement is supported by `768d7b` decision D11, which found
`arch:` unsatisfiable for a real plan. Placeholder child plans `57cc2c` and `8a0644` are re-parented from
`33b1f9`; they contain no settled requirement or decision to preserve.

**Old-epic boundary.** `c21cdc` (review report as data), `ca8ba8` (review corroboration truth), `863d97`
(evidence and receipt truth), `79cfe1` (concern registry and generated agents), and `34088e` (consumer install
correctness) remain in `33b1f9`. They harden artifact contracts or distribution and are not silently folded
into this epic's operator-facing workflow goal.

**Initial execution policy.** Parallelize Designer, Requirements Validator, Judge, Implementor, and reviewer
roles through one shared fleet scheduler. This is not a review-only throttle: `/cip` and `/ci` orchestration,
`/dr`, and `/cr` use the same admission, wave, attendance, and provider-throttling contract, and `/dr` plus
`/cr` adopt it in the same delivery rather than growing separate implementations. At most **four agent
invocations** may be in flight in one orchestrated fleet. A normal 14-invocation review therefore runs in
four declared waves; mixed-role planning and implementation fleets obey the same bound.

The cap limits simultaneous provider load, not coverage: selected concern/model pairs still run independently
once, reading batches still do not multiply concern passes, and no concern is silently dropped to satisfy the
concurrency limit. The up-front dispatch plan states selected agents and roles, total invocations, concurrency
cap, wave order, and omissions before calls begin. Provider throttling pauses admission of later waves and
retries through a bounded, reported policy rather than launching replacement calls or silently accepting
partial attendance.

**Plan-folder grouping.** New hash-schema plans use `<group>-<yyyy-mm-dd>-<plan-id>-<slug>`, where `group`
is the canonical six-hex epic ID or the literal `standalone`. `/cep` passes the epic identity when it
scaffolds children so no temporary standalone name is created. Attaching a standalone plan to an epic or
re-parenting between epics updates the membership marker and folder prefix in one script-owned operation,
then refreshes affected epic mirrors. A dedicated migration supports `-WhatIf`, collision preflight, and
idempotent active-plus-archived migration of folders matching the current hash schema only. It never renames
legacy `NNN-<slug>` folders, mutates `plan-id`, rewrites canonical `depends-on`/ledger IDs, or treats the
folder prefix as identity. All inventory, resolution, archival, worktree, test, documentation, and bundled-
script consumers accept both pre-migration and target hash folder grammars during rollout.

**Cross-plan artifact context.** `Get-PlanIndex.ps1` remains the first-stage discovery surface and the plan
corpus is never loaded wholesale. A bounded resolver takes related plan IDs from indexed topic matches,
explicit epic membership/dependencies, or operator selection; inventories a closed set of artifact kinds;
and lets `/cip`, `/cep`, `/dr`, and plan-associated `/cr` load only artifacts relevant to the current concern.
Candidate kinds include intent, references, decision records, RFC/Mermaid and call-stack designs, evolution
logs, review reports, evidence receipts, capture/learnings, and other explicitly registered plan artifacts.
Every consumed artifact is treated as untrusted historical input, path-confined to the inventoried plan,
size-bounded, and recorded by plan ID, kind, path, and relationship in the current plan's references or review
scope. Missing, stale, or conflicting artifacts are surfaced rather than silently treated as authority.

**Epic autopilot.** `/ci <epic-id>` gains a whole-epic autonomous mode whose control plane stays on the
host. The host repeatedly reads the deterministic epic rollup, selects `NextChild`, requires that child to
be drafted and structurally valid, creates or resumes its isolated branch/worktree state, and invokes the
existing container autopilot for that child only. A container may implement, validate, review, commit, push,
and produce evidence for its assigned plan; it may not select siblings, mutate epic run state, or launch
another container. The host validates the terminal receipt and remote head, stops for operator-approved
merge, then recomputes dependencies from the merged target branch before selecting another child.

The MVP is sequential whole-child execution: one fresh container and one child branch at a time. Durable
host state records epic ID, target branch, selected child, child branch, runtime/run identity, last verified
commit, retry count, and outcome from a closed set including `running`, `completed`, `blocked`, `failed`,
`degraded`, `awaiting-human`, and `merge-conflict`. Exit `42` remains the human-stop contract and exit `43`
remains the offline-rebundle contract inside one child run. A child failure or degraded receipt pauses the
epic instead of silently skipping to unrelated work. Whole-epic completion requires an epic-intent
crosscheck after every child is merged; child checkboxes alone are insufficient.

Parallel child containers are a later extension, not MVP. They may be considered only for dependency-free,
non-overlapping write scopes and must share the fleet/provider admission cap from `8a0644`; separate
containers never imply unlimited concurrent LLM calls.

**Epic coherency review.** After the operator accepts a proposed cut, `/cep` runs a focused review through
the shared bounded fleet before treating the decomposition as final. The review checks that the epic goal
and definition of done are covered by the children; children are vertical, independently executable, and
non-overlapping; cross-child contracts have one owner; dependencies are necessary and acyclic; MVP and final
outcome are both represented; and prior plans or epics are reused, extended, or superseded explicitly.
Findings are surfaced to the operator. Clear defects revise the cut; decision-changing findings return for
operator confirmation. Detailed implementation, per-child acceptance evidence, and code structure remain
the responsibility of each child's `/cip` and `/dr` flow.

Keep each write scope under one implementor. Only uncertain decisions affecting contracts, end-user
experience, security, or irreversible structure block for operator approval; other decisions are recorded
and reviewed at the slice checkpoint.
