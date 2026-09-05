# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | The façade becomes a second source of truth or generic configuration framework. | Medium | High | Catalog points to subsystem authorities; reuse their examples, writers, synchronizers, and validators; add no replacement schema/store. | TBD |
| RISK-2 | Editing generated or dogfood files creates drift that later sync overwrites. | High | High | Classify canonical/default/generated paths; write canonical sources only; run required synchronizers before reporting success. | TBD |
| RISK-3 | Secret values enter prompts, diffs, or committed files. | Medium | High | Report credential-source availability only; refuse value display/edit; route setup to approved external auth flows. | TBD |
| RISK-4 | Executable autopilot settings enable unsafe commands. | Medium | High | Reuse subsystem validation, show command effects, require explicit confirmation, and never auto-create host-command or extension values. | TBD |
| RISK-5 | The skill freezes transitional formats scheduled for deletion. | High | Medium | Depend on all three subsystem children and regenerate the inventory after they land; add no compatibility adapters. | TBD |
| RISK-6 | A broad Apply partially synchronizes derived outputs. | Medium | Medium | Keep proposals category-bounded; sequence canonical edit then existing synchronizers and focused checks; surface failure without claiming rollback or success. | TBD |
| RISK-7 | Advanced maintainer controls overwhelm routine configuration. | Medium | Medium | Separate normal and advanced menus; include examples, benefits, risks, effort, and complexity; default to routine project settings. | TBD |
| RISK-8 | A model edit changes one role source but leaves fallbacks, evals, allowlists, or dogfood copies inconsistent. | High | High | Treat model routing as one category-scoped proposal, enumerate every `33a78a` canonical source and consumer, run existing synchronizers, and fail visibly on any focused model-contract or consumer-install check. | TBD |
| RISK-9 | The façade reintroduces long context or an expensive model as an accidental routine default. | Medium | High | Derive valid options and defaults from delivered `33a78a` sources, refuse retired context values and invalid role/fallback combinations, and show estimated relative cost before Apply. | TBD |
