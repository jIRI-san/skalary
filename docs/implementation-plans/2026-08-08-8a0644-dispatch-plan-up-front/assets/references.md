# References

## Operator provenance

- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 90-92 (2026-08-08): declare selected review work and omissions before dispatch.
- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 2-5 (2026-08-14): share the contract across Designer, Requirements Validator, Judge, Implementor, and reviewers with at most four admitted calls per run.
- Epic `bcece1` accepted simplified cut and initial execution policy.
- [2026-08-22 plan simplification review](../../epics/2026-08-22-plan-simplification-review.md): keep the pure planner and run-scoped adapter; reject a durable fleet platform.

## Existing owners reused

- `docs/architecture-notes/arch-review-run-v1.md`: frozen review tasks, publication, and retained evidence remain authoritative.
- `docs/design-notes/architecture/review-reporting.design.md`: review task and attendance boundaries.
- `docs/design-notes/architecture/plan-workflow.design.md`: plan state, typed evidence, and plugin distribution.
- Existing review agents and concern definitions are reused unchanged.

## Dependency rationale

- `57cc2c` supplies confirmed planning context consumed by `/cip` and downstream workflows.
- `6a629b` supplies the vertical phase/checkpoint loop into which implementation roles are dispatched.
- Archived `c21cdc` is the delivered review-run v1 authority consumed by the CR/DR adapter; because it is complete, the explicit contract edge adds no active blockage.
- No dependency on consumer-install, concern-generation, or durable fleet infrastructure is required.
