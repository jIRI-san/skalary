# Fleet dispatch v1 contract

## Truth boundary

The scheduler proves persisted orchestrator admission: immutable selected tasks, ready ordering,
at most four active leases, attempt conservation, and terminal attendance. A VS Code subagent call
remains orchestrator-mediated. Provider concurrency is `unverified` unless a host adapter supplies
typed telemetry bound to adapter id/version, run id, lease ids, observation interval, covered calls,
and telemetry digest. Token, credit, and provider-time budgets are unavailable unless that adapter
supplies them; invocation/attempt budgets remain enforceable and are never presented as token limits.

## Store and lifecycle

- The engine derives the repo root from its installed script location and fixes the store at
  `.github/.skalary/fleet/`; callers cannot override either root.
- Run ids are UUIDs. The store root, run directory, fixed input leaves, generation files, stable lock,
  cleanup tombstone, and every ancestor are canonicalized and rejected on symlink/reparse traversal.
- Stable lock acquisition times out after 5 seconds and returns the bounded infrastructure-failure status.
- States are `new -> planned -> running -> completing -> captured -> cleanup-pending -> closed`, with
  `abandoned` terminal for an operator-forced run whose host calls cannot be observed.
- `ListIncomplete` enumerates verified nonterminal runs. `Abandon` writes an epoch/correlation receipt and
  quarantines later results. `Remove` accepts only closed/abandoned authority unless `-Force` is explicit;
  cleanup renames under a confined tombstone before deletion and converges after interruption.
- CIP/CI capture deduplicates by run id plus result digest and verifies the exact bounded entry before
  `MarkCaptured`. CR/DR use idempotent zero-summary capture because review-run owns retained attendance.

## Command status

Every command emits one `skalary/fleet-terminal-status@1` object and exits as follows:

| Exit | Class | Retryable | Meaning |
|---:|---|---|---|
| 0 | success | no | Requested transition completed; terminal run is clean when applicable. |
| 2 | invalid/state-conflict | no | Schema, identity, digest, capability, transition, or immutable-replay refusal. |
| 3 | admission/budget | no | Byte/task/edge/path/view/resource/workflow budget or unsupported-host refusal. |
| 4 | infrastructure | caller decision | Lock/store/atomic-write/cleanup/unexpected failure; authority is retained. |
| 5 | degraded | no | Terminal valid result contains failure, timeout, exhausted throttle, cancellation, or abandonment. |

Throttle wait is an internal recorded transition, not a process retry code. Review publication status takes
precedence after review-run commits: later fleet telemetry/capture failure cannot rewrite review authority and
is reported as a separate fleet exit 4 diagnosis.

## Admission and recovery

- A Plan assigns stable ordinal tasks. Admit selects the lowest ordinal task whose complete dependency set
  succeeded and whose canonical capabilities do not overlap active writers.
- Admit writes a lease token and recovery epoch before a host call. Record requires that token and a unique
  host correlation id. Skills pass both as metadata, but no claim says the host enforces them.
- Typed `throttled` releases its lease, retains task ordinal, persists `notBefore` and charged wait, and permits
  one retry. Typed Retry-After is capped at 60 seconds; aggregate charged wait is capped at 240 seconds.
- Timeout/failure are terminal. Every transitive dependent becomes cancelled; independent ready tasks continue.
- After orchestrator interruption, recorded terminal attempts resume normally. Calls that were leased but have
  no observed terminal result are not called cancelled: the run is incomplete until recovery abandons its old
  epoch. Adviser/Judge late outputs are ignored; Implementor calls run only in disposable worktrees, so late
  writes remain quarantined until an audited commit is deliberately promoted.
- For CR/DR, candidate validation precedes review-run Freeze. A fleet request is derived from the verified
  frozen plan digest. Any fault before first dispatch publishes every frozen slot as `cancelled` with
  `fleet-pre-dispatch-failed`; exhausted throttle publishes that slot as `failed` with
  `fleet-throttle-exhausted`. Review-run remains the post-run authority.

## Role handoff and write isolation

- Role outputs are closed JSON records marked `contentTrust: agent-authored-data`. The engine validates and
  credential-scans every leaf before persistence. Downstream agents receive only a fixed data-file path plus
  the expected digest/schema; output text is never pasted into another prompt or interpreted as instructions.
- `SecretGuard.psm1` is extracted from the review secret guard and becomes the single scanner used by review
  and fleet persistence, with one shared hostile/credential corpus and rejection precedence.
- CIP roles have no edit tool. Baseline/after Git receipts must be empty; any write blocks Judge and drafting.
- Each CI Implementor receives a disposable confined worktree created from the step baseline. It commits there.
  Promotion verifies the commit parent, canonical changed paths, no reparse escape, reserved workflow-state
  exclusion, entry/byte bounds, and declared capabilities, then cherry-picks through a fixed promotion script.
  A failed audit leaves the main worktree unchanged and the disposable worktree quarantined for diagnosis.
- Receipt limits are 4,096 changed paths and 2 MiB of canonical path/status records. Derivation uses Git diff
  from the pinned baseline rather than repeated whole-tree scans; large-tree performance is mandatory.

## Budgets and bounds

| Bound | Value |
|---|---:|
| Active admission leases | 4 |
| Logical tasks per fleet | 128 |
| Attempts per fleet | 256 |
| Dependency edges | 8,128 |
| Path-capability/receipt entries | 4,096 |
| Request/result input | 2 MiB each |
| Rendered plan/result view | 256 KiB each, complete only |
| Terminal status | 8 KiB |
| Diagnostic | 2 KiB |
| Label / omission reason | 128 / 512 characters |
| Capture entry / cumulative fleet capture | 4 KiB / 64 KiB |
| Cumulative lifecycle writes | 4 MiB per maximum run |
| Retry-After / total retry wait / lock timeout | 60 s / 240 s / 5 s |
| CIP draft | 4 logical / 8 attempts |
| CI step | 4 logical / 8 attempts |
| CI plan | 128 logical / 256 attempts (32 four-role steps) |

A plan above 32 executable steps is refused by CIP and must be split before CI. Every boundary is tested at
N and N+1, across replay and resumed persisted counters. The 8,129-edge test targets the pure count guard
before graph semantics; the maximum valid DAG fixture proves 8,128 independently.

The maximum 128-task/256-attempt/8,128-edge/4,096-path lifecycle includes Plan, Admit/Record, Complete,
verification, rendering, capture, and cleanup. It is mandatory on Linux and Windows at 10 s / 30 s and
256 MiB private-byte growth, using a descriptor-digested recipe, CI-leg identity, cumulative-write count,
and seeded time/memory/write over-limit failures.

## Ownership and activation

- `tools/model-allowlist.psd1` remains the only model/fallback owner and gains role-model keys. The fleet role
  registry references those keys; it owns workflow, agent, capability, output schema, and activation owner.
- Workflow-specific agent bodies are hand-authored and parity-tested; no new generator or `79cfe1` dependency
  is introduced. Existing generated concern agents remain untouched.
- `ReviewFleetAdapter.psm1` owns frozen-slot conversion and attempt-to-review-v1 outcome mapping.
- The frozen review plan supplies its invocation budget; fleet config does not copy `28`.
- Fleet schemas embed descriptor limits and deep-compare every duplicate definition with red mutations.
- New CI/autopilot cadence remains code-complete but inactive under the bundled activation field until the final
  integration phase; earlier tests activate it through an explicit test seam. The final phase flips all installed
  copies together after source, installed, structural-eval, and platform evidence are green.
- Plan `25aa23` consumes the adapter's activation-owner handoff; it does not retire a guard from this plan.

## Evidence ownership

| Evidence | Owning test file | Suite | Required discriminator |
|---|---|---|---|
| limits/schema/planning/conservation | `tests/skalary/FleetSchedulerPlan.Tests.ps1` | Fast | exact owner field or semantic diagnostic |
| lifecycle/status/confinement/recovery | `tests/skalary/FleetSchedulerLifecycle.Tests.ps1` | Fast | exact state/exit/diagnostic |
| admission/retry/fake clock | `tests/skalary/FleetSchedulerAdmission.Tests.ps1` | Fast | exact lease/order/wait diagnostic |
| role handoff/security/path isolation | `tests/skalary/FleetSchedulerSecurity.Tests.ps1` | Fast | exact rejection code; main tree unchanged |
| CIP/CI installed lifecycle | `tests/skalary/FleetConsumerInstall.Tests.ps1` | Slow | installed sentinel plus root poison observed |
| CR/DR Freeze-to-view lifecycle | `tests/skalary/FleetReviewAdapter.Tests.ps1` | Slow | exact frozen digest/task/outcome/view |
| maximum lifecycle | `tests/skalary/FleetSchedulerMaximum.Tests.ps1` | Dedicated platform | recipe and CI-leg receipt |
| structural eval execution | `tests/evals/FleetSchedulerRequired.Tests.ps1` | Structural eval gate | exact ID exactly once; duplicate/skip red |

The implementation commits a mutation table beside these tests. Each row names the injected change, exactly
one expected test id, and the expected diagnostic; the harness rejects collateral-only failures. Installed
blindness controls remove one installed dependency to prove fail-loud loading and place a distinctive poisoned
root sentinel whose observation is asserted.

## Documentation by owning step

- Foundation: architecture contract JSON, architecture note/index/human doc, fleet design note/index,
  `.gitignore`, scaffold/runtime-store ownership, plan-workflow and plugin-registry bundle grammar.
- CIP: copilot-customizations and plan-workflow notes plus CIP guides/evals.
- CI/autopilot: plan-workflow, autopilot execution/skill notes plus CI/autopilot guides/evals.
- Review: `ARCH-Review-Run-V1` note (boundary clarification only), review-reporting note, CR/DR dispatch and
  collation guides.
- CEP: plan-workflow note and `25aa23` ownership-handoff assets.
- Integration: CI gates, suite profiles/budgets, registry/marketplace, design/architecture indexes, generated
  human doc, and README only if its documented workflow surface changes.

Every payload-changing step ends with plugin-script sync, plugin-source validation, version/catalog rebuild,
and relevant docs. Dogfood activation of the new CI/autopilot cadence occurs only in the final integration
step so this plan does not mutate the workflow currently executing it.