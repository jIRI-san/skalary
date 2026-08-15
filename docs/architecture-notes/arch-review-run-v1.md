---
description: Architecture note for review-run v1 execution authority, verified delivery, and compact durable evidence.
globs:
  - "schemas/review/**"
  - "scripts/skalary/{Build-ReviewReport,Get-ReviewRun,Remove-ReviewRun,ReviewRun}.ps*1"
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
- Publish commits content-addressed plan, run, summary, and full artifacts through one manifest.
- Readers verify schema, confinement, encoding, byte count, digest, and cross-document identity.
- Plan finalization reconstructs the retained pair from verified live authority and repairs an
  interrupted pair before cleanup; receipt replay cannot authorize deletion from self-asserted data.
- Generic published cleanup emits verified full bytes; force cleanup applies only to unpublished
  abandoned runs.

## Depends On / Depended On By

- Depends on: review schemas, repository confinement, atomic file replacement, Git scope derivation.
- Depended on by: CR/DR dispatch, plan review gates, admission partition rollup, retained evidence.