---
name: autopilot
description: Autonomous execution mode orchestration for /ci
user-invocable: false
disable-model-invocation: true
---

# Autopilot

Accept `/ci`'s selected runtime and one-phase/whole-plan extent and keep the current launcher, auth,
offline-package, branch, and exit-code contracts. Before launch, require `/ci` to have passed
`Test-PlanCriteriaBaseline`; every launched agent repeats the same installed sibling
`DirectWorkflow.psm1` baseline check before mutation.

The launcher remains blocking and reports `0` completed, `42` operator action, `43` offline rebundle,
and every other nonzero failure exactly. Duration alone never cancels progressing work. Keep declared
deterministic build, test, command, and offline operation timeouts; their failures become evidence
handled by the agent. Preserve recoverable Git and Markdown progress for every non-completed outcome.

Autonomous execution uses direct native roles, direct evidence, risk-selected non-terminal review, one
terminal whole-plan review, and the bounded direct learning handoff described by the autopilot agent.
It does not use a scheduler, review authority store, evidence receipt, harvest receipt, or review-cycle
state.
