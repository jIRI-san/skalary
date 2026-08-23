# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Consumer `/si` exports one bounded typed artifact from durable local learning records, with source identity, provenance, redaction, replay safety, and untrusted-input fencing. | `test:CrossRepoSi.ExportBoundsRedactionAndReplay` · `review:cr` | 1.1, 3.1, 3.2 |
| REQ-2 | Proposal work occurs in a clean upstream checkout governed by upstream instructions and invokes normal upstream `/si` or `/cip`; installed consumer copies are never edited as source and `/si` never merges. | `test:CrossRepoSi.CleanUpstreamHandoff` · `review:cr` | 1.2, 3.1, 3.2 |
| REQ-3 | Generic review standards use the `79cfe1` source model; an optional repo-owned `docs/review-standards.md` is bounded, validated, and resolved without installer ownership. | `test:ReviewStandards.GenericLocalResolution` · `test:ReviewStandards.InstalledConsumptionAndDrift` · `review:cr` | 2.1, 2.2, 3.1, 3.2 |
| REQ-4 | Resolved standards feed existing CR/DR dispatch while review-run v1 remains the publication and evidence authority. | `test:ReviewStandards.InstalledConsumptionAndDrift` · `review:cr` | 2.2, 3.1, 3.2 |
| REQ-5 | Existing plugin sync, version, registry, marketplace, dogfood, test, and validation infrastructure distributes and verifies both features. | `test:CrossRepoSi.ExportBoundsRedactionAndReplay` · `test:CrossRepoSi.CleanUpstreamHandoff` · `test:ReviewStandards.GenericLocalResolution` · `test:ReviewStandards.InstalledConsumptionAndDrift` · `test:validate-all` · `review:cr` | 1.1, 1.2, 2.1, 2.2, 3.1, 3.2 |
