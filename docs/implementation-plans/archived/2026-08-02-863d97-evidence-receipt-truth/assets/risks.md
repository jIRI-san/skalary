# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Skip, not-run, stale, discovery, or interruption states collapse into a passed/failed boolean. | High | High | Preserve explicit outcomes from the current runner/verifiers through aggregation and rendering; test every listed state. | 1.1, 2.1, 2.2, 4.1 |
| RISK-2 | A broad, stale, or wrong-platform waiver turns absent proof into success. | Medium | High | Bind exact plan/REQ/marker/outcome and optional platform; reject wildcards and waivers for failed, unrun, or stale evidence. | 1.2, 2.2, 4.1 |
| RISK-3 | Selected and executed focused tests differ, but partial output is accepted. | Medium | High | Emit structured selected/executed counts and outcomes through the existing runner; incomplete execution remains unrun/degraded and blocks. | 1.1, 2.1, 2.2, 4.1 |
| RISK-4 | Formatter and finalization interpret the same result differently. | Medium | High | Normalize once into shared result objects, keep the formatter format-only, and test receipt text and PlanCrosscheck from the same fixtures. | 1.1, 1.2, 2.2, 3.1, 4.1 |
| RISK-5 | Canonical, bundled, and dogfood evidence consumers drift. | High | High | Use existing sync/version/registry writers and installed parity plus structural drift tests. | 2.1, 2.2, 3.1, 4.1 |
