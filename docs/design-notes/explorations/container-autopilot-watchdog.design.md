---
description: Deferred exploration — replacing autopilot's duration-based timeouts with a no-progress (stall) watchdog keyed on commit cadence. Load before changing autopilot timeout semantics or the container invocation granularity.
globs:
  - plugins/autopilot/scripts/**
  - plugins/autopilot/schemas/autopilot.schema.json
---

# Container Autopilot — Stall Watchdog

## Problem this targets

The observed failure is a phase that **runs forever iterating on something small without progressing** — a spin loop, not legitimately slow work. Duration caps cannot distinguish the two: the same 45-minute threshold that kills a spin loop also kills an honest long step. Phase 2 of plan `b0c0d3` ran 84 minutes productively; a tight duration cap would have destroyed it.

`maxIterationsPerStep` exists but is **agent-honoured, not enforced** — nothing outside the model's own compliance bounds the fix loop.

## Why "step timeout" is the wrong mechanism

The intuitive fix is a per-step timeout. It does not fit the execution model:

| Constraint | Consequence |
|---|---|
| The container invokes `copilot` **once per phase** ([container-entrypoint.sh](../../../plugins/autopilot/scripts/container-entrypoint.sh)) | Steps are internal to one CLI process; there is no step-level process to time or kill |
| Enforcing per-step would mean one `copilot` call per step | Context is rebuilt from scratch per step — ~45 invocations instead of ~10 for a plan this size, with the token cost that implies |
| Phase-completion logic (crosscheck, evidence rebuild, phase push) assumes the agent owns the whole phase | Splitting invocation granularity forces that logic to move or be re-entrant |

## Proposed mechanism

Watch **progress**, not duration. Per-step commits (autopilot agent step 21) make commit cadence a reliable heartbeat, so the watchdog polls `git log -1 --format=%ct` on the work branch and terminates only when no new commit has appeared within `noProgressTimeout`.

```text
every 5s:  if (now - last_commit_time) > noProgressTimeout -> preserve_work; exit
```

The polling loop already exists in the entrypoint for the per-phase cap; this reuses it. Distinguishing property: a long step that commits sub-work survives; a spin loop that commits nothing does not.

Resulting layered model:

| Setting | Scale | Catches |
|---|---|---|
| `noProgressTimeout` | ~45–60 min | spin loops — the actual pathology |
| `timeout` | per phase | runaway phase, coarse backstop |
| `planTimeout` | whole run | runaway run |

## Open risk

The heartbeat is only as good as commit frequency. A genuinely large single step that produces no intermediate commit for longer than the window would be killed as a false positive. Before shipping, either confirm that workflow-log writes (`Add-WorkflowNote`) commit often enough to serve as the heartbeat, or start the window generously (60 min) and tighten from observed data.

## Status

Parked. The per-phase `timeout` and whole-run `planTimeout` caps shipped instead (autopilot `1.2.0`), together with the SIGTERM preservation handler and per-step pushes that make a stall watchdog cheap to add later. Nothing in that work forecloses this design.
