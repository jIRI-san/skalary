# References

## Epic and dependencies

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `367e9a` for final review/model/autopilot configuration.
- Depends on `33a78a` for the default-first context, model-alias, and AI-credit guidance surfaces.
- Depends on `3a4498` for final SI/PFB surfaces and runtime-state exclusions.
- Depends on `623cc2` for final manifest/catalog/lifecycle synchronization.

## Preliminary configuration inventory

| Surface | Current canonical source or owner |
|---|---|
| AI-credit budget and routing policy | `docs/design-notes/explorations/agent-cost-optimization.design.md`; 180K operating, 20K reserve, dated official pricing and workflow links |
| Model aliases and roles | `tools/model-allowlist.psd1`; six stable primary/alternate low/mid/high aliases, host bindings, role assignments, fallbacks, and reasoning effort |
| Generated model bindings | `scripts/skalary/Sync-ModelBindings.ps1`; copied per-skill maps and concrete waza executor/judge identifiers |
| Autopilot project/runtime | `.autopilot.json`, `plugins/autopilot/.autopilot.json.example`, schema and launchers; `primary-model-mid`/medium/default shipped, `long_context` opt-in |
| Workflow model roles | Canonical `autopilot`, `cep`, `cip`, `ci`, `cr`, and `dr` skills use aliases only |
| Review agent bindings | `plugins/{code-review,design-review}/agents/*.agent.md` plus alias map; host-qualified names remain runtime-only |
| Eval model bindings | Generated `plugins/*/evals/waza/eval.yaml` and task pins; `primary-model-low` executor, `primary-model-mid` judge only for subjective tasks |
| Model consumers and validation | `.github/**` dogfood copies, `tests/skalary/AiCreditBudget.Tests.ps1`, `tests/skalary/ModelAllowlist.Tests.ps1`, and `tests/evals/WazaCreditPolicy.Tests.ps1` |
| Local review policy | Optional `docs/review-standards.md` |
| Terminal approvals | `.vscode/settings.json` through `scripts/skalary/Set-ScriptApproval.ps1` |
| Evals | Per-plugin `evals/waza/eval.yaml`, optional `.eval.config.json` credential targets, `tools/eval-tools.psd1` advanced pins |
| Design/architecture | `docs/design-notes/**`, `docs/architecture-notes/**`, owning scaffold/update skills |
| Plugin distribution | `plugins/*/plugin.json`; generated `registry.json`, marketplace, README, and dogfood copies |
| Repository/toolchain | `.github/copilot-instructions.md`, package aliases, container/toolchain policy |

The detailed `/cip` inventory must be regenerated after all dependencies complete. Current duplicates
and transitional review/Fleet settings are evidence for simplification, not compatibility requirements.

## Epic discussion provenance

On 2026-09-05 the operator asked for one `/skalary-config` skill that collects configuration across all
plugins/skills, guides bootstrap and edits, and manages examples such as model assignments and autopilot
settings. They later clarified that every model assignment delivered by `33a78a` must be covered. The
operator approved a separate child depending on `367e9a`, `33a78a`, `3a4498`, and `623cc2`, with no new
central configuration service.
