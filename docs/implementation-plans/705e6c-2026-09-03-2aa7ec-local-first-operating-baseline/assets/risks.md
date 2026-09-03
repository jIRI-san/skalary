# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Value-bearing coverage is deleted during pruning. | Medium | High | Require a stated value for every keep row and one operator gate for every uncertain row before deletion. | 1.1, 1.2, 2.1 |
| RISK-2 | A retained workflow gate disappears without a local owner. | Medium | High | Inventory each workflow invocation first, mark it keep/transfer/delete, and update directly invalidated notes/contracts in the same step as workflow deletion. | 1.1, 1.3, 2.3 |
| RISK-3 | A focused timeout leaves child processes running on Windows or Linux. | Medium | Medium | Bind one wall-clock timer to the directly launched child tree, terminate by concrete PID at 60 seconds, return exit `13`, and keep one focused cross-platform test seam; add no recovery service. | 1.3 |
| RISK-4 | Internal/external JSON classification breaks an ecosystem consumer. | Medium | High | Every keep row names the external consumer; update each changed producer/consumer together; bind transfer rows to one canonical child ID. | 1.1, 2.2 |
| RISK-5 | Repository-wide inventory work expands into a permanent policy system or final sweep. | Medium | Medium | Keep `assets/ownership.md` plan-local, bounded to active paths, and close every baseline row in the owning implementation step. | 1.1, 2.1, 2.2, 3.3 |
| RISK-6 | Cost guidance becomes another enforcement framework. | Medium | Medium | Keep the RFC advisory and prove consumer behavior with small focused fixtures only; prohibit a runtime budget service. | 3.1, 3.3 |
