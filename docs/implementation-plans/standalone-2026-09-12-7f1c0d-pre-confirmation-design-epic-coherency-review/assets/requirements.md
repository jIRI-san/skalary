# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | `/cip` runs the review flow after the complete plan draft and before final operator confirmation or writing `planning-confirmed`. | `test:PlanningReview.Ordering` | 1.1, 2.2, 3.1 |
| REQ-2 | The review call uses `secondary-model-high` with high reasoning; the applicability call uses `primary-model-high` with high reasoning. The normal flow is exactly two calls. | `test:PlanningReview.ModelRouting` | 1.1, 1.2, 2.2 |
| REQ-3 | Standalone plans receive the design lens. Plans with a resolvable epic marker receive design and epic-coherency lenses in the same reviewer call. | `test:PlanningReview.ScopeSelection` | 2.1, 3.1 |
| REQ-4 | The reviewer is read-only, reports all evidence-backed findings, and does not require every finding to be fixed or the plan to reach a clean verdict. | `test:PlanningReview.AdvisoryReviewer` | 1.1, 1.2, 2.1, 2.2 |
| REQ-5 | `primary-model-high` evaluates every finding against plan intent, active project contracts, existing implementation, epic context where applicable, and Simplicity First, then recommends fix, simplify, defer, or ignore plus the smallest useful edit. | `test:PlanningReview.Applicability` | 1.1, 2.2, 3.1 |
| REQ-6 | The operator sees all findings and recommendations in one consolidated choice; `/cip` applies only selected changes to the current plan and does not automatically rerun review. | `test:PlanningReview.OperatorSelection` | 1.1, 2.1, 2.2 |
| REQ-7 | A failed or incomplete reviewer/evaluator call stops visibly without fabricated results, automatic fallback fleet, judge panel, or success-shaped continuation. | `test:PlanningReview.IncompleteStop` | 1.1, 1.2, 2.2, 3.1 |
| REQ-8 | Epic coherency checks intent/done contribution, scope overlap, ownership, interfaces, necessary acyclic dependencies, sequencing, speculative shared machinery, and direct conflict with implemented sibling behavior using targeted reads. | `test:PlanningReview.EpicCoherency` | 1.2, 2.1, 2.2, 3.1 |
| REQ-9 | Active architecture/design notes and operator guides describe the same simple workflow and keep the existing `planning-confirmed` baseline unchanged. | `test:PlanningReview.Documentation` `file:docs/architecture-notes/arch-direct-workflow.md#contains:pre-confirmation` | 3.1, 3.2 |
| REQ-10 | Canonical plugin sources, manifests/catalogs, and dogfood copies converge through existing lifecycle tooling with no undeclared payload. | `test:PlanningReview.ConsumerInstall` `test:bundle-no-drift` `test:dogfood-no-drift` | 3.2 |
