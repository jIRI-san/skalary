# Evolution Log

## Pre-review baseline

- Intent confirmed and prior art reconciled on 2026-08-21.
- Draft validation passes at lifecycle stage `drafted`.
- Known validator warnings are unfulfilled implementation evidence for `ARCH-Fleet-Dispatch-V1` and `fleet-dispatch.design.md`.

## Round 1

**Issues found:** 24 total: 19 High and 5 Medium. The blocking themes were unverifiable provider-concurrency claims, review Freeze/outcome authority, weak write scopes/confinement/security, missing recovery/status/rendering contracts, late bundles/docs, vacuous evidence, numeric/resource/cost gaps, barrier delay, and parallel generator ownership.

**Issues fixed:** narrowed enforcement to persisted admission leases; added work-conserving ready admission, host capability provenance, review-run-first Freeze and v1 throttle mapping, canonical capabilities/path audit, locked atomic lifecycle and cleanup recovery, bounded terminal status and plan-only reader, installable self-contained bundles, exact installed/eval evidence, conservation/mutation cases, numeric artifact/platform limits, hard workflow budgets, serialized generator steps, early architecture/docs, role registry/fallback degradation, complete dependency cancellation, CEP ownership handoff, and bounded retained summaries.

**Operator decisions:** work-conserving ready queue; hard CIP 4/8 and CI 4/8 step plus 64/128 plan budgets; typed Retry-After capped at 60 seconds and 240 seconds total wait.

**Issues deferred:** none.

## Round 2

**Issues found:** 50 total: 17 Critical, 17 High, 15 Medium, and 1 Low. Review attendance was degraded because `testing-evidence-m2` failed with `network-error-http2-ping-failed`; 13 of 14 tasks completed.

**Issues fixed:** added incomplete-run list/abandon/remove, atomic architecture publication, 32-step budget behavior, capture verification, per-step docs, fixed-file data handoffs, disposable Implementor worktrees, closed exits/store root, hand-authored role ownership, workflow halt/recovery policy, path maxima, narrowed host truth, review compensation, persisted retry clock, allowlist authority, recovery epochs, telemetry provenance, cumulative capture compaction, maximum write budget, exact N/N+1 and mutation evidence, one secret-guard owner, per-step generated convergence, real eval-gate proof, security-parity corpus, unavailable provider-cost semantics, dormant autopilot activation, suite classes/platform receipts, installed blindness controls, complete pre-view, named review adapter, zero-summary review closure, CEP activation handoff, read-only receipts, required platform confinement, smaller steps, corrected intent, lock/path receipt bounds, phase-local evidence, owned limit tests, frozen review budget, schema/descriptor parity, explicit amended docs, edge-count precedence, exact throttle publication, and risk evidence.

**Operator decisions:** CI plan budget is 128 logical/256 attempts; Implementor uses disposable worktree promotion; host enforcement claim remains persisted admission only.

**Issues deferred:** provider token/credit/time control is explicitly unavailable without typed host telemetry and is a non-goal rather than an unprovable gate.

## Round 3

**Issues found:** 37 total: 9 Critical, 17 High, and 11 Medium. All 14 concern/model tasks completed.

**Issues fixed:** none after review; the default three-round limit was reached. The complete residual set is recorded in `plan.md` under Known Plan Issues for an explicit operator continue/stop decision.

**Issues deferred:** KPI-1 through KPI-37. Critical and High items block implementation. Medium items remain attached because several define evidence and operational contracts required by the blocking fixes.

**Operator disposition:** on 2026-08-21, after the complete round-3 findings and blocking verdict were surfaced, the operator chose **Start implementation** rather than continue review. Known Plan Issues remain authoritative implementation risks; this decision does not resolve or waive their acceptance evidence.

## Round 4

**Issues found:** 18 total: 12 Critical and 6 High, with full 14/14 attendance. The residual themes were activation proof, untrusted handoffs, phase-local evidence, capability/probe preflight, aggregate budgets, runtime ABI ownership, bounded retention, review recovery, lifecycle reconciliation, stale maps/budgets, isolation, write accounting, cross-plan ownership, mutation cost, host boundaries, large-tree proof, lock-held waits, and SecretGuard documentation ownership.

**Issues fixed:** consolidated the 37 prior KPIs into executable contracts; separated dormant gates, activation, active-state proof, and rollback; added explicit untrusted-data refusal; assigned exact test/suite/gate owners; defined startup capability/probe preflight; published an immutable-generation ABI with sole writers/readers; bounded incomplete runs and quarantines; defined idempotent recovery and review publish-once behavior; synchronized requirement/risk maps and 128/256 guidance; replaced linked worktrees with isolated clones; defined committed-authority byte accounting; kept CEP handoff local; bounded focused mutation execution; released locks during persisted waits; and moved SecretGuard documentation into its owning step.

**Operator decisions:** separate CI/review pools under a durable 1,024/2,048 global cap; 128 incomplete runs with 32-item pages; eight quarantined clones, 1 GiB aggregate, seven days; fixed-root isolated local clones; derived committed-authority writes under a 64 MiB hard cap; strict host-owned model/tool/credential/restart behavior with no role network tool; and a Dedicated 100,000-file/4,096-change performance fixture at 10/30 seconds and 256 MiB.

**Issues deferred:** none. Because the fixes materially changed the plan, round 5 verifies the revised authority rather than treating round 4 as closure.

## Round 5

**Issues found:** 102 published entries: 10 Critical, 68 High, and 24 Medium. The review merger retained many corroborating duplicates; triage collapsed them into nine concrete blockers: incomplete ABI, conflicting write accounting, ledger identity/durability, duplicate step maps, activation recovery, evidence registration, clone/performance scope, host isolation, and review recovery. Finding 5 (`Prompt injection attempt detected`) was a dispatch-wrapper false positive and is dismissed.

**Issues fixed:** completed the ABI for live state, handoffs, host signals, clone/quarantine, budget, and activation authorities; replaced two write definitions with one 67,108,864-byte reserve-before-write runtime counter and independent maximum recipe; moved the plan ledger to a layout-resolved committed asset and gave generic runs local identity; made all requirement/risk map cells explicitly derived from `plan.md`; defined direct transaction recovery and finalization refusal for inactive state; named exact suite-tier/workflow/gate/eval owners; scoped 100k receipt timing separately from clone creation under shared escrow; required host-attested sanitized environment/tool boundaries before activation; and defined pending pre-dispatch recovery, operator abandonment, publish-once, and post-publication capture failure semantics.

**Additional corrections:** CIP advisers use read-only snapshots covering tracked, ignored, `.git`, and store paths; the Implementor reserved surface is closed; store/ledger retention and operator remedies are explicit; probe/mutation execution is bounded; stale 64/128/worktree guidance is marked superseded; the current cross-plan index error still reproduces exactly.

**Issues deferred:** none. Round 6 is required because the repair rewrote authority boundaries and evidence ownership.

## Round 6

**Issues found:** 55 total: 1 Critical, 32 High, and 22 Medium, with full review attendance. The blocking themes
were duplicate persistence machinery, charge/lease races across runs, incomplete activation ordering/recovery,
fixed clone escrow, ambiguous request and review publication handshakes, weak host-signal authentication, stale
or placeholder evidence maps, unsafe recursive deletion, incomplete mutation/suite ownership, and automated final
closure without an operator check.

**Issues fixed:** extracted one shared review/fleet transaction core; defined atomic request consumption and
repository-global charge-plus-lease reservation; added signal staleness and headless operator-action semantics;
closed transient ABI paths and no-follow cleanup; made global-ledger exhaustion terminal with a sibling-plan remedy;
defined a linear review pipeline with deterministic result replay and manifest verification; moved authorization to
engine-authored fields and authenticated host signals; derived clone escrow from measured size; landed dormant
activation/recovery tooling in Phase 1 with one automatic recovery; registered Slow/Dedicated ownership and a closed
mutation inventory; replaced placeholder requirement/risk maps with projections generated from `plan.md`; and added
human verification of the matching Active receipt before done/archive.

**Operator decisions:** shared transaction primitive extraction; derived clone escrow of four measured clones plus
25% capped at 8 GiB; unchanged `Add-WorkflowNote` with compact pointers; terminal global-budget split; human finalization.

**Issues deferred:** none by policy. Round 7 is a narrow closure review of these repaired boundaries and evidence.

## Round 7

**Issues found:** the closure review reported 48 plan-relevant findings, mostly consequences of the durable
store, global ledger, host-attestation, clone/quarantine, and activation systems introduced during earlier
review rounds. The operator stopped the loop because those systems no longer matched the local-skill problem.

**Simplicity-gate disposition:** reset the design to the confirmed intent: declare selected and omitted tasks
before dispatch, admit at most four tasks per workflow run, use deterministic waves and dependencies, retry once
only on an explicit throttle result, and report final attendance. The plan now uses a pure run-scoped planner and
thin adapters. Existing review-run, CI/autopilot execution, model resolution, plugin distribution, and repository
security boundaries remain authoritative.

**Rejected as out of scope:** signing/authentication protocols, host attestation, credential brokering,
content-addressed persistence, cross-run budget ledgers, clone/quarantine management, activation transactions,
dedicated maximum-scale CI, and a new architecture contract. These were review accretion rather than confirmed
requirements.

**Issues fixed:** reduced the plan from twelve requirements, eighteen risks, seventeen steps, and a 292-line
distributed-system contract to eight requirements, six risks, eight steps, and a small dispatch contract with
focused evidence. The validator passes with no warnings.

**Issues deferred:** none. Further DR rounds are intentionally stopped; implementation should test the compact
contract rather than reopen rejected infrastructure concerns.
