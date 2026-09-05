# Autopilot skill — direct target

**DORMANT TARGET — Step 2.2 must replace `skills/autopilot/SKILL.md`; no active file may link here.**

Accept `/ci`'s selected runtime and one-phase/whole-plan extent and keep the current launcher, auth,
offline-package, branch, and exit-code contracts. Before launch, require `/ci` to have passed
`Test-PlanCriteriaBaseline`; every launched agent repeats the same installed sibling
`DirectWorkflow.psm1` baseline check before mutation.

The launcher remains blocking and reports `0` completed, `42` operator action, `43` offline rebundle,
and every other nonzero failure exactly. Remove elapsed agent/phase kill behavior at activation:
duration alone never cancels progressing work. Keep declared deterministic build, test, command, and offline
operation timeouts; their failures become evidence handled by the agent. Preserve recoverable Git and
Markdown progress for every non-completed outcome.

Autonomous execution uses direct native roles, direct evidence, risk-selected non-terminal review, one
terminal whole-plan review, and the bounded direct learning handoff described by the target autopilot
agent. It does not use Fleet, review-run/receipt authority, evidence receipts, harvest receipts, or
review-cycle state.
