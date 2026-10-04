# Risks

<!-- For uncertain or high-impact work, the mitigation names the concrete stop/escalation condition. -->

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | The test host cannot create a file symlink, leaving the external-target write regression unproven. | Medium | High | Use an available capable non-elevated host; report capability failure explicitly and stop if none is available. Never count an unsupported fixture as a pass, elevate the coding app, or change host-wide settings for this test. | 1.1, 1.2 |
| RISK-2 | Attribute validation and later refresh are separate operations; a concurrent replacement could bypass the check. | Low | High | Retain the trusted single-operator point-in-time model without a lock. Revisit only if concurrent/untrusted mutation becomes part of the workflow. | 1.2 |
