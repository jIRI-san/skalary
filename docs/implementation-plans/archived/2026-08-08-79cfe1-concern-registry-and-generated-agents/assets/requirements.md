# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | One validated concern registry and one shared template are the authoring source for the settled seven concerns, shared guidance, CR/DR variants, and concern-to-ledger mappings. | `test:ReviewConcerns.RegistryAndTemplate` · `review:cr` · `review:dr` | 1.1, 3.1 |
| REQ-2 | One deterministic generator produces all 14 model-agnostic CR/DR concern agents and both mapping views while preserving template-owned safety and explicit surface differences. | `test:ReviewConcerns.DeterministicGeneration` · `test:ReviewConcerns.GeneratedBehaviorAndDistribution` · `review:cr` · `review:dr` | 1.2, 2.1, 3.1 |
| REQ-3 | Generated agents and mappings are distributed through existing manifest, sync, version, dogfood, marketplace, and registry writers, and detect-only drift fails on any mismatch. | `test:ReviewConcerns.GeneratedBehaviorAndDistribution` · `test:ReviewConcerns.GenerationDrift` · `review:cr` · `review:dr` | 2.1, 2.2, 3.1 |
| REQ-4 | The seven-concern taxonomy, model binding, injection guards, read-only stance, review-run v1 authority, and existing validation infrastructure remain unchanged. | `test:ReviewConcerns.RegistryAndTemplate` · `test:ReviewConcerns.DeterministicGeneration` · `test:ReviewConcerns.GeneratedBehaviorAndDistribution` · `test:ReviewConcerns.GenerationDrift` · `review:cr` · `review:dr` | 1.1, 1.2, 2.1, 2.2, 3.1 |
