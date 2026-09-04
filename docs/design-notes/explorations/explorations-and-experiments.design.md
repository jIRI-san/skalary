---
description: Index of deferred design explorations — ideas evaluated and deliberately parked rather than built, each with the reasoning that produced them. Load when picking up parked work, or before proposing a change in an area an exploration already covers.
globs:
  - docs/design-notes/explorations/**
---

# Explorations and Experiments

Parked design work. An entry lands here when an idea has been analysed far enough that the reasoning is worth keeping, but implementing it would derail the plan in flight.

This tier is **not** a backlog of features. It holds *analysis* — the constraint that blocked the obvious approach, the mechanism that turned out to be wrong, the alternative that survived scrutiny. That reasoning is the expensive part and the part that decays if left in a chat transcript.

## Rules

| Rule | Why |
|---|---|
| An entry records the *problem* and the *constraint*, not just the proposed fix | A fix without its constraint gets re-litigated from scratch |
| Entries state what was rejected and why | Prevents re-proposing the mechanism already ruled out |
| Nothing here is a commitment | Parked ≠ accepted; a plan must still justify picking it up |
| Promote to a real design note on implementation | An implemented exploration stops being an exploration |

## Active Explorations

| File | Area | Parked because |
|---|---|---|
| [agent-cost-optimization.design.md](agent-cost-optimization.design.md) | Multi-agent skills and agents | Advisory operator-approved baseline; implementation changes remain owned by their subsystem plans |
| [container-autopilot-watchdog.design.md](container-autopilot-watchdog.design.md) | `plugins/autopilot/scripts/**` | Would restructure autopilot invocation granularity mid-plan; the phase + whole-run caps shipped instead |
| [intent-and-domain-capture.design.md](intent-and-domain-capture.design.md) | `/cip`, `/cep`, plan `assets/` | Operator notes; builds on `b0c0d3` intent asset, which must land first |
| [design-rfc-artifacts.design.md](design-rfc-artifacts.design.md) | `/cip`, plan `assets/` | Operator notes; fits the `b0c0d3` assets layout, sequenced after it |
| [asset-scanner-root-bound.design.md](asset-scanner-root-bound.design.md) | `Sync-PluginScripts.ps1`, `schemas/{plugin,registry}/**` | Found mid-`b0c0d3`; widening the scanner grammar is a schema change, not a script fix |
| [review-system-enforcement-gaps.design.md](review-system-enforcement-gaps.design.md) | `Build-ReviewReport.ps1`, `Build-EvidenceReceipt.ps1`, `plugins/{code,design}-review/**`, `.github/workflows/**` | Sourced from the `b0c0d3` step 10.7 gate. A/D resolved by `c21cdc`; B (except evidence skipped), E/H by `768d7b`; C deferred to `34088e`; F/G remain |
## Resolved Explorations

| File | Resolution |
|---|---|
| [review-standards-tiering.design.md](review-standards-tiering.design.md) | Plan `2366ad` shipped bounded generic and repository-local review standards while leaving automated ledger promotion deferred. |
| [si-cross-repo-proposal-protocol.design.md](si-cross-repo-proposal-protocol.design.md) | Plan `2366ad` shipped a bounded typed export and clean upstream-rooted handoff; the broader platform alternatives remain rejected. |

## Scheduled review

Active explorations remain candidates for a later align phase. Resolved entries stay indexed
separately so their rejected alternatives and implementation decisions remain discoverable.
