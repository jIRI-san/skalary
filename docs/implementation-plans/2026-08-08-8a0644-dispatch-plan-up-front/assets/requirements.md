# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Define the real four-in-flight scheduler cap in an owner-local machine descriptor using the `skalary/workflow-limits@1` contract delivered by `34088e`; every active guide, dispatch input, and runtime admission consumer derives from or is parity-bound to that owner. | Resolver-backed graph evidence proves `8a0644 -> 34088e`; this plan's real descriptor, admission consumers, owner mutation, and copied-cap refusal pass independently of 34088e's synthetic handoff fixture. `test:WorkflowLimits.FleetConsumerHandoff` · `test:Epic.WorkflowLimitsDependencyState` · `test:FleetScheduler.WorkflowLimitOwnerParity` | 1.1+ |
