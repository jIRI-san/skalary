# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | A selected artifact escapes its plan root or consumes unbounded memory. | Medium | High | Resolve through canonical plan/layout helpers, require regular confined files, and enforce per-file plus aggregate byte limits before returning content. | 1.1, 1.2, 3.1, 3.2 |
| RISK-2 | Historical content is mistaken for current authority or carries hostile instructions. | Medium | High | Return explicit source metadata, fence content as untrusted historical data, and preserve confirmed intent/contracts as authority. | 1.1, 1.2, 3.1, 3.2 |
| RISK-3 | Consumers record inconsistent or missing provenance. | Medium | Medium | Use one metadata shape and write it only to existing references or review scope through each consumer's current path. | 2.1, 2.2, 3.1, 3.2 |
| RISK-4 | Review integration accidentally creates a second review lifecycle. | Medium | High | Restrict integration to context resolution and review-scope metadata; leave Freeze, publication, verification, and retention to review-run v1. | 2.2, 3.1, 3.2 |
