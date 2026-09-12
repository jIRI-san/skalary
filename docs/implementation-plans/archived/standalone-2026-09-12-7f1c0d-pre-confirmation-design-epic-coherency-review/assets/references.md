# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- Operator-confirmed workflow discussion, 2026-09-12.
- `docs/architecture-notes/arch-direct-workflow.md` — current direct review and planning contract.
- `docs/design-notes/project/simplicity-first.design.md` — deletion/reuse/local-fix priority and reviewer-overengineering guardrail.
- `docs/design-notes/architecture/plan-workflow.design.md` — current `/cip` confirmation and Git-baseline flow.
- `docs/design-notes/architecture/review-reporting.design.md` — read-only DR, model routing, and advisory review behavior.
- `docs/design-notes/project/copilot-customizations.design.md` — plugin and dogfood source/distribution boundaries.
- `docs/design-notes/architecture/direct-workflow-core.design.md` — current direct review primitives and explicit absence of retired receipt machinery.
- `docs/operator-guide/planning.md` and `docs/operator-guide/reviews.md` — current operator-facing sequence and model matrix.
- Plan `367e9a` (`Simple review-to-plan workflow`) — prior simplification that removed the fixed review fleet and automatic Judge.
- Plan `25aa23` (`Epic coherency review`) — historical coherency scope and the retired verdict/receipt design that must not return.
- Plan `33a78a` (`AI credit budget optimization`) — current alias, context, and delegated-call boundaries.
