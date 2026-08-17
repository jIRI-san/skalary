# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | A semantic merge repair hides unrelated behavior loss. | Medium | High | Reuse exact source-branch records, run focused owners, then run both complete tiers. | 1.1, 2.2, 3.1 |
| RISK-2 | A test falls into neither tier or runs twice. | Medium | High | One tracked manifest plus a structural complete/disjoint partition test over discovered files. | 1.2, 2.1, 3.1 |
| RISK-3 | Slow execution bypasses cannot-test, leak, or evidence checks. | Medium | High | Both tiers execute through the same runner and differ only in selected paths and budget applicability. | 1.2, 2.2, 3.1 |
| RISK-4 | CI exposes a slow command but does not require or attribute it. | Medium | High | Separate blocking workflow step, separate NUnit path, inventory row, and workflow structural tests. | 2.1, 2.2, 3.1 |
