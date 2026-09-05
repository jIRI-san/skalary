# Domain Model

Preliminary context captured by /cep; /cip must confirm and refine it.

## Terms and meanings

- **Focused scope:** explicit repository-relative test paths, plugin IDs, or validation paths selected
  because the current change affects them.
- **Full-repository run:** an intentionally broad local command selected only through
  `-FullRepository`; never a routine default or skill-selected fallback.
- **Deterministic command:** local unit, structural-eval, or validation work covered by the
  30/60-second contract. Premium Waza/LLM evals are not deterministic commands.
- **External-required JSON:** JSON whose shape is consumed by Copilot, VS Code/devcontainers, plugin
  catalogs/manifests, or another named external tool.
- **Internal operational artifact:** repository-owned state, evidence, review, inventory, or
  configuration that can use strict Markdown without breaking an external interface.
- **Ownership row:** one temporary planning record assigning an active gate, JSON path, test, note, or
  architecture contract to exactly one child and one `keep`, `transfer`, `delete`, or `uncertain`
  disposition.
- **Uncertain test:** a test whose current user value cannot be established from behavior, external
  format, or high-impact regression evidence; only the operator chooses its disposition.

## Actors and boundaries

- **Operator:** the single trusted repository owner who may explicitly request broad or premium work.
- **Routine agent:** a VS Code or Copilot CLI agent performing one bounded repository task.
- `2aa7ec local-first-operating-baseline` owns shared local execution rules, workflow removal,
  repository-wide classification, unaffected-plugin cleanup, and the agent-cost RFC.
- `367e9a simple-review-to-plan-workflow`, `3a4498 simple-self-improvement`, and
  `623cc2 simple-plugin-lifecycle` own their assigned subsystem formats, docs, scripts, and tests.
- `Run-UnitTests.ps1`, `Test-Evals.ps1`, `Invoke-WazaEvals.ps1`, and `validate.ps1` remain direct
  entry points; this plan adds no `focus-*` wrapper.

## Invariants

- No GitHub workflow or ordinary package/skill command executes hosted or full-repository validation.
- Missing, invalid, conflicting, or implicit focused scope fails before execution.
- A focused command targets under 30 seconds, warns between 30 and 60 seconds, and terminates with a
  distinct timeout result above 60 seconds; it never retries or widens scope automatically.
- Every ownership row has exactly one child owner. The inventory is planning evidence, not runtime
  state or a new policy authority.
- Internal operational formats use strict Markdown. JSON remains only with a named external consumer.
- VS Code and Copilot CLI choices carry equivalent decision context, including effort and complexity.
- Current intent and active contracts outrank historical context; the existing bounded artifact
  adapter is the only historical-plan reader.
