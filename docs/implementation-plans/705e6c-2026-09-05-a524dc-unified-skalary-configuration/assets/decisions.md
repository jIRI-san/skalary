# Decisions

Preliminary decisions accepted during epic refinement; `/cip` must reconfirm them against the final
dependency outputs.

- **New child, not another responsibility inside workflow or plugin lifecycle.** Configuration crosses
  every plugin and depends on final subsystem surfaces; it owns only the façade and catalog.
- **One guided entry point plus direct subcommands.** Support `/skalary-config`, `show`, `bootstrap`,
  `edit`, `validate`, `diff`, `apply`, and per-key `reset`.
- **No central configuration file or service.** Existing subsystem files remain authoritative.
- **Canonical-source writes only.** Generated/dogfood/catalog outputs change through existing
  synchronizers.
- **One proposal and one Apply/Cancel gate.** Read-only discovery precedes every mutation; the operator
  sees the full diff, risks, required synchronization, and focused checks.
- **Bootstrap is selected and lazy.** Missing optional files are created only for the chosen surface.
- **Reset is narrow.** Derive current defaults from shipped examples and preserve unknown fields and
  unrelated settings.
- **Two audience levels.** Normal project/operator settings are guided; manifests, allowlists, eval pins,
  and toolchains are clearly labeled advanced maintainer policy.
- **Model routing is a first-class normal category.** Show and edit every role assignment from `33a78a`:
  Luna routine, Terra standard, Sol deep, Opus independent, all replacement fallbacks and reasoning
  efforts, the default-context-only rule, autopilot defaults, CR/DR routing, and waza executor/judge
  bindings. The underlying host allowlists remain advanced.
- **One model proposal may update several authorities.** The façade groups the category for the operator,
  but writes each owning canonical skill, agent, config example, allowlist, or eval spec and then invokes
  existing synchronization. It does not create a consolidated model-policy file.
- **Model reset follows delivered defaults.** Per-role reset derives from `33a78a`'s shipped canonical
  defaults, and retired `long_context` values are refused rather than restored.
- **Secrets are availability-only.** Never read values into the model or write credential material.
- **Executable configuration gets extra confirmation.** Autopilot build/test/host command and container
  extension values are never silently created or applied.
- **Defer exact catalog rows until dependencies land.** Do not preserve configuration adapters for
  review, SI, or plugin machinery that those children remove.
