# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08). Two of its
constraints have no counterpart here: one registry is the single source of truth for the concern
list, and concern bodies are authored once with per-surface variants **generated at sync time so
the surfaces cannot drift**.

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

- `tests/skalary/ConcernAgents.Tests.ps1` — `test:concern-agents-complete` (seven per review type,
  declared in the manifest), injection-guard and read-only assertions.
- `tests/skalary/DispatchGuide.Tests.ps1` — byte-identical shared guide, concern-ledger-map totals.
- `scripts/skalary/Sync-PluginScripts.ps1` — the existing precedent for generate-and-verify: a
  single writer, byte-identical copies, `-WhatIf` drift gate wired into `validate.ps1`. The same
  shape probably applies to generated agent bodies.
- `docs/design-notes/project/plugin-registry.design.md` — payload declaration and distribution.
