# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08), which prints
an invocation plan before the review run: concerns selected, model per concern, what was dropped by
the cap, and estimated waves.

## Epic discussion provenance

- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 90-92 (2026-08-08): selected as an independent child because declaring dispatch before a run delivers value without the corroboration work.
- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 2-5 (2026-08-14): the operator broadened the contract from review throttling to one shared Designer/Requirements Validator/Judge/Implementor/reviewer fleet for `/cip`, `/ci`, `/cr`, `/dr`, and later `/cep` review, with at most four calls in flight.
- Epic `bcece1` Initial execution policy records the accepted cap, wave, attendance, and provider-throttling behavior.

## The gap

`plugins/code-review/skills/cr/SKILL.md` L57 asks the orchestrator to add a todo per dispatch, so
the fan-out becomes visible *as it happens*. `scripts/skalary/Build-ReviewReport.ps1` L244 reports
`Dispatched N of M budgeted invocations` *after* the run. Neither is a statement of what the run
intends to do before it starts.

The part that matters most is **what was dropped**. `tests/skalary/DispatchGuide.Tests.ps1`
`test:dispatch-budget-reported` confirms the 28-invocation budget is *reported, not enforced*, and
concern selection scales with change size (dispatch-guide §4). So concerns can fall out of a run
with nothing stating which ones, or why. The operator cannot tell a deliberately narrowed review
from a silently truncated one.

## Prior art

- `plugins/code-review/skills/cr/assets/dispatch-guide.md` §4 — scope tiers and concern sets.
- `tests/skalary/DispatchGuide.Tests.ps1` — `test:dispatch-guide-scaling-thresholds`,
  `test:dispatch-budget-reported`.
- `scripts/skalary/Build-ReviewReport.ps1` — post-run invocation count.
- `plugins/design-review/skills/dr/SKILL.md` — the same dispatch shape on the design-review surface;
  whatever lands here has to land there too.

## Indexed reconciliation confirmed 2026-08-21

- **Extend `34088e`.** Reuse its `skalary/workflow-limits@1` owner discovery, parity, installed-consumer,
  and resolver-backed graph protocol; this plan owns the scheduler descriptor, cap, and admission semantics.
- **Extend `b0c0d3`.** Preserve explicit concern/model fanout, size-scaled concern selection, one pass over
  the union, the invocation budget, and model fallback precision; add a machine-derived pre-dispatch
  declaration and real wave admission.
- **Reuse `c21cdc`.** Preserve frozen task identity, task outcomes, attendance derivation, immutable
  publication, and rendering; generic review scheduling never becomes a second authority.
- **Reuse `79cfe1`.** Preserve the seven-concern taxonomy and generated concern-agent authorship.
- **Extend `25aa23`.** Supply the shared scheduler and adapter it consumes; leave epic coherency behavior
  and activation in that dependent plan.
- **Reuse `57cc2c` and `6a629b`.** Preserve confirmed intent, complete vertical delivery, phase
  crosschecks, retained decisions, high-impact escalation, and one writer per scope.
- **Reuse `863d97`, `ca8ba8`, and `a5ad22` boundaries.** Evidence-marker truth remains separate;
  corroboration remains downstream; parallel epic children stay deferred until shared admission and
  non-overlapping scopes are proven.
- **Retain tangential contracts from `001`, `005`, `006`, `768d7b`, and `aaf29b`.** This plan does not
  supersede launcher dispatch, eval semantics, validation flow, suite-budget measurement, or offline
  rebundle behavior.
- **Index limitation.** `Get-PlanIndex.ps1` returned
  `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`; no record is
  inferred from that active folder.

## Review-run contract boundary

This child depends on `c21cdc review-report-as-data`. `c21cdc` owns the versioned frozen-task/result schemas,
validation, persistence, derived attendance, and report rendering. This child owns the shared fleet scheduler
and therefore later **produces** the frozen task-plan records before admission/dispatch; it does not define a
second attendance or artifact format. `ca8ba8` remains the later consumer that evaluates similarity and
corroboration truth. The three ownership seams are plan, record/render, and corroborate.

## Workflow-limit contract boundary

This child depends on `34088e consumer-install-correctness`. `34088e` owns discoverable owner-local limit
descriptors, parity validation, installed-consumer proof, and resolver-backed dependency evidence. This child
owns the scheduler's four-in-flight value and admission behavior, registers that owner, and does not copy the
cap into active consumers without parity coverage.

## Consulted current contracts and guidance

- `docs/architecture-notes/arch-review-run-v1.md` and `ARCH-Review-Run-V1` — Freeze, publication, verified
  delivery, and compact retained review evidence remain authoritative.
- `docs/design-notes/architecture/review-reporting.design.md` — exact task, attendance, installed bundle,
  and review lifecycle boundaries.
- `docs/design-notes/architecture/plan-workflow.design.md` — plan assets, script-only capture, stage, evidence,
  and bundle contracts.
- `docs/design-notes/project/copilot-customizations.design.md` — agent/model ownership, skill size, explicit
  model dispatch, and installed customization inventory.
- `docs/design-notes/architecture/architecture-notes.design.md` — provisional contract and human-doc flow.
- Review ledger: `plan-structure.md`, `testing.md`, `security.md`, `error-handling.md`, and `consistency.md`.
  Applied lessons require mutation-backed workflow evidence, non-vacuous owner/consumer assertions,
  executable declaration truth, fail-loud installed reads, and same-commit generated catalog updates.

## DR round 1 operator resolutions

- Provider-global concurrency is not claimed; the enforceable unit is a persisted admission lease, with
  provider telemetry explicitly verified or unverified.
- Stable work-conserving ready admission replaces strict wave barriers.
- Retry-After is honored only from typed host throttling, capped at 60 seconds and 240 seconds per fleet.
- Superseded by round 2: the initial CI plan budget was 64/128; the accepted and current authority is 128/256.
- Review-run alone freezes review slots and owns post-run attendance; exhausted throttle maps to v1 `failed`.

## DR round 2 operator resolutions

- CI plan budget scales to 128 logical tasks / 256 attempts, supporting 32 mandatory four-role steps;
  larger plans are refused and split before execution.
- Superseded by round 4: the initial disposable-worktree choice was replaced by fixed-root isolated local clones;
  only audited pinned-parent commits are promoted.
- Real host calls remain orchestrator-mediated; the enforceable claim is persisted admission and attempt
  conservation, with provider telemetry explicitly unavailable/unverified unless adapter-bound.
- The complete executable contract, mutation ownership, suite classes, and documentation ownership live in
  `assets/decisions/fleet-contract.md`.

## DR round 4 operator resolutions

- Keep CI and frozen-review budgets separate beneath a durable plan-global 1,024 logical / 2,048 attempt cap.
- Bound incomplete-run listing to 128 total and 32 per page; bound isolated-clone quarantine to eight entries,
  1 GiB aggregate, and seven days, with typed admission backpressure.
- Replace linked worktrees with fixed-root isolated local clones and retain pinned-parent commit audit.
- Superseded by round 5: reserve every fleet-owned staging, failed, and committed write against one 67,108,864-
  byte runtime counter; independently derive the closed maximum recipe below that oracle.
- Use one shared host capability/signalling contract: allowlisted model mapping, sanitized environment, no
  credentials in artifacts or role processes, declared non-network tools only, and correlation reconciliation.
- Keep the large-tree performance contract and bind it to a 100,000-file/4,096-change Dedicated fixture at the
  existing Linux/Windows 10/30-second and 256-MiB ceilings.

## DR round 6 operator resolutions

- Extract one transaction primitive core from review-run and migrate review unchanged; fleet reuses the core
  rather than implementing a parallel persistence engine.
- Derive clone escrow from four measured `--no-hardlinks` clones plus 25%, cap it at 8 GiB, and refuse before
  dispatch when the cap or available-space check fails.
- Keep `Add-WorkflowNote` semantics unchanged. CIP/CI capture appends only a compact summary pointing to
  content-addressed fleet plan/result views.
- Treat plan-global ledger exhaustion as terminal evidence and require a new sibling plan; no ledger extension
  or reset path exists.
- Require a human finalization step to verify the matching content-addressed Active transaction receipt before
  lifecycle `done` and archival.
