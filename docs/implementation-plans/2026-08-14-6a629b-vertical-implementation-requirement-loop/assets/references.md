# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 0-1: the operator required `/ci` to loop on requirements and preserve full implementation coverage while each phase delivers an MVP or later usable vertical increment.
- The same discussion required independent decisions and uncertainty to be collected for review, with high-impact uncertainty returned to the operator.
- Epic `bcece1` Goal, Plan completeness versus phase shape, MVP checkpoint, and Initial execution policy.
- Dependency `57cc2c`: defines the confirmed intent and vertical plan shape this execution loop consumes.

## Prior-plan index reconciliation

- Consulted `Get-PlanIndex.ps1` on 2026-08-21 for vertical increments, intent/requirement crosschecks, decision provenance, uncertainty, typed evidence, and receipt truth; no plan corpus was read.
- Extend `57cc2c` decisions: complete-plan outcome, MVP-first phases, durable provenance, and high-impact uncertainty stops.
- Reuse archived `006` `REQ-7`: each requirement has machine-checkable typed evidence.
- Reuse archived `b0c0d3` plan-assets decision: runtime artifacts stay under the layout resolver.
- Depend on and reuse active `863d97` `REQ-1` through `REQ-8`, `RISK-1` through `RISK-14`, and its evidence-truth decisions.
- Reuse `ca8ba8` review-attendance separation; review authority is not folded into evidence truth.
- The `768d7b` `RISK-4` evidence-v1 statement that receipts cannot represent skipped results is superseded by `863d97`; no old adapter is planned.
- The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. That path contains review scratch only; the completed archived `cda9da` plan and retired-`arch:` requirement were indexed. See `RISK-7`.

## Governing design and architecture

- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/architecture/autopilot-execution.design.md`
- `docs/design-notes/architecture/autopilot-skill.design.md`
- `docs/design-notes/project/copilot-customizations.design.md`
- `docs/design-notes/architecture/review-reporting.design.md`
- `docs/design-notes/project/ci-gates.design.md` remains a reference for existing suite-tier ownership; update it only if implementation changes that ownership.
- `ARCH-Review-Run-V1`, `ARCH-Eval-Gate-Separation`, and `ARCH-Install-Confinement` are validation boundaries, not changed contracts.

## Review ledger

- Consulted `plan-structure.md`, `testing.md`, `error-handling.md`, `security.md`, `consistency.md`, and `observability.md` on 2026-08-21.
- Applied the catalog-freshness rule, fail-loud bounded-input guidance, non-self-referential evidence guidance, and actionable diagnostic requirement.
