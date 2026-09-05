---
description: Direct plan creation and execution using Git criteria, Markdown progress, and current evidence.
globs:
  - docs/implementation-plans/**
  - scripts/skalary/{PlanState,Test-Plan,DirectWorkflow,Get-DirectPlanArtifactConsumerContext,Get-DesignNoteCompactionContext,Write-RecentLearning}.ps*1
  - plugins/{create-implementation-plan,continue-implementation}/**
---

# Plan workflow

Human guidance lives in [`docs/operator-guide/README.md`](../../operator-guide/README.md); it is not auto-loaded
and is excluded from design-note compaction.

## Planning

`/cep` keeps epics as indexes of sibling plans. `/cip` confirms intent, requirements, risks, and
decisions before writing `planning-confirmed`. Complex choices use host-equivalent context, example,
benefits, pros/cons, recommendation/default, 1–10 effort/complexity, and Mermaid only when structure
matters; free-form input remains one focused question.

Before drafting, `/cip` audits requirements and active policy for behavior-asserting absolute or fuzzy
language. Confirmed unconditional rules retain their reason. Otherwise it confirms condition, behavior,
and exception; fuzzy language requires an observable criterion, threshold, example, or interpretation.
Code, quotations, analyzed examples, grammar, and already-observable prose are excluded.

Plans retain six-hex identity, assets, stage markers, dependency syntax, typed `test:`/`file:`/`review:`
markers, focused validation, and script-owned mutation. History is limited to explicit IDs or the
filtered index and five confined Markdown artifacts.

## Execution

Before mutation `/ci` and every autopilot mode run `Test-PlanCriteriaBaseline`, locating the unique
confirmation commit and byte-comparing immutable criteria; checklist, stage, and worktree markers may
change. `Invoke-DirectEvidence` evaluates current supplied tests/files and an active complete clean
exact-scope review. Persisted reports are advisory.

Ordinary work may use a combined Designer/Validator and normally a Judge: two calls by default, five
maximum. Background work gets two evidence checks, one redirect, and one replacement; synchronous
calls are host boundaries, elapsed time is not a kill signal, and deterministic command timeouts stay.
Review is risk-selected; the terminal phase skips phase review and runs one whole-plan review.
Incomplete, exhausted, stuck, or unresolved work stops visibly.

Finalization runs compaction exactly once only if `docs/design-notes/**` changed. It inventories the
active index, reads batches of at most five, preserves unique decisions/contracts/constraints/
exceptions/examples, and shows the diff. Cross-note merge/delete requires approval; headless mode
leaves the diff and exits `42`.

After the completed source commit, CI/autopilot run `Write-RecentLearning.ps1`, which checks completion,
source identity, citations, secrets, and 10-item/16-KiB limits before replacing the strict Markdown
handoff (`None.` for zero lessons).

Root-canonical workflow scripts bundle into their consumers. Run script sync, registry/marketplace
generation, and dogfood sync as owned by [plugin-registry.design.md](plugin-registry.design.md).
