# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | A consumer test passes by reading skalary's source tree or copying undeclared files. | High | High | Use the production installer, poison source paths, derive inventory from manifests, and require installed payload-load evidence. | 1.1, 1.2, 2.1, 3.1, 4.1 |
| RISK-2 | Static scanning misses a runtime-computed dependency or mistakes documentation for a runtime read. | Medium | High | Keep the supported grammar explicit, reject unsupported dynamic reads, and pair scanning with installed smokes. | 1.2, 3.1, 4.1 |
| RISK-3 | A representative smoke skips behavior, hangs, or touches network/credentials. | Medium | High | Require one manifest-derived result per active plugin, deterministic offline behavior, existing process controls, and no skipped success. | 2.1, 2.2, 3.1, 4.1 |
| RISK-4 | Fixture or scaffold mutation escapes its root or overwrites a modified consumer file. | Medium | High | Reuse existing confinement helpers and fixture cleanup, test hostile paths and modified targets, and fail before mutation. | 1.1, 2.2, 3.1, 4.1 |
| RISK-5 | Bundles, manifests, dogfood, marketplace, or registry drift from installed behavior. | High | High | Use existing sync/generator writers and finish with focused installed tests plus detect-only drift checks. | 1.1, 1.2, 2.1, 2.2, 3.1, 4.1 |
