# Evolution Log

## Round 1 - 2026-08-21

**Review state:** degraded. Twelve of fourteen concern/model tasks completed; GPT-5.6 Sol security and operability tasks failed with network errors. The review merged 53 findings from 87 raw records.

### Issues found

- Enrollment could fail open if state-file presence were the signal; interview state also risked duplicating `cip-stage` authority.
- Approval and confirmation were detached from mutable content, and the approved flow placed the final checkpoint after drafting.
- Phase 1 enforced content whose producers arrived in Phase 2; REQ-5 and named evidence straddled phase closure.
- The plan lacked a shared bounded grammar/read model, resume semantics, dependency consumption, explicit asset ownership, consumer negative matrices, and per-step distribution closure.
- Security evidence did not cover hostile content and reader escapes; context and correction loops had no practical bounds.
- Exploration retirement, final gate evidence, DR asset loading, and explicit enrolled/legacy signals were underspecified.

### Issues fixed

- Added independent enrollment, kept `cip-stage` authoritative, and made `Set-PlanStage` responsible for the gated `drafted` transition.
- Renamed the concept to interview gates/context, assigned the shared grammar/read model to `PlanState.psm1`, and specified a canonical-plan-bound locked idempotent batched writer.
- Chose invalidation-before-write transactional content updates, interactive-only approval, explicit revocation, three-round correction caps, resume-at-first-pending behavior, and all-stage integrity checks.
- Moved design classification after a provisional outline and final confirmation before detailed drafting; co-located the Phase 1 producer and gate path.
- Added concrete byte/string/quote bounds, hostile-input and read/write confinement matrices, once-per-invocation reads, headless operator-needed behavior, and real legacy-corpus coverage.
- Added dependency consumption, source/install distribution closure at each script-changing step, exploration promotion/retirement, deterministic Tier-1 evidence, and final gate inventory coverage.

### Issues deferred or rejected by the simplicity gate

- No persistent context cache: bounded assets are read once per invocation and at crosschecks.
- No runtime telemetry or transition log: deterministic output and git history remain authoritative.
- No mandatory Tier-2 evidence: LLM behavior evaluation remains report-only by architecture contract.
- No content digest: the operator selected a transactional governed writer. Direct edits outside that writer remain an accepted review-visible limitation.
- No general tree-validation performance project or perpetual prior-art receipt; both exceed the confirmed feature scope.

## Round 2 - 2026-08-21

**Review state:** blocked. All fourteen concern/model tasks completed; the review reported 16 High, 10 Medium, and 2 Low findings.

### Issues found

- Dependency admission remained hard-coded to plan `006`; autopilot and `/cep` were missing from the governed contract.
- The canonical reader, repair path, correction counters, approval source, final trigger recheck, lifecycle rank checks, closed marker/asset vocabulary, and schema authority were incomplete.
- Payload-only changes, Tier-1 case deletion, suite-tier placement, plugin version skew, archive behavior, exploration indexes, eval docs, recovery, and same-HEAD final evidence needed explicit contracts.
- Dual deletion could erase enrollment provenance, requiring either a permanent baseline or an accepted current-tree limitation.

### Issues fixed

- Generalized direct/transitive dependency admission and added `/cep`, `/ci`, `/dr`, and autopilot to the shared writer/reader boundary.
- Added bundled schema ownership, closed resolver/header vocabulary, writer-owned initialization, durable correction state, rank/floor/crosscheck checks, final trigger comparison, approval-source/refusal semantics, and pending-state repair.
- Bound hostile-input controls to writer/reader matrices, section lists to parity tests, every payload step to distribution closure, and stable Tier-1 cases to missing/skipped/duplicate enforcement.
- Added Slow-tier placement and measurement, schema capability failure, prose-gate supersession, exact lock budget, archive warnings, exploration-index removal, eval documentation, recovery convergence, per-owner write scope, and same-HEAD final receipts.

### Operator decisions and retained limits

- Dual marker/state deletion is accepted as git/review-detectable; no permanent legacy baseline.
- Enrolled archived plans are warn-only.
- JSON shape uses a bundled schema; transition semantics remain in `PlanState.psm1`.
- Unknown enrolled versions fail closed across independently installed plugins.
- Round-1 simplicity rejections remain in force.

## Round 3 - 2026-08-21

**Review state:** clean attendance with findings. All fourteen tasks completed; 68 raw records merged into 46 findings. One Critical item was explicitly identified by the reviewer as dispatch framing rather than a plan defect.

### Issues found

- Schema distribution, dependency traversal, writer naming, phase-due evidence, receipt ownership, and dependency bootstrap still needed precision.
- Lifecycle/write locking, consumer rollout, installed autopilot code, exit-42 durability, read diagnostics, reader hostile checks, typed authority, repair/version order, and objective-versus-judgment evidence were incomplete.
- Payload convergence, architecture/design-note scope, exploration deletion, eval grammar, stdin transport, plan-006 migration, Slow baseline, archived writes, schema runtime compatibility, and template parity needed explicit ownership.

### Issues fixed

- Added generic schema closure and bounded dependency traversal; unified `Set-InterviewGates.ps1`; assigned step-level evidence; reused the existing commit-bound receipt; and widened documentation/cleanup scope.
- Added one lifecycle/writer lock, `Get-PlanState` fields, installed autopilot closure, reasoned exit-42 ordering, identical reader/writer hostile matrices, non-authoritative prose rules, version-before-repair, post-draft resume, and archived-write refusal.
- Split objective parser evidence from operator/DR judgment; used registered `eval:` grammar; added bounded stdin transport, explicit generic/006 ownership, Slow baseline, code/schema compatibility, template parity, and structural DR wiring checks.

### Operator decisions and known issues

- Runtime code validates shape on PowerShell 7.0; schema remains the bundled parity contract.
- Interview corrections keep separate storage but share review-cycle semantics.
- Intent remains a per-step `/ci` read; domain/design are invocation and crosscheck reads.
- Promoted exploration files are deleted after links/indexes are repaired.
- Dependency bootstrap, dual enrollment deletion, out-of-band writer bypass, and reviewer-enforced operator identity remain in `plan.md` as Known Plan Issues.