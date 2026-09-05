---
description: Autopilot skill handoff, runtime selection, and direct execution contract.
globs:
  - plugins/autopilot/skills/**
  - plugins/continue-implementation/skills/**
  - .autopilot*.json
---

# Autopilot skill

`/ci` selects one runtime and one-phase or whole-plan extent. The autopilot skill accepts those choices
without a second menu, validates/creates the host-local configuration, and invokes the existing launcher.

Before launch `/ci` passes the Git confirmation baseline; the autonomous agent repeats it before
mutation. All modes use direct evidence, native bounded roles, progress-based stuck recovery, one
terminal review, and the bounded recent-learning handoff. They do not use scheduler, receipt, ledger,
or review-cycle authority.

The launcher preserves auth, branch, container/sandbox isolation, offline package rebundling, custom
host command validation, and exit codes. It does not kill agents based on elapsed duration.
