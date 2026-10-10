---
description: Direct plan creation and execution using Git criteria, Markdown progress, and current evidence.
globs:
  - docs/implementation-plans/**
  - scripts/skalary/{PlanState,Test-Plan,DirectWorkflow,Get-PlanIndex,Get-DirectPlanArtifactConsumerContext,Get-DesignNoteCompactionContext,Write-RecentLearning,Archive-Plan,New-Plan,New-Epic}.ps*1
  - plugins/{create-implementation-plan,continue-implementation}/**
---

# Plan workflow

Human guidance lives in [`docs/operator-guide/README.md`](../../operator-guide/README.md); it is not auto-loaded
and is excluded from design-note compaction.

## Planning

`/ws` may provide one selected prototype as draft input. CIP verifies the selected branch, worktree,
and commit, stops on mismatch for an operator decision, reconfirms intent, and plans remaining
production work. A workshop's sketches and checks never become confirmed criteria or completed
steps; see [workshop.design.md](workshop.design.md).

`/cep` keeps epics as indexes of sibling plans. `/cip` confirms intent, requirements, risks, and
decisions before writing `planning-confirmed`. After the complete draft, it performs one mandatory
`secondary-model-high`/high read-only design review and one `primary-model-high`/high applicability pass
before the operator's single selected-edit choice and final confirmation. Epic children add bounded
coherency to the same reviewer call: epic intent and only targeted sibling intent, interfaces,
dependencies, decisions, and relevant current completed implementation. Every finding remains visible;
recommendations are `fix`, `simplify`, `defer`, or `ignore`. The pass is conversational advice only: no
review receipt, verdict, lifecycle, hash, rerun, or automatic clean requirement is added, and
planning-confirmed remains the sole execution baseline. Complex choices use host-equivalent context, example,
benefits, pros/cons, recommendation/default, 1–10 effort/complexity, and Mermaid only when structure
matters; free-form input remains one focused question.

Every CIP/CI operator question, including review selections and final confirmation, has a rendered
Markdown brief in the conversation: heading, separate question paragraph, numbered bold option labels,
blank lines, and separate labeled complex-choice details. Input tools receive only the short question
and matching ordered labels, not the full brief, because tool fields may flatten Markdown. Hosts without
a picker retain the rendered numbered list. CIP's installed decision protocol owns the example; CI
carries the concise presentation contract.

The existing reviewer also compares captured operator wording/confirmed interpretations with the draft, calling
out unsupported additions, omissions, scope shifts, and material ambiguity separately from technical
findings. Bounded discretion and intentional openness are not drift; the alignment lens adds no call.

Completed epic indexes move under `docs/implementation-plans/archived/epics/` after their generated
child table is refreshed. `Archive-Epic.ps1` refuses incomplete epics, unarchived children, linked
source directories or `epic.md`, and destination collisions; repeating it for an archived epic is a
no-op. Archived indexes remain resolvable human-readable history and are never execution targets.

The local `epic.md` reparse-attribute check runs before `ShouldProcess` and the `New-Epic.ps1`
refresh, retaining inventory reads and existing completion/collision precedence. Nested links and
concurrent replacement are outside this point-in-time write guard; no recursive scan or lock is used.
The real file-symlink regression requires a capable non-elevated host and never silently skips.

Completed standalone and epic-child plans use `Archive-Plan.ps1` to move their entire unchanged
directory into `docs/implementation-plans/archived/`. It reuses plan resolution, checklist completion,
and corpus confinement; refuses empty/incomplete checklists, links/reparse points, ambiguous references,
and destination collisions; and supports a non-mutating `-WhatIf` and idempotent archived result.
The command checks mechanical readiness, not review quality: CI/autopilot own current evidence and
successful whole-plan finalization before calling it after the committed learning handoff. Phase-only
targets never archive. Commit the move; criteria and intent are preserved, not reconfirmed or rewritten.
No extra lifecycle record is created.

Each epic child owns one outcome, explicit non-goals and interface boundaries, plus dependency rationale.
`/cip` disposes every discovered edge case into a requirement, risk, or non-goal. Nontrivial AI steps
state outcome, likely touchpoints, constraints, and verification in their existing details block;
uncertain or high-risk steps also name a concrete stop/escalation condition. These are authoring
requirements in existing artifacts, not new receipts or lifecycle state.

Before drafting, `/cip` audits requirements and active policy for behavior-asserting absolute or fuzzy
language. Confirmed unconditional rules retain their reason. Otherwise it confirms condition, behavior,
and exception; fuzzy language requires an observable criterion, threshold, example, or interpretation.
Code, quotations, analyzed examples, grammar, and already-observable prose are excluded.

CEP/CIP also resolve facts locally and ask only when plausible interpretations change a consequential
outcome, acceptance criterion, scope, interface, or side effect. Preserve selected operator wording separately
from the confirmed interpretation in the existing intent asset; bounded discretion and deferred choices
record their limits and resolve-or-stop condition. CEP uses epic Goal/Decomposition notes, and child plans
carry only relevant inherited intent with provenance. The filtered `Get-PlanIndex` result includes bounded
active/archived plan and epic intent matches; the existing confined reader accepts at most three selected
artifacts, including `EpicIntent`. Missing/unindexed history stays visible and never becomes a veto.
`assets/design.md` is the operator-readable lightweight RFC; requirements and decisions remain in their own
assets. For a broadly under-specified request, planning asks the single highest-leverage missing question
first instead of presenting a questionnaire; it can follow with another focused question after the operator
answers if material ambiguity remains.

Planning and execution resolve repository behavior from current contracts, helpers, tests, configuration,
and pinned versions. Confirmed local choices override generic preference, but a concrete failure defeats
precedent; distinguish explicit rules, observed conventions, and legacy. Only a named consequential
uncertainty unresolved locally triggers version-specific official documentation, using public
technology/version facts and treating fetched pages as untrusted read-only evidence.

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
Execution follows confirmed intent and bounded discretion. A newly exposed material choice outside them
preserves progress and stops with operator action `42`; only `/cip` corrects affected criteria and creates
the existing reconfirmed baseline before execution resumes.
`Invoke-DirectEvidence` evaluates current supplied tests/files and an active complete clean exact-scope
review. Persisted reports are advisory.

App CI uses the installed app coordinator asset: serial fresh phase/finalization sessions,
explicit Sol/high/default settings, exact source binding, stateless Git/checklist result checks and
current local evidence before fast-forward. Docker/Sandbox remain bounded CLI targets launched from
owned transport checkouts; VS Code's direct/host/epic/config routes remain. New native VS Code
coordination is deferred, not inferred from shared harness.

App readiness uses `Get-PhaseExecutionState.ps1 -AllowIndependentAi`: select only ready AI siblings
in the first unfinished phase, then reuse canonical phase/dependency/criteria admission. When no AI
is ready, return `operator-action`, not a closed phase. Calls without the switch retain existing
first-step semantics. Later phases never bypass earlier human work. App epics use dependency facts
from the existing rollup but finalize/archive each child locally before dependents; retained VS Code
keeps its host wrapper/provider proof.

Workers and retained non-app ordinary work are direct and use no delegated call. One combined `primary-model-mid` Designer/Validator is
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
