# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | A registry/template defect weakens all generated concern agents at once. | Medium | High | Keep safety structure template-owned, validate registry substitutions, and test every generated agent and mapping. | 1.1, 1.2, 2.1, 3.1 |
| RISK-2 | Generation overwrites an unmanaged path or produces nondeterministic bytes. | Low | High | Confine the generator to declared outputs, validate/render before writes, use ordinal ordering, support `-WhatIf`, and prove a clean second pass. | 1.1, 1.2, 2.2, 3.1 |
| RISK-3 | Agents regenerate while manifests, versions, dogfood, marketplace, or registry remain stale. | Medium | High | Run existing owning writers in order and make one drift test cover generated and distributed outputs. | 2.1, 2.2, 3.1 |
| RISK-4 | Centralization changes the settled taxonomy, model binding, review behavior, or review-run authority. | Low | High | Pin the seven ids independently, compare generated behavior, and keep review-run v1 and orchestrator model binding unchanged. | 1.1, 1.2, 2.1, 2.2, 3.1 |
