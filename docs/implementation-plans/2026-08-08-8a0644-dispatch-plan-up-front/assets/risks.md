# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | The four-in-flight cap is copied into scheduler prose or code before its owner descriptor exists, creating another ungated limit and repeating the dropped Cluster C handoff. | Medium | High | Depend on `34088e`; use its owner-local descriptor discovery/parity contract; reject unregistered active literals and require receiving-side graph evidence. | 1.1+ |
