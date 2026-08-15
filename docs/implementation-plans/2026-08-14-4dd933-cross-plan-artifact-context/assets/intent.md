# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Let planning and review reuse relevant artifacts from related active, archived, sibling, dependency, and operator-selected plans without loading the plan corpus wholesale.

## Desired outcome

A bounded, typed artifact resolver builds on `Get-PlanIndex.ps1`, inventories a closed set of plan assets, selects only what each consumer and concern needs, confines and size-bounds every read, and records provenance plus reuse, extension, supersession, or conflict in the current work.

## Success signals

- `/cip`, `/cep`, `/dr`, and plan-associated `/cr` share one discovery and artifact-selection contract.
- Consumed intent, designs, decisions, reviews, evidence, and learnings are recorded by plan ID, kind, path, and relationship.
- Missing, stale, malformed, oversized, or conflicting historical artifacts are surfaced explicitly.
- Historical content is treated as untrusted data and never executed as instruction.

## Non-goals

- Replacing the deterministic plan index with a full-corpus semantic scan.
- Loading all assets from every matching plan.
- Letting historical artifacts override current confirmed intent or architecture contracts.

## Definition of done

- Every planning and review consumer can obtain bounded relevant historical context with inspectable provenance and no corpus-wide context load.
