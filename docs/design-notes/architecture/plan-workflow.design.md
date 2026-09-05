---
description: Direct plan creation and execution using Git criteria, Markdown progress, and current evidence.
globs:
  - docs/implementation-plans/**
  - scripts/skalary/{PlanState,Test-Plan,DirectWorkflow,Get-DirectPlanArtifactConsumerContext}.ps*1
  - plugins/{create-implementation-plan,continue-implementation}/**
---

# Plan workflow

## Planning

`/cep` keeps epics as indexes of sibling plans. `/cip` confirms current intent, requirements, risks,
and decisions, then writes the existing `planning-confirmed` marker. Complex questions include context,
examples, benefits, pros/cons, effort and complexity from 1–10, and Mermaid when relationships matter.
Conditional absolutes become condition/behavior/exception rules; fuzzy requirements gain observable
criteria.

Plans keep the current six-hex identity, assets layout, stage markers, dependency syntax, typed
`test:`/`file:`/`review:` markers, focused validator, and script-owned scaffolding/stage mutation.
Historical context comes only from explicit IDs or a filtered index and at most five confined Markdown
artifacts through `Get-DirectPlanArtifactConsumerContext.ps1`.

## Execution

Before any mutation, `/ci` and every autopilot mode call `Test-PlanCriteriaBaseline`. It finds the
unique commit that introduced the current confirmation marker and byte-compares intent, requirements,
risks, and decisions. Checklist, stage, and worktree markers remain mutable.

`Invoke-DirectEvidence` evaluates supplied current-run test results, current confined file assertions,
and an active complete clean review for the exact current source/scope. It writes no receipt. Persisted
review Markdown is advisory.

The orchestrator performs ordinary work. A combined Designer/Validator is optional and Judge is the
normal second call. Two delegated calls are normal and five are the maximum. Observable background work
gets two evidence checks, one redirect, and at most one replacement; synchronous calls remain a host
boundary and elapsed time is not a kill signal. Existing deterministic command timeouts remain.

Non-terminal review occurs only for concrete changed-scope risk. The final phase skips post-phase review
and finalization runs one whole-plan review. Unchanged scope is not rerun. Incomplete, exhausted, stuck,
or unresolved outcomes stop visibly.

## Distribution

`DirectWorkflow.psm1` is root-canonical and bundles with `PlanState.psm1` and `SecretGuard.psm1` into
CR, DR, CI, and autopilot. The direct historical adapter adds the same closure to CR, DR, CEP, and CIP.
Run `Sync-PluginScripts.ps1`, `Build-Registry.ps1`, then `Sync-Dogfood.ps1` after changing these entries.
