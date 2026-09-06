# Decisions

Confirmed on 2026-09-06 against the final dependency outputs.

- **New child, not another responsibility inside workflow or plugin lifecycle.** Configuration crosses
  every plugin and depends on final subsystem surfaces; it owns only the façade and catalog.
- **One guided entry point plus direct subcommands.** Support `/skalary-config`, `show`, `bootstrap`,
  `edit`, `validate`, `diff`, `apply`, and per-key `reset`.
- **No general central configuration file or service.** Existing subsystem files remain authoritative;
  the accepted exception is `tools/model-allowlist.psd1`, the one canonical model alias map.
- **Canonical-source writes only.** Generated/dogfood/catalog outputs change through existing
  synchronizers.
- **One proposal and one Apply/Cancel gate.** Read-only discovery precedes every mutation; the operator
  sees the full diff, risks, required synchronization, and focused checks.
- **Transient stale-preview guard, not proposal state.** Preview computes an in-memory digest of the
  canonical inputs; Apply rechecks it and refuses changes rather than persisting a proposal or merging
  concurrent edits.
- **Closed local adapter, not a framework.** The skill-local scripts accept one known category and known
  keys, with fixed canonical paths and category-specific handlers. They do not interpret the Markdown
  catalog as executable policy or accept arbitrary write paths.
- **Bootstrap is selected and lazy.** Missing optional files are created only for the chosen surface.
- **Reset is narrow.** Derive current defaults from shipped examples and preserve unknown fields and
  unrelated settings.
- **Two audience levels.** Normal project/operator settings are guided; manifests, allowlists, eval pins,
  and toolchains are clearly labeled advanced maintainer policy.
- **Model routing is a first-class normal category.** Show and edit the stable
  `primary-model-low|mid|high` and `secondary-model-low|mid|high` host bindings, role assignments, reasoning
  efforts, autopilot defaults, CR/DR routing, and waza executor/judge bindings. Context is separate:
  shipped settings use `default`, while `long_context` remains explicit opt-in.
- **One alias proposal updates one authority.** The façade edits `tools/model-allowlist.psd1`, then runs
  `Sync-ModelBindings.ps1` and existing distribution synchronization. Concrete host identifiers in waza
  specs and installed skill assets are generated bindings, not independent policy.
- **Model reset follows delivered aliases.** Per-role reset restores the shipped six-alias map and
  `default` context. It may accept `long_context` only as an explicit operator choice with its cost shown.
- **Secrets are availability-only.** Never read values into the model or write credential material.
- **Secret creation stays outside the agent session.** For autopilot, print conditional official
  acquisition links, required permissions, and placeholder-only storage/login commands; pause while the
  operator performs them in a separate shell; resume only when they select Ready to validate.
- **Validation wraps existing probes.** Add only a secret-safe installed boundary that retrieves the
  selected credential and invokes the existing auth validator internally. Return sanitized
  availability/capability results and remediation; never put a token in a tool argument or output.
- **Executable configuration gets extra confirmation.** Autopilot build/test/host command and container
  extension values are never silently created or applied.
- **Defer exact catalog rows until dependencies land.** Do not preserve configuration adapters for
  review, SI, or plugin machinery that those children removed.
- **Failure is visible, not transactional.** Apply stops on the first failed write, synchronizer, or
  validator and prints the remaining Git diff plus the exact direct recovery command. It adds no
  rollback, journal, backup, or retry service.
