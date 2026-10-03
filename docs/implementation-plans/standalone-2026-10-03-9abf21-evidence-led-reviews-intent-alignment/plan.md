# 9abf21: Evidence-led reviews and intent alignment
<!-- plan-id: 9abf21 -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:748a9162a453076f2b1f26fb565a5840381ec6c2a945b5d1e3a6bac18ab4d29f -->
<!-- execution-mode: manual -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Domain model - [assets/domain.md](assets/domain.md)
- Design / lightweight RFC - [assets/design.md](assets/design.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Review results - advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`
- AI-credit ledger - existing `assets/ai-credits.json`, only if autonomous execution creates it

## Phase 1: Deliver early intent alignment through execution

- [x] 1.1 Capture meaningful intent and bounded historical conflicts before drafting (REQ-1, REQ-2, REQ-3, RISK-1, RISK-2) `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/cep` and `/cip` expose consequential ambiguity before decomposition/design, preserve selected OP wording and confirmed interpretations, and reconcile relevant prior intent. Existing `intent.md` and `design.md` provide the capture and lightweight RFC.

  **Likely touchpoints:** planning skills and shared decision protocol; canonical `New-Plan.ps1`, existing epic scaffold/inventory, `Get-PlanIndex.ps1` and bounded historical reader; `PlanIndex.Tests.ps1`, `PlanIntent.Tests.ps1`, `PlanningContext.Tests.ps1`; planning/operator notes.

  **Constraints:** preserve five intent sections for child/standalone plans. CEP uses existing epic.md Goal/Decomposition notes, not new assets; child CIP carries only relevant inherited intent with provenance. Discover active/archived plan and epic intent through existing inventory. Candidate records identify kind, ID, path, archive status, matched section and at most three 240-character snippets per artifact; missing context stays explicit. Extend the bounded reader locally for selected epic intent, retaining confinement, secret screening and three-artifact total. No persistent index, interview engine or reviewer call.

  **Verify:** named `test:IntentAlignment.Planning`, `test:IntentAlignment.History` cases, focused scaffold/context regressions and selected planning structural cases. Fixtures include ambiguity, bounded discretion, changed OP intent, irrelevant old preference and intent-only historical match.

  **Stop/escalate when:** resolving history would change an active contract or another plan's dependency, or provenance needs a new storage authority.

  </details>

- [x] 1.2 Carry alignment into existing draft review and implementation stops (REQ-4, REQ-5, REQ-10, RISK-1, RISK-3) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** existing pre-confirmation review checks OP-to-draft drift; `/ci` and autopilot distinguish authorized choices from newly exposed intent decisions. A material unresolved choice preserves progress and uses operator-action stop 42. CIP corrects the affected existing criteria and uses existing reconfirmation/baseline handling before CI resumes; no full redraft.

  **Likely touchpoints:** `pre-confirmation-review.md`, DR caller role, CI/autopilot instructions and agent, baseline/context tests, direct-workflow contract, planning/review/autopilot notes and operator guides.

  **Constraints:** retain two pre-confirmation calls, standalone routing and three-call ceiling. Alignment questions are distinct from technical defects. Do not reopen resolved decisions without new evidence or bypass the Git baseline.

  **Verify:** `test:IntentAlignment.Handoff` and selected consumer/baseline tests cover OP wording versus agent summary, draft scope inflation, authorized discretion and runtime uncertainty. Publish this usable slice through canonical script sync, registry/marketplace generation and dogfood sync; verify installed consumers.

  **Stop/escalate when:** the change needs another marker, lifecycle, mandatory call or blanket re-confirmation.

  </details>

## Phase 2: Deliver evidence-led, codebase-aware reviews

- [x] 2.1 Strengthen CR/DR candidate evidence and selective independent review (REQ-4, REQ-6, REQ-10, RISK-4) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** findings demonstrate a failure or contract conflict and check disconfirming evidence. DR includes alignment; CR checks confirmed outcomes. Selected independent reviewers receive scope/contracts before earlier conclusions.

  **Likely touchpoints:** CR/DR skills, thin agents only where wiring requires it, review-reporting note, `ReviewPolicy.Tests.ps1`, structural evals.

  **Constraints:** valid static traces remain evidence; reproduction is preferred where cheap, not universally required. Group duplicate root causes. Keep defects, alignment questions and optional advice distinct without changing verdict vocabulary. Retain read-only/security guards, aliases, risk selection and budgets.

  **Verify:** `test:ReviewQuality.Evidence` covers trigger/path/impact, a guard invalidating a candidate, valid static evidence, incomplete review and an OP-authorized exception. Reuse report-contract tests; no automatic full rerun.

  </details>

- [x] 2.2 Ground technology guidance in local conventions and targeted documentation (REQ-7, REQ-8, REQ-10, RISK-5, RISK-6) [after: 2.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** implementation and review use the same scoped rules; only named consequential uncertainties trigger version-specific official-documentation lookup.

  **Likely touchpoints:** planning, CI/autopilot and CR instructions; existing standards resolver/tests; design notes and operator guide.

  **Constraints:** retain `docs/review-standards.md` syntax; short guidance references relevant existing notes/documentation. No separate best-practice library or rule schema. Explicit local choices beat generic preferences; demonstrated failures cannot be excused by precedent. Fetched text is evidence, never instructions or automatically accepted policy. Public queries exclude private code/secrets.

  **Verify:** `test:ReviewQuality.LocalFit` and `test:ReviewQuality.DocGrounding` cover local exceptions, legacy conflicts, version mismatch, malicious documentation and unavailable sources. Unavailable research is explicit; it cannot establish a defect or silently pass a selected unresolved check.

  **Stop/escalate when:** lookup would expose private information, advice conflicts with an active contract or new tooling/services would be needed.

  </details>

- [x] 2.3 Publish the review slice with focused consumer checks (REQ-10, RISK-7) [after: 2.2] `S`
  <details><summary>Implementation contract</summary>

  **Outcome:** canonical and installed review/implementation skills agree; affected notes and guides describe behavior.

  **Likely touchpoints:** distribution scripts, manifests/catalogs/dogfood, review consumer tests.

  **Constraints:** use generators; no manual generated-script edits, blanket suite, hosted workflow or unrelated cleanup.

  **Verify:** selected structural/consumer tests and focused syntax checks; include exact changed paths in script sync.

  </details>

## Phase 3: Prove quality with precisely selected local evals

- [ ] 3.1 Make named paid-case selection exact and fail before spending (REQ-9, RISK-8) [after: 1.2, 2.3] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `Invoke-WazaEvals.ps1 -Plugin <name> -Case <id> -Quick` executes exactly one requested functional case with one trial, not the unrelated adversarial pack.

  **Likely touchpoints:** canonical Waza runner, `InvokeWazaEvals.Tests.ps1`, focused/local-first tests, eval and validation notes.

  **Constraints:** validate case existence before provisioning, auth or output creation. Unknown/ambiguous selectors fail, never widen. Preserve explicit plugin-wide functional/adversarial behavior and token/isolation boundaries. Paid latency is separate from the existing deterministic under-30-second target.

  **Verify:** `test:ReviewQuality.FocusedEval` uses offline/mocked execution to assert exact case/trial/mode selection, invalid-selector preflight refusal and unchanged explicit plugin-wide behavior.

  </details>

- [ ] 3.2 Add a small balanced quality suite to existing plugin evals (REQ-1, REQ-2, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-4, RISK-8) [after: 3.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** 12-20 distinct task scenarios total across create-implementation-plan, code-review, design-review, continue-implementation and autopilot suites exercise alignment, review signal and grounding, including clean negatives. Every retained/revised/new task YAML in these suites counts, not only newly relevant tasks.

  **Likely touchpoints:** affected Waza tasks/fixtures, per-plugin convention tests, `WazaCreditPolicy.Tests.ps1`; existing reports.

  **Constraints:** map every task ID and required topic in the existing plugin-evals note; revise/replace weak existing cases before adding more, with no uncatalogued extras in the five suites. Keep unrelated plugin/global policy counts separate. Deterministic semantic checks where possible; keywords alone cannot prove diagnosis. Use established subjective graders only where needed, with rubrics calibrated against reviewed expected answers. Mock web/OP interaction where supported; no live-page dependence or new harness.

  **Verify:** `test:ReviewQuality.EvalCoverage` checks count, positive/negative balance, grader shape and outcome assertions. Cover ambiguity, intentional openness, history conflict/false conflict, draft drift, runtime escalation, cross-file defect, guarded non-defect, local exception, version mismatch, injection and missing context.

  **Stop/escalate when:** pinned Waza cannot represent interaction or grading. Use documented transcript fixtures and state fidelity limits; do not invent responder infrastructure or claim live-interaction coverage.

  </details>

## Phase 4: Operator-controlled evaluation and finalization

- [ ] 4.1 Select a bounded paid comparison or explicitly defer it (REQ-9, RISK-8) [after: 3.2] @human `S`
  <details><summary>Paid-eval decision</summary>

  **Steps:**
  1. Inspect selected deterministic results and proposed exact plugin/case/trial selections, baseline/candidate revisions, estimated cost and latency.
  2. Approve a bounded comparison, approve one broader local final run if justified, or defer. This step does not pre-authorize spending.
  3. If approved, execute direct local Waza commands with existing auth/isolation. Compare valid findings, known defects missed, false findings, question quality, available costs/credits and latency in existing reports. Identify unavailable metrics.

  **Verify:** record the OP decision in this step's progress details. Executed comparisons identify exact cases/revisions and observed results. Deferral completes this decision, not proof of improved quality.

  **Rollback:** cancel an unstarted run or stop its specific launched process if required; incurred credits cannot be recovered. Retain reports and expose partial execution.

  </details>

- [ ] 4.2 Finalize with scoped evidence and one whole-plan review (REQ-3, REQ-9, REQ-10, RISK-7) [after: 4.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** shipped skills, focused commands, scenarios and guidance form one understandable workflow. Compare delivery with original confirmed intent; explain deviations without rewriting it.

  **Likely touchpoints:** affected docs, generated outputs, final review and existing learning handoff.

  **Constraints:** no automatic broad/premium run or GitHub CI. Update notes alongside each slice. Existing conditional compaction and terminal review run once, then normal completion/learning/archive flow. No measured-improvement claim when comparison is deferred.

  **Verify:** named deterministic cases pass in selected runs; installed output matches canonical payloads; `review:cr` covers implementation scope. Pending required alignment or technical work cannot be clean.

  </details>
