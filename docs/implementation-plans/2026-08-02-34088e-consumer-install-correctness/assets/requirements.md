# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | A manifest-derived foreign-repository fixture uses the production installer and verifies installed inventory, hashes, dependencies, and confinement without copying source wildcards. | `test:ConsumerInstall.ForeignFixtureInventory` · `review:cr` | 1.1, 3.1, 4.1 |
| REQ-2 | The runtime-reference scan rejects source-tree fallbacks and undeclared assets while recognizing installed, bundled, and first-use scaffold paths. | `test:ConsumerInstall.RuntimeReferenceClosure` · `review:cr` | 1.2, 3.1, 4.1 |
| REQ-3 | Every active plugin, derived from current manifests, has one representative installed smoke that loads its payload and exercises behavior or an exact offline preflight. | `test:ConsumerInstall.ActivePluginSmokeMatrix` · `review:cr` | 2.1, 3.1, 4.1 |
| REQ-4 | Every declared first-use scaffold owner is executed in the foreign fixture and preserves installer confinement, idempotence, and modified consumer files. | `test:ConsumerInstall.FirstUseScaffoldLifecycle` · `review:cr` | 2.2, 3.1, 4.1 |
| REQ-5 | Existing plugin sync, version, registry, marketplace, dogfood, structural-eval, and repository validation paths remain the distribution and drift authority. | `test:ConsumerInstall.ForeignFixtureInventory` · `test:ConsumerInstall.RuntimeReferenceClosure` · `test:ConsumerInstall.ActivePluginSmokeMatrix` · `test:ConsumerInstall.FirstUseScaffoldLifecycle` · `test:ConsumerInstall.DistributionDrift` · `review:cr` | 1.1, 1.2, 2.1, 2.2, 3.1, 4.1 |
