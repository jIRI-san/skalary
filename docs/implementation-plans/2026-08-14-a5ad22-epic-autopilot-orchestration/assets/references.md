# References

## Operator provenance

- Epic `bcece1` epic-autopilot outcome and confirmed `assets/intent.md`.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): host loop over existing rollup/launcher, one small state record, one child at a time, merge stop, refresh, and final crosscheck.

## Existing owners reused

- `docs/design-notes/architecture/plan-workflow.design.md`: `Get-PlanState` epic rollup, `NextChild`, dependency completion, plan state, and workflow evidence.
- `docs/design-notes/architecture/autopilot-execution.design.md` and `autopilot-skill.design.md`: existing per-plan launchers, host/container boundary, progress, and operator stops.
- Existing terminal verification, branch/remote-head checks, plugin generators, dogfood sync, registry/catalog builders, and installed-host tests.

## Dependency rationale

- No implementation dependency is required: sequential child selection and launch reuse the existing epic rollup and per-plan launcher, not the task-fleet dispatcher.
- Simplified `25aa23` is invoked after final merge when available but does not block the core sequential implementation; an epic-intent/done crosscheck is the fallback.
- `669ad3` naming and `79cfe1` generated concerns are not required to resolve children or run existing launchers.
