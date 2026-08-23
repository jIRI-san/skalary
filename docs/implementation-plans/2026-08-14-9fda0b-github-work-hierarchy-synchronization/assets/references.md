# References

## Operator provenance

- Epic `bcece1` work-hierarchy outcome and confirmed `assets/intent.md`.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): GitHub-only v1 with deterministic projection, dry run, confirmed apply, mapping, managed sections, refusal, and no-op convergence.

## Existing owners reused

- `docs/design-notes/architecture/plan-workflow.design.md`: epic/plan identity, assets, membership, dependencies, and generated mirror.
- Existing GitHub CLI authentication and `gh` invocation conventions; credentials remain outside repository artifacts.
- Existing plugin generators, dogfood sync, registry/catalog builders, installed-consumer fixtures, and test infrastructure.

## Dependency rationale

- No implementation dependency is required: current epic and plan assets already contain the local projection source. Later `57cc2c` output is consumed when present through the same existing asset shape.
- `25aa23` coherency review may improve an epic before sync but is not required behavior for the GitHub adapter.
- No dependency on artifact-context sidecars, provider capability systems, or live credential infrastructure is required.
