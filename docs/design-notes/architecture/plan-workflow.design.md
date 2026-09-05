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

Each epic child owns one outcome, explicit non-goals and interface boundaries, plus dependency rationale.
`/cip` disposes every discovered edge case into a requirement, risk, or non-goal. Nontrivial AI steps
state outcome, likely touchpoints, constraints, and verification in their existing details block;
uncertain or high-risk steps also name a concrete stop/escalation condition. These are authoring
requirements in existing artifacts, not new receipts or lifecycle state.

Before drafting, `/cip` audits requirements and active policy for behavior-asserting absolute or fuzzy
language. Confirmed unconditional rules retain their reason. Otherwise it confirms condition, behavior,
and exception; fuzzy language requires an observable criterion, threshold, example, or interpretation.
Code, quotations, analyzed examples, grammar, and already-observable prose are excluded.

Plans retain six-hex identity, assets, stage markers, dependency syntax, typed `test:`/`file:`/`review:`
markers, focused validation, and script-owned mutation. History is limited to explicit IDs or the
filtered index and three confined Markdown artifacts.

Autonomous execution creates `assets/ai-credits.json` lazily. It is the minimal exact execution-cost
ledger: one idempotent record per Copilot CLI target plus a plan total. Epic cost is derived by summing
the child-plan ledgers rather than duplicating an epic ledger.

## Execution

Before mutation `/ci` and every autopilot mode run `Test-PlanCriteriaBaseline`, locating the unique
confirmation commit and comparing both index and worktree immutable criteria through Git clean filters.
Staged confirmation-marker drift is refused; checklist, stage, and worktree markers may change.
`Invoke-DirectEvidence` evaluates current supplied tests/files and an active complete clean exact-scope
review. Persisted reports are advisory.

Ordinary work is direct and uses no delegated call. One combined `primary-model-mid` Designer/Validator is
available for a concrete unresolved concern; deterministic evidence is the normal Judge. `primary-model-high`
is a deep escalation only after unresolved standard evidence, and `secondary-model-high` is one
independent pass for a named high-risk path.
Calls, retries, and replacements share a three-call ceiling; a fourth requires a new operator decision.
Background work gets two evidence checks, one redirect, and one replacement; synchronous calls are host
boundaries, elapsed time is not a kill signal, and deterministic command timeouts stay. Review is
risk-selected; the terminal phase skips phase review and runs one whole-plan review. Incomplete,
exhausted, stuck, or unresolved work stops visibly.

Finalization runs compaction exactly once only if `docs/design-notes/**` changed. It inventories the
active index, reads batches of at most five, preserves unique decisions/contracts/constraints/
exceptions/examples, and shows the diff. Cross-note merge/delete requires approval; headless mode
leaves the diff and exits `42`.

After the completed source commit, CI/autopilot run `Write-RecentLearning.ps1`, which checks completion,
source identity, citations, secrets, and 10-item/16-KiB limits before replacing the strict Markdown
handoff (`None.` for zero lessons).

Root-canonical workflow scripts bundle into their consumers. Run script sync, registry/marketplace
generation, and dogfood sync as owned by [plugin-registry.design.md](plugin-registry.design.md).
