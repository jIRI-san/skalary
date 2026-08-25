# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Step map authority |
|----|------|------------|--------|------------|-------|
| RISK-1 | A skill prints one plan but dispatches different or extra tasks. | Medium | High | Make the returned plan object the only source for wave admission and compare final attendance to it. | 1.1, 1.2, 4.2 (generated from `plan.md`) |
| RISK-2 | The UI implies control over provider-global concurrency that the orchestrator cannot observe. | Medium | High | Describe and test only the four-task per-run admission cap; label provider concurrency unobserved. | 1.2, 2.1, 2.2, 3.1, 4.2 (generated from `plan.md`) |
| RISK-3 | Ordinary failures are mistaken for throttling and trigger hidden extra calls. | Medium | High | Retry once only for an explicit host/tool throttle result and show the retry in attendance. | 1.2, 3.1, 4.2 (generated from `plan.md`) |
| RISK-4 | A failed prerequisite cancels unrelated work or allows a dependent task to run. | Medium | High | Use the declared dependency graph; cancel transitive dependents and continue independent ready tasks in stable order. | 1.1, 2.1, 2.2, 4.2 (generated from `plan.md`) |
| RISK-5 | Source skills, bundled copies, evals, or catalogs drift. | Medium | High | Use the repository's existing sync, version, registry, marketplace, installed-consumer, and eval checks. | 2.1, 2.2, 4.1, 4.2 (generated from `plan.md`) |
| RISK-6 | Shared attendance duplicates or changes review-run authority. | Medium | High | Adapt frozen review tasks into the planner, then return outcomes to the unchanged review-run publish path. | 3.1, 3.2, 4.2 (generated from `plan.md`) |