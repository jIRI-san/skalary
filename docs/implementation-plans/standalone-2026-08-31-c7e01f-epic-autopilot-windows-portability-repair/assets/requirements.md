# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Final crosscheck and no-checkpoint publication are line-ending-neutral while retaining canonical LF evidence and exact Capture-only mutation. | `test:EpicAutopilot.FinalCrosscheck` `test:EpicAutopilot.NoCheckpointProductionFinalization` | 1.1, 1.2 |
| REQ-2 | Interrupted-evidence recovery handles Windows path/status output and missing state deterministically, admitting only exact staged or unstaged Capture residue. | `test:EpicAutopilot.AbruptEvidenceRecovery` | 1.1, 1.2 |
| REQ-3 | Canonical/plugin/dogfood copies converge and the existing `a5ad22` final Wrap remains append-only with no new review, PlanCrosscheck, archive, or DONE claim. | `test:bundle-no-drift` `test:dogfood-no-drift` `file:docs/implementation-plans/2026-08-14-a5ad22-epic-autopilot-orchestration/assets/logs/cr-log.md#contains:review-cycle-decision stage=plan-finalization after=4 action=wrap` | 1.2 |
