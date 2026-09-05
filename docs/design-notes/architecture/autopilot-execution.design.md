---
description: Direct autonomous plan execution across host, container, and Windows Sandbox.
globs:
  - plugins/autopilot/**
  - scripts/skalary/{EpicAutopilot,Invoke-EpicAutopilot,Get-PhaseExecutionState,DirectWorkflow}.ps*1
  - .autopilot*.json
---

# Autonomous plan execution

The autopilot launcher retains host, container, and Windows Sandbox modes; auth, branch, offline
package rebundling, explicit staging/push, destructive-action, and external config validation remain.
Exit `0` means complete, `42` means operator action, `43` means offline rebundle, and every other
nonzero value is failure.

The launcher is blocking. Agent or phase elapsed time never causes cancellation. Host and container
process waits are synchronous host/operator boundaries; Sandbox waits for its completion sentinel or
process exit. Deterministic build, test, command, auth, and offline-operation timeouts remain local to
those commands and their failures become evidence for the agent.

Every execution mode runs `Test-PlanCriteriaBaseline` before mutation. The agent performs ordinary work,
uses optional combined design/validation plus a normal Judge, verifies current evidence directly, and
commits each completed step. Background stuck recovery uses progress evidence, one redirect, and at most
one replacement within the five-call budget.

Non-terminal review is risk-selected. The terminal phase skips ordinary phase review and owns the one
whole-plan direct CR. Successful completion replaces `docs/feedback/recent-learning.md`. Runtime resume
uses committed plan checklist state; no review-cycle, phase-receipt, or scheduler state participates.

Epic host orchestration remains a separate deterministic wrapper. It selects one child, invokes the
same blocking per-plan launcher, and retains its Git/provider close checks.
