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
terminal review, and the bounded recent-learning handoff.

Successful whole-plan completion calls the installed `Write-RecentLearning.ps1` only after the full
completed source commit exists. Zero to ten lessons carry repo-relative source-commit citations; the
helper screens secrets and atomically replaces, never appends, the 16-KiB Markdown handoff.

The launcher preserves auth, branch, container/sandbox isolation, offline package rebundling, custom
host command validation, and exit codes. It does not kill agents based on elapsed duration.
