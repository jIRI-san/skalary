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
and decisions, then writes the existing `planning-confirmed` marker. The shared planning decision
protocol makes complex predefined choices identical across hosts: context, a concrete example, benefits,
pros/cons, recommendation/default, effort and complexity from 1–10, and Mermaid only when relationships
or sequencing matter. Free-form input is one focused question at a time; explicit trivial yes/no prompts
stay concise.

Before drafting, `/cip` inspects operator requirements and relevant active policy for behavior-asserting
absolute terms and the seeded fuzzy vocabulary. An already confirmed unconditional rule stays an
invariant with its reason. Otherwise `/cip` presents a candidate condition, behavior, and exception for
confirmation. A fuzzy requirement is drafted only after the operator supplies an observable criterion,
threshold, example, or interpretation. Code keywords, quotations, examples being analyzed, format
grammar, and already-observable descriptive prose are excluded.

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

Finalization invokes the shared design-note compaction protocol exactly once only when implementation
changed `docs/design-notes/**`. It inventories `.design-notes.md`, reads candidates in sequential batches
of at most five, preserves unique decisions/contracts/constraints/exceptions/examples, and shows the
final Git diff before terminal review. Cross-note merge/delete needs explicit operator approval; a
headless run leaves the proposal visible and exits `42`. `docs/operator-guide/**` never triggers or
participates in compaction.

After a successful whole-plan source commit, `/ci` and autopilot invoke the bundled
`Write-RecentLearning.ps1`. It validates plan completion, source identity, citations, secrets, the
10-item/16-KiB limits, then atomically replaces `docs/feedback/recent-learning.md`. It writes strict
Markdown, including explicit `None.` for zero lessons, with no history, receipt, or repair store.

## Distribution

`DirectWorkflow.psm1` is root-canonical and bundles with `PlanState.psm1` and `SecretGuard.psm1` into
CR, DR, CI, and autopilot. The direct historical adapter adds the same closure to CR, DR, CEP, and CIP.
`Write-RecentLearning.ps1` and its validation closure bundle into CI and autopilot.
Run `Sync-PluginScripts.ps1`, `Build-Registry.ps1`, then `Sync-Dogfood.ps1` after changing these entries.
