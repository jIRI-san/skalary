# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Normalizing CRLF could hide unrelated content changes. | Medium | High | Normalize only for byte comparison; keep exact Git path-set validation and canonical LF writes. | 1.1, 1.2 |
| RISK-2 | Windows path/status repair could broaden residue admission. | Medium | High | Parse repository-relative Git output and require the sole exact Capture path and permitted staged/unstaged state. | 1.1, 1.2 |
| RISK-3 | Repair work could rewrite wrapped review history or imply clean final evidence. | Low | High | Use a separate plan and assert the existing final Wrap record remains present; do not run another `a5ad22` review. | 1.2 |
