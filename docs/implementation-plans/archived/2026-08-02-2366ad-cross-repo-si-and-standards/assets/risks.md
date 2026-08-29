# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Consumer-authored text carries prompt injection or secrets into the upstream session. | High | High | Bound and redact the typed export, preserve untrusted-input fencing, and re-judge every claim under upstream instructions. | 1.1, 1.2, 3.1, 3.2 |
| RISK-2 | The handoff edits installed consumer payloads or runs under consumer instructions instead of upstream rules. | Medium | High | Require a clean upstream checkout and load its repository instructions before invoking normal `/si` or `/cip`. | 1.2, 3.1, 3.2 |
| RISK-3 | Cross-repo transport accidentally gains publication or merge authority. | Low | Critical | Reuse normal upstream workflow controls; the transport only carries an artifact and `/si` remains draft-only and never-auto-merge. | 1.2, 3.1, 3.2 |
| RISK-4 | Repository-local standards silently replace generic safety rules or become a second review authority. | Medium | High | Resolve local input through the `79cfe1` source model with explicit precedence and keep review-run v1 authoritative. | 2.1, 2.2, 3.1, 3.2 |
| RISK-5 | Installed payloads or generated CR/DR agents drift from canonical sources. | Medium | High | Use existing generator and sync writers, then run installed-consumer, drift, structural-eval, and repository validation checks. | 1.1, 1.2, 2.1, 2.2, 3.1, 3.2 |
