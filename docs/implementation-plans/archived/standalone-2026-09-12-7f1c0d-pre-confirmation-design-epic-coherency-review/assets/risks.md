# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | DR proposes architectural machinery disproportionate to the plan. | High | High | Keep review advisory; require `primary-model-high` to apply current project context and Simplicity First; let the operator select changes. | 1.1, 1.2, 2.2, 3.1 |
| RISK-2 | Mandatory premium calls make planning slow or expensive. | Medium | Medium | Use one combined reviewer call and one evaluator call, no automatic rerun, panel, or fallback fleet; keep prompts and context bounded. | 1.1, 2.1, 2.2 |
| RISK-3 | Epic context grows without bound across many sibling plans. | Medium | High | Read epic intent and targeted sibling outcomes/interfaces/dependencies/decisions only; inspect current code only for relevant completed work. | 2.1, 3.1 |
| RISK-4 | Planning mode weakens DR safety or changes standalone `/dr` unexpectedly. | Low | High | Preserve read-only, prompt-injection, secret, confinement, and proportional-security guards; scope routing changes to the explicit planning caller. | 1.2, 2.1, 3.2 |
| RISK-5 | The evaluator hides findings it considers irrelevant. | Medium | High | Require all findings to remain visible while recommendations are presented separately. | 1.1, 2.2 |
| RISK-6 | Implementation recreates retired tickets, receipts, hashes, verdicts, or review validation. | Medium | High | State explicit non-goals in skills, docs, and tests; reuse only the existing planning confirmation and distribution machinery. | 1.1, 1.2, 2.2, 3.1, 3.2 |
| RISK-7 | Epic review trusts stale completed-plan prose and misses conflict with delivered behavior. | Medium | High | For relevant completed siblings, compare the proposed interface or assumption with targeted current code/contracts; stop when compatibility cannot be established cheaply. | 2.1, 3.2 |
