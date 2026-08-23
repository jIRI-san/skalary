# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Model- or operator-authored learning and SI text is later read as trusted instruction. | Medium | High | Preserve the existing `/si` untrusted-input wrappers and sanitize through existing script-owned writers; include hostile stored text in focused tests. | 1.1, 2.2, 4.1 |
| RISK-2 | A non-blocking headless due write fails while completion appears fully successful. | Medium | High | Return and render an explicit degraded result while keeping the plan completion non-blocking; test the failure path. | 2.1, 2.2, 4.1 |
| RISK-3 | Replay or interruption creates duplicate dues or loses an operator outcome. | Medium | High | Stable due identity, append-only records, and the existing lock/temp/atomic-replace pattern; test replay and interruption. | 2.1, 2.2, 4.1 |
| RISK-4 | A new writer or phase hook works only in the source repo or drifts from generated plugin artifacts. | Medium | High | Use existing layout, ledger, plugin sync, version, registry, marketplace, and dogfood writers; run installed-fixture and drift checks. | 1.1, 2.1, 3.1, 4.1 |
