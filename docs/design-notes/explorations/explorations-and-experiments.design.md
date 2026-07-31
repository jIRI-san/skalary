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
| [container-autopilot-watchdog.design.md](container-autopilot-watchdog.design.md) | `plugins/autopilot/scripts/**` | Would restructure autopilot invocation granularity mid-plan; the phase + whole-run caps shipped instead |
