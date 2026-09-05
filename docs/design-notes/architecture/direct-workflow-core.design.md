---
description: Dormant direct review and plan-execution primitives staged before the simple workflow cutover.
globs:
  - scripts/skalary/DirectWorkflow.psm1
  - scripts/skalary/Get-DirectPlanArtifactConsumerContext.ps1
  - scripts/skalary/assets/direct-workflow-*.md
  - plugins/**/targets/direct/**
  - tests/skalary/DirectWorkflow*.Tests.ps1
---

# Direct workflow core

## Dormant boundary

`DirectWorkflow.psm1`, the direct historical adapter, and every `targets/direct/` instruction are the
unactivated replacement path. No active CR, DR, CEP, CIP, CI, or autopilot entry point imports or links
them, no plugin manifest distributes them, and dogfood remains unchanged. Step 2.2 owns the atomic
consumer switch and retirement of review-run, receipt, Fleet, and repair machinery. Keeping the path
dormant avoids a compatibility layer between old authority and direct advisory output.

## Deterministic primitives

| Function | Contract |
|---|---|
| `Test-PlanCriteriaBaseline` | Resolves a canonical plan with `PlanState`, finds the unique Git commit that introduced the current committed `planning-confirmed` value, and byte-compares intent, requirements, risks, and decisions with that tree. Plan checklist, stage, and worktree markers are outside the comparison. |
| `Write-DirectReviewReport` | Validates a full Git commit, selected-task completion, and the closed verdict vocabulary; redacts secrets; then atomically replaces the confined stage report in the same directory. The returned in-memory result is current evidence; the Markdown file is advisory. |
| `Invoke-DirectEvidence` | Checks supplied test outcomes, current confined file assertions, and an active complete clean review result for the exact source and requested scope. It writes no receipt or state. |
| `Resolve-DirectReviewStandards` | Parses the optional 16 KiB strict local Markdown file against caller-supplied hand-authored base rules. This path has no generated generic-standard JSON dependency. |
| `ConvertTo-UntrustedReviewBlock` | Redacts high-confidence secrets and chooses a delimiter absent from the content before framing repository text as untrusted data. |
| `Get-DirectPlanArtifactConsumerContext.ps1` | Reads at most five explicitly selected current Markdown artifacts through `PlanState` confinement, includes stable `phase-N.md`/`final.md` review files without receipts, screens secrets, and emits content once inside the direct untrusted frame. |

The module contains only repository fact checks and safe writes. Native roles, call limits, recovery,
review cadence, visible outcomes, and retained guard instructions stay readable in the dormant Markdown
asset rather than becoming a scheduler or policy engine.

## Focused proof

`DirectWorkflow.Tests.ps1` invokes every exported primitive against isolated Git repositories. It covers
the four-file confirmation baseline and mutable plan progress; confined phase/final report replacement;
hostile framing and secret publication guards; strict local standards; live direct evidence; and closed
native recovery, budget, and single-terminal-review scenarios. Reparse escape cases run when the host can
create directory links. The policy scenarios deliberately remain fixtures over the readable native
instructions rather than introducing scheduler state into the module.

`DirectWorkflowConsumers.Tests.ps1` invokes the historical adapter and checks secret/budget behavior,
the complete dormant target set, canonical closure map, and the negative invariant that active plugin
entry points, manifests, and dogfood do not reference the target before Step 2.2.

## Consumer preparation

The seven canonical target files cover CR, DR, CEP, CIP, CI, the autopilot skill, and the autopilot
agent. They encode risk-selected direct review, the approved model/call/context budgets, native
design/judge roles, evidence-based stuck recovery, Git criteria protection, direct evidence, one
terminal review, bounded learning handoff, and closed visible outcomes. They are intentionally outside
plugin manifests. `assets/direct-workflow-activation.md` is the exact replacement, closure,
manifest/registry, and delayed dogfood checklist for Step 2.2; it is not a runtime flag.

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
