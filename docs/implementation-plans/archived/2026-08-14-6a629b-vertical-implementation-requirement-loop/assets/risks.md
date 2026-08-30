# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Phase admission could disagree with the plan validator or mutate before discovering a blocker. | Medium | High | Use existing parsed metadata/state read-only before mutation and cover the same dependency/prerequisite cases. | 1.1, 3.1, 3.2 |
| RISK-2 | A phase could be promoted despite failed, stale, or unrun evidence. | Medium | High | Consume the truthful existing evidence result set and block on every unresolved non-pass/non-waived result. | 1.2, 2.2, 3.2 |
| RISK-3 | High-impact uncertainty could be buried in ordinary capture prose. | Medium | High | Classify by the confirmed contract/user/security/irreversibility boundary and require an explicit operator checkpoint. | 1.2, 2.1, 3.2 |
| RISK-4 | Stop/resume could duplicate work or diverge between interactive and autopilot paths. | Medium | High | Share admission/crosscheck behavior and resume from existing checklist progress; add interruption fixtures. | 2.2, 3.1, 3.2 |
| RISK-5 | Bundled workflow copies and generated catalogs could drift. | Medium | High | Use existing script bundling, dogfood sync, registry/catalog, and installed-consumer checks. | 3.1, 3.2 |
