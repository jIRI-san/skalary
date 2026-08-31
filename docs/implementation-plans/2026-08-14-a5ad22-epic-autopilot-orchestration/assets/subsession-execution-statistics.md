# Subsession execution statistics

Collected: 2026-08-31

## Scope and method

This learning record covers the 17 substantive child sessions launched by the
epic coordinator from 2026-08-28 through 2026-08-31, plus the `c7e01f`
whole-plan container follow-up launched from the `a5ad22` child session. Short
`echo hello` process probes are not counted as execution sessions.

Test time comes from terminal Pester summaries preserved in child-session tool
output. Repeated reads of accumulated console output were deduplicated by
session, duration, passed count, failed count, and skipped count. This yields a
recorded lower bound: a run without a terminal summary cannot contribute time.
The suite grouping is operational rather than semantic because old output did
not always retain its tier label:

- `Fast/full-large`: at least 700 reported results.
- `Slow/full-medium`: 250 through 699 reported results.
- `Focused/eval/debug`: fewer than 250 reported results.

Build, generator drift, receipt, crosscheck, Git integrity, container startup,
and review-fleet records did not consistently include elapsed time. Their
duration is therefore unknown and is not estimated. Review counts use durable
`review-cycle` records where present and transcript evidence for the older
`57cc2c`, `863d97`, and `25aa23` runs.

## Recorded test time

| Kind | Unique terminal runs | Time | Reported passed | Reported failed | Reported skipped |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fast/full-large | 10 | 5h 51m 16.76s | 8,203 | 16 | 66 |
| Slow/full-medium | 14 | 5h 07m 23.09s | 4,573 | 4 | 168 |
| Focused/eval/debug | 176 | 3h 15m 02.42s | 2,846 | 136 | 28 |
| **Total recorded Pester time** | **200** | **14h 13m 42.27s** | **15,622** | **156** | **262** |

The result totals measure executions, not distinct test identities. They
include expected red runs used to reproduce defects and prove fail-closed
behavior. They must not be read as a final product pass rate.

The 17 app child sessions span 168.32 summed wall-clock hours. That figure is
not compute time: sessions overlapped, remained idle at operator-decision
points, and waited for prerequisite merges. It is included only to prevent the
14.23 hours of recorded Pester process time from being mistaken for total
elapsed orchestration time.

### Recorded Pester time by child session

| Workstream | Runs | Time |
| --- | ---: | ---: |
| `8a0644` dispatch-plan-up-front | 15 | 3h 07m 44.34s |
| Completion-only resume repair | 38 | 1h 48m 46.42s |
| Wrapped-review remediation | 24 | 1h 26m 25.73s |
| Legacy phase-receipt migration | 14 | 1h 20m 55.96s |
| Unauthorized Reopen invalidation | 7 | 1h 19m 23.96s |
| Artifact acceptance and symlink portability | 11 | 1h 17m 36.29s |
| `ca8ba8` review-corroboration-truth | 13 | 1h 15m 28.48s |
| Unauthorized Continue invalidation | 6 | 1h 05m 59.24s |
| CEP provenance repair | 2 | 44m 10.28s |
| `4dd933` cross-plan-artifact-context | 5 | 14m 47.62s |
| `6a629b` vertical requirement loop | 9 | 10m 35.58s |
| `2366ad` cross-repository SI standards | 22 | 8m 11.94s |
| `25aa23` epic coherency review | 4 | 5m 25.88s |
| `863d97` evidence-receipt truth | 13 | 3m 34.51s |
| `a5ad22` epic autopilot orchestration | 3 | 2m 18.60s |
| `57cc2c` intent capture and RFC | 14 | 2m 17.44s |
| `863d97` human-approved finalization | 0 | no timed Pester summary |
| `c7e01f` Windows portability follow-up | not recoverable | typed evidence and focused phase gate passed, but no durable elapsed summary |

The low recorded time for `a5ad22` is a capture limitation. Most implementation
and review work ran in repository containers; only three terminal Pester
summaries survived in the owning child-session record.

## Gate inventory

The orchestration exercised these gate classes:

| Gate class | Purpose | Timing status |
| --- | --- | --- |
| Repository build/full validation | Syntax, JSON, contracts, plan structure, and repository invariants | Passed or disclosed per handoff; elapsed time unavailable |
| Fast Pester tier | Broad unit and policy coverage | Included in recorded Pester total |
| Slow Pester tier | Process-heavy, integration, install, and portability coverage | Included in recorded Pester total |
| Focused acceptance/regression | Exact changed behavior and reproduced defects | Included in recorded Pester total |
| Structural evaluation | Required structural and policy eval cases | Included when a Pester summary survived; otherwise untimed |
| Evidence and receipt | Typed evidence outcomes, receipt freshness, coverage, and truthfulness | Mixed Pester and untimed script gates |
| Generator and installation drift | Canonical/plugin/dogfood/marketplace/registry parity | Elapsed time unavailable |
| PlanCrosscheck/finalization | Evidence completeness, review truth, archive eligibility, and terminal state | Elapsed time unavailable |
| Git integrity | Clean tree, `git diff --check`, ancestry, and published-head checks | Elapsed time unavailable |
| Review attendance | Required reviewer completion and degraded-run detection | Review time unavailable |

The three final Windows failures on the pre-repair `a5ad22` head were
`EpicAutopilot.FinalCrosscheck`,
`EpicAutopilot.NoCheckpointProductionFinalization`, and
`EpicAutopilot.AbruptEvidenceRecovery`. The `c7e01f` follow-up implemented and
harvested their portability repair. Its post-phase review did not complete
before the container disappeared, so no review success is claimed here.

## Review inventory

### Plan-level cycles

| Plan | Date | Review kind | Cycles | Why the cycles ran and stopped |
| --- | --- | --- | ---: | --- |
| `2366ad` | 2026-08-28/29 | CR | 9 | Three automatic cycles for each of two phases and finalization; each stage recorded Wrap at its cap. |
| `57cc2c` | 2026-08-28 | CR | 3 | Three direct review passes successively found empty, malformed, and missing-colon confirmation-marker bypasses; fixes were applied before archival. |
| `863d97` | 2026-08-28/29 | CR | 3 | Finalization review drove bounded parsing, exact waiver, and evidence-truth fixes before the explicit human acceptance and archive. |
| `6a629b` | 2026-08-29 | CR | 12 | Three automatic cycles for each of three phases and finalization; all four stages recorded Wrap at the cap. |
| `4dd933` | 2026-08-29/30 | CR | 13 | Three cycles per phase; finalization received one extra cycle because findings appeared actionable, then Wrapped. |
| `ca8ba8` | 2026-08-29/30 | CR | 19 | Repeated phase review and remediation crossed receipt-migration and authorization repairs; bounded Continue decisions were used, then the plan truthfully Wrapped. |
| `8a0644` | 2026-08-30 | CR | 16 | Phase 1 received one extra cycle; phases 2-4 and finalization stopped at automatic caps and Wrapped with residual evidence. |
| `25aa23` | 2026-08-30/31 | DR | 4 | Three automatic design-review cycles plus one authorized cycle because the initial findings looked clearable. The extra cycle worsened to 72 findings, so another cycle was rejected and the plan Wrapped. |
| `a5ad22` | 2026-08-31 | CR | 14 | Phase 1 received one extra cycle; phases 2-3 stopped at their caps. Finalization received one authorized fourth cycle, which degraded to 13/14 attendance and 42 findings, forcing an honest Wrap. |
| `c7e01f` | 2026-08-31 | CR | 0 completed | The container entered post-phase review but disappeared before recording a result. |
| **Total completed plan-level review cycles** |  |  | **93** |  |

The 93-cycle count excludes ad hoc implementation/debug review passes in
infrastructure-repair sessions because those older records do not share a
durable cycle identity. Counting prose fragments or repeated console reads
would overstate them.

### Machine-readable receipt subset

The repository retains 21 machine-readable review receipts across `4dd933`,
`ca8ba8`, `8a0644`, `25aa23`, and `a5ad22`. They account for:

- 12 clean-attendance and 9 degraded-attendance receipts.
- 197 completed reviewer tasks and 23 failed reviewer tasks.
- 348 recorded findings across High, Medium, and Low severity.
- 21 blocked verdicts. A clean attendance state means the fleet completed; it
  does not mean the review verdict passed.

The final `a5ad22` automatic review
`b834b559-48b9-42a9-a34a-d8880196cbe9` completed 14/14 and retained ten
findings. The explicitly authorized fourth review
`3bd44cea-7bc7-400a-9ecf-ace2426ee7a0` completed 13/14, failed one reviewer,
and retained 42 findings: 10 High, 21 Medium, and 11 Low.

## Lessons

1. Preserve terminal timing in structured receipts. Counts without elapsed
   time made build, drift, crosscheck, and review cost impossible to aggregate.
2. Emit one invocation ID in every Pester summary. Deduplicating accumulated
   console output by result tuple is reliable only as a lower bound.
3. Keep attendance separate from verdict. Several fleets completed cleanly
   while correctly returning `blocked`.
4. Treat Continue as a bounded investment decision. Extra cycles helped only
   when the remaining findings were narrow; the `25aa23` and final `a5ad22`
   cycles showed that more review can expand, rather than close, the finding
   set.
5. Record platform and checkout shape with every validation. Detached HEAD,
   long Windows paths, CRLF behavior, and symlink capability changed outcomes
   independently of product logic.
6. A truthful Wrap is useful evidence, not completion. The active plans retain
   their residual findings and missing prerequisites instead of converting
   review effort into a false DONE state.
