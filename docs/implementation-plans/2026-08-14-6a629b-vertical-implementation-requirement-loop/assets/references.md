# References

## Operator provenance

- Epic `bcece1` goal, MVP checkpoint, plan-completeness boundary, and confirmed `assets/intent.md`.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): retain admission, evidence crosscheck, decision/uncertainty capture, operator checkpoint, and one-phase stop/resume; remove duplicate parser/capture/parity machinery.

## Existing owners reused

- `docs/design-notes/architecture/plan-workflow.design.md`: `Get-PlanState`, plan metadata, typed evidence, `Add-WorkflowNote`, and autopilot scope behavior.
- `scripts/skalary/PlanState.psm1` and `Get-PlanState.ps1`: plan parsing, progress, dependencies, and next-step state.
- `scripts/skalary/Add-WorkflowNote.ps1`: layout-resolved capture writer.
- Existing autopilot `next-phase`/whole-plan launchers and current evidence receipt/crosscheck infrastructure.

## Dependency rationale

- `57cc2c` is required for the confirmed intent/design checkpoint behavior this loop consumes.
- `863d97` is required because phase admission and close must distinguish truthful evidence statuses rather than infer success from checkboxes.
- No dependency on dispatch planning is required for the core vertical loop.
