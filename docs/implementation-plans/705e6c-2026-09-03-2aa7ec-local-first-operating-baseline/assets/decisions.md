# Decisions

Preliminary context captured by /cep; /cip must confirm and refine it.

- **Simplicity is the first rule.** Prefer deletion, direct scripts, and local fixes. When simple and
  safe cannot both be achieved within this trusted single-operator repository, choose the simple
  design and record the tradeoff in the affected design note.
- **No GitHub workflows.** Remove them and their workflow-only support. Do not replace them with
  another hosted pipeline.
- **Whole-suite execution is explicit-only.** Skills and routine scripts must use the smallest
  affected-plugin subset. Only the operator may select the separate full-repository path.
- **Focused timing contract.** Target under 30 seconds per selected command and return a distinct
  timeout result above 60 seconds; do not create an aggregate suite gate.
- **Tests require user value.** Keep only deterministic coverage of current behavior, required
  external formats, or high-impact regressions. Ask the operator about uncertain rows.
- **One temporary ownership inventory.** It classifies all active JSON, gates, tests, notes, and
  contracts once; each child closes its assigned rows. The inventory is planning evidence, not a new
  runtime authority.
- **Internal formats use strict Markdown.** Keep JSON only where an external consumer requires it.
  Do not add schemas or migrations for retired internal formats.
- **Direct stable scripts.** Read-only and focused scripts may be pre-approved by exact path.
  Mutating scripts remain explicit. Avoid operator-facing module-loading chains and hooks.
- **Cross-host choices are equivalent, not abstracted.** Use native VS Code pickers and a numbered or
  chat CLI equivalent, both with enough context and effort/complexity scores.
- **Bounded prior context.** Reuse the existing bounded artifact adapter instead of creating another
  history service. Current intent and active contracts outrank explicit supersession, which outranks
  older accepted decisions; unresolved conflicts are shown.
- **Cost budgets are operator decisions.** Produce a short RFC, then apply the selected budgets in
  consumer children without adding a policy engine.
- **Rejected:** mandatory CI, Fast/Slow tier machinery, receipt authority, exhaustive review
  matrices, compatibility layers, and reviewer requests to restore platform-scale controls.
- **Unresolved for `/cip`:** exact focused command names and the concrete budget options to present
  to the operator.
