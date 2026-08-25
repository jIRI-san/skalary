# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08). Two of its
constraints have no counterpart here: one registry is the single source of truth for the concern
list, and concern bodies are authored once with per-surface variants **generated at sync time so
the surfaces cannot drift**.

## Epic discussion provenance

- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 90-92 (2026-08-08): the operator supplied a parallel implementation description, then selected the highest-value missing ideas for separate epic children.
- The accepted grouping combines "one concern registry" with "generated per-surface agent variants" because a registry that drives nothing is another copy rather than a source of truth.
- Epic `33b1f9` non-goal keeps the existing seven-concern taxonomy closed.

## The gap

**Concern list is authored in several places.** It appears in the `DispatchGuide.Tests.ps1` test
array (L16–L22), the `dispatch-guide.md` table (L8–L16), and the `concern-ledger-map.md` table
(L5–L13), and is implied a fourth time by which `*.agent.md` files exist. Tests cross-check these,
so drift is *detected* — but adding or renaming a concern still means editing several files and
trusting the tests to have covered every one.

**Agent bodies are hand-maintained per surface.** `plugins/code-review/agents/cr-security.agent.md`
is 4076 chars; `plugins/design-review/agents/dr-security.agent.md` is 3982 — not identical, and
nothing generates one from the other. Fourteen bodies across two surfaces are hand-edited, so a
scope improvement to `cr-security` does not reach `dr-security`.

What *is* gated: `tests/skalary/DispatchGuide.Tests.ps1` L38 requires the shared guide be
byte-identical across both plugins, and `tests/skalary/ConcernAgents.Tests.ps1` requires all seven
concerns per review type plus an injection guard and read-only stance on every agent. The parts
someone thought to check are enforced; the bodies are not.

## Scope caution

Epic `33b1f9` lists a non-goal: *"Re-opening the review concern taxonomy — `b0c0d3` settled it."*
This plan must not change **which** concerns exist or what they mean. It changes only **where the
list is authored** and **how agent bodies are produced**. If drafting starts proposing taxonomy
changes, that is out of scope and the epic's non-goal governs.

## Prior art

- [2026-08-22 simplification review](../../epics/2026-08-22-plan-simplification-review.md) — approved one registry, deterministic generator, generated agents/mappings, and a drift test while rejecting generated-inventory, migration, transaction, and dogfood-recovery protocols.
- `tests/skalary/ConcernAgents.Tests.ps1` — `test:concern-agents-complete` (seven per review type,
  declared in the manifest), injection-guard and read-only assertions.
- `tests/skalary/DispatchGuide.Tests.ps1` — byte-identical shared guide, concern-ledger-map totals.
- `scripts/skalary/Sync-PluginScripts.ps1` — the existing precedent for generate-and-verify: a
  single writer, byte-identical copies, `-WhatIf` drift gate wired into `validate.ps1`. The same
  shape probably applies to generated agent bodies.
- `docs/design-notes/architecture/plugin-registry.design.md` — payload declaration and distribution.

## Cross-plan index consultation

Consulted on 2026-08-16 with `Get-PlanIndex.ps1` using the topic filter
`concern agents|concern-agent|concern taxonomy|concern-ledger|seven concerns|7 review concerns|single-authored`.

- **Extends `b0c0d3` REQ-8.** Keep seven model-agnostic agents per surface and every local data-only,
  injection, secret-redaction, and read-only guard; generate the same contract from one source.
- **Extends `b0c0d3` REQ-10.** Keep the total deterministic concern-to-ledger mapping; move its rows
  into the registry and generate both installed map views.
- **Reuses `b0c0d3` explicit-model dispatch decision.** Generated concern agents continue to declare
  no model; the orchestrator remains the model-binding authority.
- **Reuses `b0c0d3` seven-concern taxonomy decision.** The registry centralizes the settled ids and
  meanings without adding, deleting, or redefining a concern.
- **Index limitation.** The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`.
  That unrelated record could not be indexed, so this reconciliation claims completeness only for
  the records the topic query returned.

## Governing context

- `docs/architecture-notes/arch-review-run-v1.md` — review execution and evidence authority remains unchanged.
- `docs/design-notes/project/copilot-customizations.design.md` — concern-agent and model-binding conventions.
- `docs/design-notes/architecture/plugin-registry.design.md` — plugin source, dogfood, registry, marketplace, and version ownership.
- `docs/design-notes/architecture/review-reporting.design.md` — CR/DR caller and review-run v1 boundaries.
- `docs/design-notes/project/ci-gates.design.md` — existing validation hosting and runtime boundaries reused by the drift test.
- `docs/review-ledger/consistency.md` — generated payload changes must regenerate registry and marketplace data in the same commit.
- `docs/review-ledger/testing.md` — determinism checks require clean rebuilds and non-blind mutation fixtures.
- `docs/review-ledger/security.md` — machine declarations and write confinement must be enforced rather than asserted.
