---
description: `/ci` handoff and direct autonomous plan execution across host, container, and Windows Sandbox.
globs:
  - plugins/autopilot/**
  - plugins/continue-implementation/skills/**
  - .github/{agents/autopilot.agent.md,skills/autopilot/**,skills/ci/**}
  - scripts/skalary/{EpicAutopilot,Invoke-EpicAutopilot,Get-PhaseExecutionState,DirectWorkflow}.ps*1
  - .autopilot*.json
---

# Autonomous plan execution

`/ci` selects one runtime and a one-phase or whole-plan extent. The autopilot skill accepts that
choice without a second menu, validates or creates host-local configuration, and invokes the existing
blocking launcher.

The launcher retains host, container, and Windows Sandbox modes; auth, branch, offline rebundling,
explicit staging/push, destructive-action approval, custom-host validation, and isolation remain.
Exit `0` means complete, `42` operator action, `43` offline rebundle, and other nonzero values failure.

Agent or phase elapsed time never cancels work. Host/container waits are synchronous boundaries;
Sandbox waits for its sentinel or process exit. Deterministic command timeouts remain and become agent
evidence. Progress recovery uses two evidence checks, one redirect, and at most one replacement within
the three-call budget.

Before mutation `/ci` passes, and every mode repeats, `Test-PlanCriteriaBaseline`. Execution uses direct
current evidence, optional combined design/validation, no automatic Judge, native bounded roles, and one
commit per completed step. Model configuration uses stable aliases; launchers resolve a concrete host
identifier. Shipped configs select `default` context, while `long_context` remains explicit opt-in.

A complex operator stop exits `42` with context, example, benefits, pros/cons, recommendation/default,
effort and complexity from 1–10, and Mermaid only when relationships or sequencing matter. Interactive
resume shows the same ordered choices; free-form input asks one focused question.

Non-terminal review is risk-selected. Phase targets only close phases. For whole-plan runs, host,
container, and sandbox launchers invoke exactly one explicit completion target after all phases are
closed, including an all-closed resume. That target skips terminal-phase review and owns one whole-plan
CR without rerunning unchanged scope. If design notes changed, finalization runs the shared bounded
compaction once before validation; cross-note merge/delete requires approval, so headless execution
leaves the diff and exits `42`.

Terminal close proof follows the completed plan into its canonical archive path and accepts the exact
published work head through either its open or merged pull request. A clean archived plan plus that
provider proof is `closed`; it must not trigger another same-session completion handoff.

After a whole-plan source commit exists, the installed `Write-RecentLearning.ps1` replaces—not
appends—the strict 16-KiB handoff with zero to ten secret-screened lessons and repo-relative
source-commit citations. Runtime resume otherwise uses committed checklist state. Epic orchestration
is a separate deterministic wrapper around the same launcher and retains Git/provider close checks.
Installed `/pfb` remains optional: interactive `/ci` offers it before archival, while headless
autopilot queues its question without prompting. Absence, decline, or queue failure never blocks
completion and feedback never replaces evidence.

Each Copilot CLI target also writes an exact local usage sidecar. The launcher immediately normalizes
it into the plan-local `assets/ai-credits.json` ledger and removes the sidecar. Re-importing a target
execution is idempotent. The ledger retains per-execution and per-model credits and token classes;
an epic total is the sum of its child-plan ledgers. No provider usage API or telemetry service is
part of this path.
