# References

Design notes consulted while drafting and executing this plan:

- `docs/design-notes/architecture/plan-workflow.design.md` — plan validator stages, typed evidence contract, plan naming/id scheme, ledger contracts.
- `docs/design-notes/project/copilot-customizations.design.md` — customization inventory, cr/dr review agents, cip/ci workflow skills.
- `docs/design-notes/architecture/plugin-registry.design.md` — plugin manifests, registry generation, installer confinement model.
- `docs/design-notes/architecture/architecture-notes.design.md` — ADR harvest from plan decision records.
- `docs/design-notes/architecture/autopilot-execution.design.md` — autopilot model binding and `.autopilot.json` contract.

Prior plans whose decisions this plan builds on:

- `archived/006-plan-workflow-hardening` — typed evidence vocabulary and validator staging.
- `archived/2026-06-27-7645b1-optimize-ci-cip-plugins` — `PlanState` module, skill/asset split, anti-drift contract.
- `archived/2026-07-04-9fc66d-plugin-manager` — plugin install surfaces and script-approval model.

Extended per-topic rationale for this plan lives in `assets/decisions/`.
