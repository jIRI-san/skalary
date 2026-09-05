---
description: Dormant direct review and plan-execution primitives staged before the simple workflow cutover.
globs:
  - scripts/skalary/DirectWorkflow.psm1
  - scripts/skalary/assets/direct-workflow-core.md
---

# Direct workflow core

## Dormant boundary

`DirectWorkflow.psm1` and `assets/direct-workflow-core.md` are the unactivated replacement core. No
active CR, DR, CIP, CI, or autopilot skill imports them, and no plugin manifest distributes them. Phase
2 owns the atomic consumer switch and retirement of review-run, receipt, Fleet, and repair machinery.
Keeping the path dormant avoids a compatibility layer between old authority and direct advisory output.

## Deterministic primitives

| Function | Contract |
|---|---|
| `Test-PlanCriteriaBaseline` | Resolves a canonical plan with `PlanState`, finds the unique Git commit that introduced the current committed `planning-confirmed` value, and byte-compares intent, requirements, risks, and decisions with that tree. Plan checklist, stage, and worktree markers are outside the comparison. |
| `Write-DirectReviewReport` | Validates a full Git commit, selected-task completion, and the closed verdict vocabulary; redacts secrets; then atomically replaces the confined stage report in the same directory. The returned in-memory result is current evidence; the Markdown file is advisory. |
| `Invoke-DirectEvidence` | Checks supplied test outcomes, current confined file assertions, and an active complete clean review result for the exact source and requested scope. It writes no receipt or state. |
| `Resolve-DirectReviewStandards` | Parses the optional 16 KiB strict local Markdown file against caller-supplied hand-authored base rules. This path has no generated generic-standard JSON dependency. |
| `ConvertTo-UntrustedReviewBlock` | Redacts high-confidence secrets and chooses a delimiter absent from the content before framing repository text as untrusted data. |

The module contains only repository fact checks and safe writes. Native roles, call limits, recovery,
review cadence, visible outcomes, and retained guard instructions stay readable in the dormant Markdown
asset rather than becoming a scheduler or policy engine.

## Direct report contract

Plan-associated output is exactly `assets/reviews/phase-<N>.md` or `assets/reviews/final.md`, under a
canonical `Resolve-Plan` result and `PlanState` confinement context. Reports contain the ordered
`Source`, `Scope`, `Completed tasks`, `Findings`, and `Verdict` headings. `clean` requires every selected
task to complete and no findings; failed, interrupted, or stuck tasks force a non-clean outcome.
Security findings use attacker/input, reachable capability, affected asset, and plausible impact.

## Deliberate limits

The direct path adds no schema, receipt, run store, scheduler, telemetry, policy engine, or compatibility
service. It does not infer an active result from persisted Markdown. Existing external-format validators
and operator control of destructive actions remain at their current boundaries until activation.
