# References

## Epic and dependencies

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `367e9a` for final review/model/autopilot configuration.
- Depends on `33a78a` for the final default-context, model-routing, and AI-credit guidance surfaces.
- Depends on `3a4498` for final SI/PFB surfaces and runtime-state exclusions.
- Depends on `623cc2` for final manifest/catalog/lifecycle synchronization.

## Preliminary configuration inventory

| Surface | Current canonical source or owner |
|---|---|
| Autopilot project/runtime | `.autopilot.json`, plugin examples/schemas, autopilot launcher |
| Models/review | All `33a78a` routine/standard/deep/independent primaries, replacement fallbacks, reasoning efforts, default-context-only policy, autopilot default, CR/DR routing, and waza executor/judge assignments across their canonical skills, agents, configs, allowlists, and eval specs |
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
