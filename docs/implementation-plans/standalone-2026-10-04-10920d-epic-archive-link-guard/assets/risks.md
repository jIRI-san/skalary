# Risks

<!-- For uncertain or high-impact work, the mitigation names the concrete stop/escalation condition. -->

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | The test host cannot create a file symlink, leaving the external-target write regression unproven. | Medium | High | Require the test to fail visibly if its required link cannot be created; run on a link-capable host before claiming REQ-1 verified. | 1.1, 1.2 |
| RISK-2 | A recursive preflight descends through a linked directory before detecting it. | Low | High | Check each entry for link/reparse attributes before adding any directory to the traversal; include a junction/symlink fixture whose external target remains unchanged. | 1.1, 1.2 |
