# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Confirmation can become stale after intent or design changes. | Medium | High | Invalidate the single lifecycle-owned confirmation marker on either asset change and require the affected checkpoint again. | 1.1, 1.2, 2.1, 3.2 |
| RISK-2 | Interactive and headless consumers could disagree about whether planning is confirmed. | Medium | High | Read the same lifecycle marker and layout-resolved assets through current plan state; headless execution stops for the operator when confirmation is pending. | 1.2, 3.1, 3.2 |
| RISK-3 | The interview or design package could become burdensome or substitute diagrams for complete requirements. | Medium | Medium | Keep three checkpoints, concise Mermaid output, optional call stacks, and objective requirement routing; retain operator judgment for semantic usability. | 1.1, 2.1, 2.2, 3.2 |
| RISK-4 | Bundled workflow copies or generated catalogs could drift from source. | Medium | High | Use existing plugin generators, sync writers, registry/catalog builders, and focused installed-consumer drift checks. | 3.1, 3.2 |
