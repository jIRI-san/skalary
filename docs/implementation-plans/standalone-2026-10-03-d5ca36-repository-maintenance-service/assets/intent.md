# Intent

## Original operator statements

Captured from this session on 2026-10-03; quotations preserve the operator's wording.

> the skill will be called /rcs (repository cleanup service)

> it will check for the implementation plans, their states and propose to archive ones which are implemented.

> the overal goal of the skill should be to keep the repository qualityh high and monitor for drift in intent, archtiecture, design and coding standards.

> we want to have in this skill dead code detection and proposals to remove code which is not reachable, not called from anywhere or otherwise dead. same fix/wontfix rules as for other parts

> we want the overal design/architecture improvements suggestions for the codebase to be included in proposed actions.

## Goal

Keep repository quality high through an operator-controlled repository maintenance audit that detects
drift from human intent, architectural contracts, design decisions, and coding standards, and proposes
concrete improvements and removal of dead code.

## Desired outcome

An independently installable `repository-maintenance` plugin exposes `/rcs`. Each invocation inventories
plans and repository subsystems, performs a structural survey, then investigates risk-selected
candidates against current implementation. It reports requirements alignment, codebase-wide
architecture/design opportunities, coding-standard drift, and dead-code candidates with evidence,
counter-evidence, uncertainty, and actionable recommendations.

One `docs/repository-maintenance.md` record preserves findings and operator dispositions across runs.
The operator chooses accepted intentional drift, "won't fix," or corrective planning through existing
flows. Completed plans/epics receive separate archival proposals under existing completion contracts.
No code change or archival follows merely from discovering a finding.

## Success signals

- A run identifies its source snapshot, plan/subsystem inventory, selected deep traces, and unread,
  skipped, or blocked areas; no unexamined area is presented as clean.
- Each actionable candidate cites the expectation or improvement rationale, current code location,
  trigger/reachability evidence, impact, smallest useful action, effort, and complexity.
- Dead-code advice distinguishes proven unreachable code from exports, manual tools, indirect dispatch,
  and uncertain external usage; overall design/architecture proposals appear in the same action list.
- Repeated runs preserve scoped operator decisions without asking again unless evidence, scope, or
  stated assumptions change. Existing corrective plans are surfaced before duplicate creation.
- A chosen corrective action produces or updates a normal implementation plan, not an immediate fix;
  accepted drift does not erase original intent or bypass contracts/reconfirmation.

## Non-goals

- A proof of whole-repository correctness, exhaustive tracing of every requirement on every invocation,
  a numeric quality score, unattended scheduler, or continuous background monitor.
- Direct code fixes/deletion, arbitrary file cleanup, dependency upgrades, or a standalone dependency/
  security audit. Concrete risks discovered during normal review remain reportable.
- A full documentation/link crawl. Stale/contradictory guidance encountered in normal traces remains
  reportable; a full local docs/reference sweep is a separate operator-requested task.
- A new requirements authority, registry, database, ticket lifecycle, receipt, general policy engine,
  or automatic rewriting of plan criteria to fit code.
- Automatic commits, pushes, PRs, broad suites, premium trials, or external network crawl.

## Definition of done

The installed plugin delivers the complete survey/report/decision/handoff workflow with confined,
secret-screened central-record writes, focused deterministic coverage and disposable scenario evidence,
consumer distribution closure, and updated operator/design documentation. Current implementation quality
is assessed with explicit limits rather than claimed from historical reports or structural tests alone.

## Confirmed interpretation and discretion

The operator confirmed the updated scope and design on 2026-10-03. Selected names are
`repository-maintenance` and `docs/repository-maintenance.md`; `/rcs` retains its original expansion.
Default depth is repository-wide survey plus risk-selected traces. Duplicate-plan checks and
conditional revisits are included; the full docs/reference sweep is excluded from v1.

The implementer may choose small helper/file boundaries and reuse existing confinement/secret guards.
It may not widen audit scope, remove approval gates, infer intent for legacy plans, add a lifecycle,
or treat optional improvement preferences as demonstrated defects. After the mandatory two-pass
planning review and all seven operator-selected edits, the operator confirmed intent, requirements,
risks and decisions together and authorized the plan-only baseline commit on 2026-10-03.
