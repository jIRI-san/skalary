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
It does not persist auxiliary review or learning lifecycle state. If the run needs a complex operator
decision, the agent stops with `42` and returns the
host-equivalent context, examples, benefits, pros/cons, recommendation/default, effort, complexity, and
relationship/sequence diagram defined there; free-form input is one focused question at a time.

During finalization, invoke `./assets/design-note-compaction.md` exactly once when the bundled
`.github/skills/autopilot/scripts/Get-DesignNoteCompactionContext.ps1` reports edited
`docs/design-notes/**`. Never self-approve its cross-note merge/delete proposal: preserve the visible
diff and stop with `42`. Do not invoke it for `docs/operator-guide/**` or other changes alone.

After the completed source commit exists, invoke installed
`.github/skills/autopilot/scripts/Write-RecentLearning.ps1` with zero to ten concise lessons and one
repo-relative source-commit citation per lesson. Commit the replacement; never append it or write
auxiliary history, recovery, or lifecycle state.
