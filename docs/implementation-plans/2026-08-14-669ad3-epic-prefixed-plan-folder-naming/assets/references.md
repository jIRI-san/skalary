# References

## Operator provenance

- Epic `bcece1` plan-folder grouping outcome and confirmed `assets/intent.md`.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): prefer prefixes for new plans; retain only a simple `-WhatIf`-first migration because confirmed intent asks for a script-owned migration.

## Existing owners reused

- `docs/design-notes/architecture/plan-workflow.design.md`: canonical plan IDs, inventory/resolution, dual layouts, epic mirrors, and legacy compatibility.
- `scripts/skalary/PlanState.psm1`: shared parser, inventory, and resolver.
- `scripts/skalary/New-Plan.ps1` and `New-Epic.ps1`: plan/epic creation and membership writers.
- Existing repository locking or safe sequential file operations, plugin bundling, dogfood sync, registry/catalog builders, and plan tests.

## Dependency rationale

- No dependencies. Naming and optional migration use existing plan identity and lifecycle machinery.
- Review-run, container launchers, artifact context, and CI aggregation are consumers at most; they do not define this naming behavior.
