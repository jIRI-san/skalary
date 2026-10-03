---
description: Implementation guidance for the local-first, restartable factory-loop plugin and its project-owned adapter boundary
globs:
  - plugins/factory-loop/**
  - tests/factory-loop/**
---

# Factory Loop

## Purpose and boundaries

Factory-loop runs one bounded issue-to-delivery chain for an explicitly selected repository. The
plugin is the only orchestration component: local scripts and checkpoint files own the state; the
operator supplies personal scheduling and project-owned live provider commands. Do not add hosted
Skalary workflows, services, databases, agent swarms, or cross-plugin path frameworks.

Loopback adapters and demo providers are simulated and cannot represent live deployments. Live ADO
or GitHub integrations are deliberately not bundled. A project-owned adapter is an explicit command
configured by the consumer and must honor the shared JSON contract in the operator guide.

## Runtime flow

`Start-FactoryLoopChain.ps1` validates one confirmed plan through `Test-PlanCriteriaBaseline`, binds
the full source SHA and stable chain ID, and initializes a confined consumer checkpoint. A finite
`Invoke-FactoryLoopTick.ps1` call advances one checkpoint stage with zero AI calls; a personal
scheduler invokes it at the configured interval. A lock enforces one active chain per project.

Every mutation persists a stable operation ID before dispatch and reconciles that same ID after a
restart. Unknown or malformed outcomes stop as blocked/inconclusive rather than retrying blindly.
Human merge is required before artifact creation. The artifact is a digest-pinned snapshot derived
from the actual merge commit; deployment, acceptance, telemetry, approval, and evidence all refer
to that same digest.

Test acceptance precedes a bounded telemetry observation. Production triggering requires a fresh
operator approval for the exact accepted digest, then production identity and acceptance checks.
Missing access, stale identity, uncertain query coverage, or unverified deployment-trigger exclusion
are blockers—not success-shaped defaults.

## Repairs

Initial implementation follows ordinary `/ci` admission after initial plan confirmation. The
existing launcher accepts narrowly scoped repair mode only after an identified failed build or
confirmed deployed defect. Repair revalidates the immutable original criteria, reserves before
invocation, and cannot write requirements or confirmation/checklist state.

Each corrective attempt uses a separate `factory-repair/<incident>/<attempt>` branch and successor
PR. Admission is capped at two PRs per incident and two corrective calls per stable build lineage.
Repair PRs still require checks and human merge; the new artifact repeats test, telemetry,
artifact-specific production approval, production deployment, and production acceptance. Bug closure
requires the repair artifact to pass its original reproducer and evidence publication.

## Evidence and safety

Evidence is allowlisted metadata bound to the validated merge/artifact and committed in a separate
worktree/branch. It excludes raw logs and customer payloads and runs the existing repository
`SecretGuard`. The project owner must verify that the evidence branch cannot trigger deployment;
the runtime requires explicit acknowledgement rather than pretending to inspect arbitrary CI
configuration. Evidence filenames are derived from hashed chain, work-item, and artifact identity;
path creation rejects symlink/reparse-point traversal. The recording timestamp is checkpointed
before commit so crash recovery reuses the same immutable record. Evidence publication and each
close operation have separate replay checkpoints.

## Tests

`tests/factory-loop/FactoryLoop.Tests.ps1` exercises the real local Git demo and code-level
acceptance with injected clocks and simulated provider boundaries. Installed global and repository
layouts must remain confined to the explicit consumer; global project actions never mutate the
plugin payload. Waza cases are optional, describe-only, and not part of deterministic acceptance.

## Dubious decisions

The MVP accepts project-owned scripts and a personal scheduler instead of adding native provider
connectors or a hosted orchestrator. This keeps credentials, permissions, and scheduling within
the consumer's existing controls, at the cost of requiring the operator to author and validate each
live adapter.
