# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Apply could mutate a different action set than the operator reviewed. | Medium | High | Bind confirmation to the current deterministic dry-run actions and refresh remote state immediately before writes. | 1.2, 2.2, 3.1, 3.2 |
| RISK-2 | Synchronization could overwrite human edits or silently adopt the wrong remote item. | Medium | High | Manage explicit marker regions, require stable mappings or explicit adoption, and refuse ambiguity/conflicts. | 1.2, 2.1, 2.2, 3.1, 3.2 |
| RISK-3 | Missing or stale mappings could create duplicate issues. | Medium | High | Key one mapping file by canonical local IDs, validate remote identity, and fail closed before create/update. | 1.1, 2.1, 2.2, 3.1, 3.2 |
| RISK-4 | `gh` failures or untrusted remote text could cause partial or unsafe continuation. | Medium | High | Keep remote data inert, use bounded adapter results, stop on failure, and require a fresh dry run before retry. | 1.2, 2.2, 3.1, 3.2 |
| RISK-5 | A future-provider seam could expand into a speculative provider platform. | Medium | Medium | Keep a narrow interface proven by the GitHub adapter only; defer Azure DevOps code, capability publication, and compatibility layers. | 1.1, 3.1, 3.2 |
