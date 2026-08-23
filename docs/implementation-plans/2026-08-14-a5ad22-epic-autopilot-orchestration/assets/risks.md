# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Resume state could select a stale child or target. | Medium | High | Store only the current run coordinates, compare target on resume, and refresh `Get-PlanState` before every new selection. | 1.1, 2.2, 3.2 |
| RISK-2 | The host loop could bypass child isolation or launch multiple children. | Medium | High | Delegate to the existing per-plan launcher, keep one `currentChild`, and refuse selection while a run is active or awaiting merge. | 1.2, 2.1, 3.2 |
| RISK-3 | The target or dependency graph could change between child completion and merge. | Medium | High | Stop for operator merge, then fetch/refresh target and recompute the epic rollup before continuing. | 2.1, 2.2, 3.2 |
| RISK-4 | Failure or degraded evidence could be mistaken for completion and skipped. | Medium | High | Verify existing terminal outputs and retain explicit outcome for operator resume; never advance on non-success. | 1.2, 2.1, 2.2, 3.2 |
| RISK-5 | Final coherency could grow into another delivery-audit platform. | Medium | Medium | Invoke simplified `25aa23` when available or a direct intent/done crosscheck; record existing evidence and create no finalization PR or concern family. | 3.1, 3.2 |
