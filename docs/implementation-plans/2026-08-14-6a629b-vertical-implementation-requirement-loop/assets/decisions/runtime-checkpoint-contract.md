# Runtime Checkpoint Contract

## Ownership

- `Add-WorkflowNote.ps1` is the only Capture writer. It owns bounded crash-released locking, atomic replacement, read-back, shared-secret rejection, sanitization, confinement, and reserved count/byte limits.
- `CheckpointGate.ps1` is the only typed-record parser/reducer and, after the phased CI/autopilot migration, the sole caller of `863d97` phase execution/publication. It owns state digests, blocker reduction, review-stop aggregation, marker batching, and the closed `allow` / `operator-decision` / `blocked` verdict.
- Interactive `/ci` and autopilot consume the gate verdict. Neither parses Capture fields or derives continuation independently.
- `863d97` owns focused test execution, evidence status/finding/disposition, v2 receipt publication, evidence digest enumeration/framing, and evidence exits. The checkpoint gate calls those APIs and adds no fallback.

## Typed Record Grammar

Typed Capture entries use a version token plus closed fields emitted from bound parameters:

| Field | Contract |
|---|---|
| `v` | Literal `1`. |
| `id` | Caller-retained lowercase 32-hex UUID; duplicate identical replay is a no-op and divergent replay fails. |
| `kind` | `intent-confirmation`, `decision`, `uncertainty`, `correction`, `blocker`, or `resolution`. |
| `impact` | `reversible`, `contract`, `user-experience`, `security`, `irreversible-structure`, or `intent`. |
| `confidence` | `low`, `medium`, or `high`. |
| `resolution` | `continue`, `blocked`, `approved`, `rejected`, or `superseded`; this is record state, not a gate verdict or `863d97` evidence disposition. |
| `evaluatedState` | Lowercase SHA-256 over framed canonical plan id, canonical implementation-tree digest, phase, runtime intent digest/confirmation, completed-step IDs, and owned marker inventory. |
| `persistenceCommit` | Optional full commit ID recording where this entry became durable; excluded from `evaluatedState`. |
| `resolves` | Required only for `resolution`; names one unresolved blocker ID at the same state. |
| `supersedes` | Required only for `correction`; names one earlier decision/uncertainty/correction ID. |

The sanitized bounded body is accepted inert untrusted text. Decision bodies state selected choice, rationale, and rejected options; uncertainty/blocker bodies state the unresolved question and consequence; correction bodies state what changed. Control objects contain validated closed fields only, never bodies. Agent consumers place displayed bodies beneath a fixed `UNTRUSTED CAPTURE DATA` delimiter and never interpolate them into instructions or commands.

## Closed Transitions

| Kind | Required relation | Allowed impact / resolution | Result | Mutation |
|---|---|---|---|---|
| `intent-confirmation` | none | `intent` / `approved` | confirmation for runtime-computed exact intent digest | interactive append only |
| `decision` | none | `reversible` / `continue` | no blocker | append or identical replay |
| `uncertainty` | none | `reversible` / `continue` | no blocker | append or identical replay |
| `blocker` | none | structural category or `intent` / `blocked` | unresolved valid blocker | append/reuse same-state blocker |
| `resolution` | `resolves` one blocker | same impact / `approved` or `rejected` | resolves exact blocker/state or remains blocked | interactive append only |
| `correction` | `supersedes` one choice record | inherited impact / `continue` or `blocked` | replaces exact prior choice; structural impact also creates blocker | append or identical replay |

Every other combination, missing target, cross-state relation, cycle, conflicting resolution, or divergent duplicate ID returns verdict `blocked` with zero mutation.

## Reduction And Authority

- `reversible` uncertainty may carry `continue`; the four structural categories and `intent` require a blocker record whose `resolution` field is `blocked`. A valid unresolved blocker yields verdict `operator-decision`, not verdict `blocked`.
- A blocker remains unresolved until exactly one valid operator-origin resolution names its `id` and identical `evaluatedState`. The workflow-only blocker commit does not invalidate that state; a real implementation/intent/step/inventory change does.
- Only interactive `/ci` may invoke interactive-only intent-confirm or resolve actions. It requires a positively established non-redirected host and rejects CI/autopilot variables plus absent/unclassifiable origin before mutation.
- `CheckpointGate` computes the five-section intent digest. The upstream current-value confirmation flag is prerequisite only. Headless first use without a current digest confirmation persists a blocker and exits `42`.
- `ReviewCycleGate -Action Check` runs read-only first. `CheckpointGate` preserves every pending reason/ID and returns stop reason `checkpoint`, `review-cycle`, or `multiple`; unsafe or invalid state dominates, otherwise any valid operator decision maps to `42`.
- Verdict exits are closed: `allow` = `0`; valid unresolved blocker = `operator-decision`/`42`; grammar, link, cycle, secret, digest, or hard-cap rejection = `blocked`/`46` with zero mutation; commit/push persistence failure = `47`. Preflight checks the complete installed inventory including `42-45`, `124`, `143`, and all `863d97` exits.
- Missing targets, cross-state replay, multiple conflicting resolutions, cycles, or invalid kind/link combinations return `blocked` with no mutation.
- Reads are current-phase scoped for execution. Harvest may read the full bounded plan log but cannot alter gate state.

## Durability And Bounds

- The writer uses an OS-released lock with a five-second acquisition bound across read, validation, merge, same-directory atomic replacement, and read-back. Killed holders release it; timeout names the remedy. It never holds this lock while calling evidence APIs.
- Every Capture, lock, temp, and replacement path is canonicalized and rejected when any existing component is a symlink, junction, or reparse point.
- Typed records are limited to 64 records/64 KiB UTF-8 per phase and 256 records/256 KiB per plan. Ordinary records may use 56 phase/224 plan slots; the remainder is reserved for blockers/resolutions. Hard exhaustion returns verdict `blocked` plus a cleanup/escalation remedy and never drops unresolved blockers.
- `SecretGuard.psm1` extracts the existing matcher as `Find-HighConfidenceSecret`; CI, CIP, and review consumers bundle the same module. Missing matcher or a match fails before mutation and reports only credential type and field/location. Every display/harvest consumer also guards typed, legacy, and manually altered bodies before emission; raw Capture reads in CI/autopilot are prohibited.
- On resume, reconcile working Capture against committed state before writing: commit an existing valid record or return `blocked`; reuse an existing same-`evaluatedState` blocker ID rather than creating another.
- The phase checkpoint, receipt, Capture record, and checkbox state are committed together before progression. Isolated blocked paths commit and push before exit `42`; failure exits `47`. Fresh-clone resume must recover the exact pending set.
- Container entrypoint propagates `42`, `46`, and `47` exactly. Sandbox bootstrap cleans stale state, writes one bounded session marker containing only those values, and `launch-sandbox.ps1` validates and returns it; absent, malformed, or stale markers fail closed.

## Evidence And Cost

- Step 1.1 pins the exact predecessor CI/autopilot caller set from `863d97`; 1.2 reroutes interactive CI; 2.1 reroutes autopilot and enables global residual-caller rejection atomically.
- Completed steps declare marker ownership through their referenced acceptance evidence. The gate rejects missing or ambiguous ownership.
- Phase close unions and ordinal-deduplicates owned markers, invokes `863d97`'s focused test executor once, evaluates each non-test marker once, and publishes one v2 phase result for the current state.
- `evaluatedState` reuses `863d97` `EvidenceDigest.psm1` enumeration/framing with one closed projection excluding only checkpoint Capture, evidence publication, checkbox, and persistence metadata. It fails closed on implementation-relevant untracked files, gitlinks, symlinks/reparses, unsupported Git modes, or API mismatch.
- Final integration is keyed by finalization attempt plus tree state: zero phase invocations, one green invocation for an unchanged tree, rerun after failure or tree change, and no duplicate invocation when resuming the same published green state.

## Marker Ownership

| Marker | Owner |
|---|---|
| `test:VerticalLoop.DependencyApiPreflight` | 1.1 |
| `test:VerticalLoop.InteractiveCompletePlanProgression` | 1.2 |
| `test:VerticalLoop.InteractivePhaseCloseSeams` | 1.2 |
| `test:CheckpointGate.TypedRecordTransitionMatrix` | 1.2 |
| `test:WorkflowNote.AtomicTypedCaptureSecurity` | 1.2 |
| `test:WorkflowNote.TypedCaptureLimitsAndCompatibility` | 1.2 |
| `test:VerticalLoop.InteractiveFocusedPhaseEvidence` | 1.2 |
| `test:VerticalLoop.FocusedPhaseEvidenceBatch` | 2.1 |
| `test:VerticalLoop.ExecutionModeInterruptionMatrix` | 2.2 |
| `test:CheckpointGate.OperatorResolutionAuthority` | 2.2 |
| `test:VerticalLoop.AutonomousCompletePlanProgression` | 2.2 |
| `test:VerticalLoop.DistributionAndDocumentation` | 3.1 |
| `test:VerticalLoop.StructuralEvalRegistration` | 3.2 |
| `test:VerticalLoop.FinalIntegrationTreeState` | 3.2 |
| `test:VerticalLoop.PlatformBudgetAndTiering` | 3.2 |

REQ-6 documentation `file:` markers and `review:cr` are final plan evidence owned by 3.2; each earlier payload-changing step still updates and validates its affected copies before commit.