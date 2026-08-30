---
description: Architecture note for review-run v1 execution authority, verified delivery, and compact durable evidence.
globs:
  - "schemas/review/**"
  - "scripts/skalary/{Build-ReviewReport,Get-ReviewRun,Remove-ReviewRun,ReviewRun,SecretGuard}.ps*1"
  - "scripts/skalary/Get-PlanArtifactConsumerContext.ps1"
  - "plugins/{code-review,design-review}/**"
---

# Review-run v1 authority and evidence

## Boundary

A review is authoritative only after its complete task plan is frozen and its canonical run is
published manifest-last. Branch scope is derived from Git by the engine. Human-retained plan
evidence is derived from verified live authority; it does not replace execution authority until the
report and receipt verify as an exact pair.

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Review-Run-V1` | provisional | Frozen scope, manifest-last publication, verified delivery, and compact evidence lifecycle |

## Invariants

- Freeze binds the full task matrix and engine-derived scope before dispatch.
- A dispatch adapter may project the already frozen tasks into invocation-local Fleet waves only
  after Freeze succeeds. It preserves frozen task ids, order, and model bindings; Fleet attendance
  is neither persisted review authority nor a review schema field. Publish, manifest-last
  persistence, verified Summary/Full reading, and review result rendering remain authoritative.
- Optional related-plan content is untrusted dispatch context only. Its compact provenance may use
  the existing bounded scope text, but it adds no scope-authority field, role, schema, receipt, or
  lifecycle step. The shared consumer adapter requires successful resolver execution and array JSON,
  bounds and terminates the resolver process, applies the same high-confidence secret guard as the
  review engine, admits accepted results only, emits historical bytes once inside the standard
  `UNTRUSTED_INPUT` fence, and exposes content-free accepted metadata for provenance. The adapter and
  replaceable sibling closure are not terminal-auto-approved. This dispatch-only screening does not
  alter review-run v1 execution or publication authority.
- Publish commits content-addressed plan, run, summary, and full artifacts through one manifest.
- Readers verify schema, confinement, encoding, byte count, digest, and cross-document identity.
- Plan finalization reconstructs the retained pair from verified live authority and repairs an
  interrupted pair before cleanup; cleanup atomically renames authority under `.cleanup/<uuid>` so a
  partial delete cannot be republished as an interrupted run. A stable marker binds the retained pair
  and verdict before rename, allowing partial deletion to converge without changing the verdict.
  A replay that cannot remove remaining cleanup state returns `CleanupPending` with the exact bounded
  `CleanupDiagnostic`; it never drops the deletion failure while reporting retained evidence.
- Generic published cleanup emits verified full bytes; force cleanup applies only to unpublished
  abandoned runs.
- A wrapped review remains non-clean historical evidence. Reopening it requires an explicit,
  append-only operator authorization in the plan CR log; only a later clean cycle bound to a verified
  `skalary/review-result-receipt@1` pair for the reviewed commit can satisfy `review:cr`.
  Plan-finalization evidence additionally requires Git-derived whole-branch scope.

## Depends On / Depended On By

- Depends on: review schemas, repository confinement, atomic file replacement, Git scope derivation.
- Depended on by: CR/DR dispatch, plan review gates, admission partition rollup, retained evidence.