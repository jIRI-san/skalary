# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | `/cip` rephrases and confirms operator intent at three checkpoints: intent, domain/design context, and final pre-draft summary. Confirmed wording, decisions, uncertainty, and rejected alternatives remain in the existing Markdown assets. | Focused cases prove all three checkpoints, correction/resume behavior, and preservation of the five required intent sections. `test:Cip.IntentConfirmationCheckpoints` | 1.1, 3.2 |
| REQ-2 | Current lifecycle machinery writes one simple confirmation marker only after all checkpoints pass, reports it through existing plan state, and invalidates it whenever intent or design content changes. | Lifecycle tests prove confirmation, invalidation, resume, and refusal to advance with stale confirmation without adding a second state authority. `test:Cip.IntentDesignConfirmationLifecycle` | 1.2, 3.1, 3.2 |
| REQ-3 | The existing design asset and template contain a concise Mermaid program design and optional call stacks when they clarify control flow; operator confirmation is required before detailed drafting. | Template, installed-flow, and operator-confirmation tests pass; design judgment remains reviewable. `test:Cip.ConciseDesignFlow` `review:dr` | 2.1, 3.1, 3.2 |
| REQ-4 | `/cip` plans the complete desired outcome in MVP-first vertical phases, maps every requirement to a step, and leaves semantic slice usability to operator/reviewer judgment. | Existing parser checks reject unmapped requirements and incomplete final routing while focused guidance coverage preserves MVP-first complete planning. `test:Cip.VerticalPlanObjectiveInvariants` | 2.2, 3.2 |
| REQ-5 | `/cip`, `/ci`, `/dr`, and autopilot consume the same layout-resolved Markdown assets and current lifecycle state; changed plugin payloads converge through existing sync, registry, marketplace, and test infrastructure. | Installed-consumer and generated-drift checks pass with no new schema, service, store, or architecture contract. `test:Cip.ConfirmedContextInstalledConsumers` `test:bundle-no-drift` `test:dogfood-no-drift` | 3.1, 3.2 |

## Evidence ownership

| Owner step | Evidence due at the step/phase crosscheck |
|---|---|
| 1.1 | `test:Cip.IntentConfirmationCheckpoints` |
| 1.2 | `test:Cip.IntentDesignConfirmationLifecycle` |
| 2.1 | `test:Cip.ConciseDesignFlow`, `review:dr` |
| 2.2 | `test:Cip.VerticalPlanObjectiveInvariants` |
| 3.1 | `test:Cip.ConfirmedContextInstalledConsumers`, generated payload parity |
| 3.2 | All required markers in the existing evidence receipt |
