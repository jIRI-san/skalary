# d5ca36: Repository maintenance service
<!-- plan-id: d5ca36 -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:427330aa26b0982418536b67ed0d0374a5e174133ee8658de8b1f08d21889782 -->
<!-- execution-mode: manual -->
<!-- scope: phase -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Domain model - [assets/domain.md](assets/domain.md)
- Approved design - [assets/design.md](assets/design.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Review results - advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`

## Phase 1: Usable repository survey and drift report
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Resolve review integration and wire installed discovery (REQ-1, REQ-2, REQ-11, RISK-1, RISK-2) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the new `repository-maintenance` plugin exposes `/rcs` and can discover plan/epic state, relevant human sources, repository subsystems, standards, and the existing maintenance record in a foreign consumer repository.

  **Likely touchpoints:** `plugins/repository-maintenance/plugin.json`, `skills/rcs/SKILL.md`, installed assets/script mappings, canonical `Get-PlanIndex.ps1`, `Get-DirectPlanArtifactConsumerContext.ps1`, `PlanState.psm1`, and focused fixtures.

  **Constraints:** inspect current integrated helpers before selecting signatures; reuse PlanState inventory and bounded intent intake rather than adding another index. Use enhanced intent/epic discovery if integrated; otherwise disclose search/epic-context gaps. Probe the plan corpus or use inventory before calling the index, which throws on an absent corpus. Derive subsystems from existing indexes/manifests/entry points and foreign-consumer project/build/layout evidence, not a new registry. Declare reusable canonical closures through existing script sync, not sibling-plugin imports. Missing notes, plan corpus, or standards are explicit coverage gaps, not unrelated scaffolds.

  **Verify:** focused inventory/discovery fixtures cover active, archived, legacy/no-intent, malformed, and no-plan repositories; source and dogfood wiring use installed paths.

  **Stop/escalate when:** current inventory/intake helpers are absent or incompatible, or needed historical context cannot be established within the bounded intake. Missing enhanced snippets alone are a coverage limitation, not an integration blocker; do not merge another session's branch or invent a replacement index.

  </details>
- [x] 1.2 Deliver the survey-to-evidence-to-record MVP (REQ-1, REQ-2, REQ-3, REQ-7, REQ-8, REQ-11, RISK-2, RISK-3, RISK-6) [after: 1.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/rcs` produces a repository-wide structural survey, selects concrete drift traces, and saves cited findings and explicit coverage to `docs/repository-maintenance.md` without editing implementation or source criteria.

  **Likely touchpoints:** audit guidance and record template under `skills/rcs/assets/`, a small plugin-owned Markdown record helper, `tests/skalary/RepositoryMaintenance.Tests.ps1`, plugin structural evals, manifest literal scaffold.

  **Constraints:** keep the report advisory, source commit plus dirty-worktree scope visible, and decisions preserved. Frame accepted consumer Markdown with `ConvertTo-UntrustedReviewBlock` once; retain already-framed historical intake without nesting. The plugin-owned writer uses a compile-time fixed path, `Resolve-PhysicalRepoPath`, per-component reparse checks, physical containment, and existing secret guards, not plan-corpus or review-report writers. Stable-ID matching is exact; ambiguous reuse is an operator choice. Refuse malformed existing content or unsafe/oversized writes without truncation or a success-shaped fallback.

  **Verify:** focused helper tests prove create/read/update, preserved human prose/dispositions, idempotent unchanged findings, missing record, empty findings, partial coverage, refusal, and no source/criteria mutation. Walk a disposable fixture containing one evidenced mismatch, one legitimate exception, and one legacy plan without intent; show the actual cited trace, not a regex-only quality claim.

  **Stop/escalate when:** source expectations conflict, a selected trace cannot be completed, the record cannot be preserved, or source changes invalidate gathered evidence. Keep gaps visible and unresolved dispositions pending.

  </details>

## Phase 2: Full quality recommendations and operator actions
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add codebase design/architecture, coding-standard, and dead-code proposals (REQ-4, REQ-5, REQ-7, REQ-11, RISK-3, RISK-4) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the same survey includes architecture/design improvement opportunities and coding-standard drift beyond individual plans, plus evidence-led dead-code removal candidates.

  **Likely touchpoints:** audit guidance, installed examples, structural evals, focused reachability fixtures, record candidate examples.

  **Constraints:** follow explicit local conventions and Simplicity First. Missing references alone do not prove dead code. Inspect manifests, exported/public APIs, scripts/package commands, manual maintenance tools, tests, configuration, reflection/dynamic dispatch, generated sources, and external consumers where relevant. Unsupported language tooling or opaque external callers remain uncertainty. Generated copies are not independent removal targets.

  **Verify:** disposable cases distinguish an unreachable private helper from an exported/manual tool and an indirectly registered handler; another case reports a concrete cross-subsystem design improvement with cost/tradeoff and a corrective-plan option. Structural checks verify required guidance; scenario evidence demonstrates judgment and is not claimed as a measured LLM quality gain.

  **Stop/escalate when:** removal could affect a supported entry point or external contract whose use cannot be established; report an uncertain candidate rather than recommend unconditional deletion.

  </details>
- [x] 2.2 Wire dispositions, plan reuse, and approval-gated archive handoffs (REQ-6, REQ-8, REQ-9, REQ-10, REQ-11, RISK-4, RISK-5, RISK-7) [after: 2.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the operator can accept scoped intentional drift, record "won't fix," or choose a corrective implementation plan for any applicable finding, including dead code and architecture/design proposals; implemented plans receive separate archival choices.

  **Likely touchpoints:** decision guidance, record helper, `/cip` handoff instructions, existing state/completion/archive contracts, focused refusal and repeat-run cases.

  **Constraints:** no disposition inferred from silence. Check existing active corrective plans before proposing another; reuse/update is an explicit choice. A cleanup acceptance does not amend confirmed criteria or waive a locked contract. Invoke existing `/cip` or architecture-maintenance flow where needed. Use existing completion/archive paths, never launch autonomous implementation to accomplish archival.

  **Verify:** fixtures cover unchanged accepted/won't-fix entries, changed assumptions, reopened candidates preserving prior rationale, duplicate-plan linkage, cancelled/incomplete plan creation, incomplete plans, unarchived epic children, archive destination collision, and successful selected handoffs. Assert decision/plan/archive outcome is recorded only after the relevant action succeeds.

  **Stop/escalate when:** required installed planning/archive capability is absent, completion evidence is missing, a contract requires approval, or a handoff fails. Keep the requested action pending/blocked with an exact reason; do not claim success or rewrite criteria.

  </details>

## Phase 3: Shippable consumer experience
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Document the complete workflow and add focused behavioral coverage (REQ-1, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, RISK-6, RISK-8) [after: 2.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** operator documentation explains audit coverage, report limits, decisions, corrective planning, archival, dead-code uncertainty, and the separate docs/reference sweep; focused tests cover the delivered helper and installed instructions.

  **Likely touchpoints:** `docs/design-notes/architecture/repository-maintenance.design.md`, design-note index, customization inventory, `docs/operator-guide/reviews.md` and its index, plugin README/evals, existing consumer fixture seams.

  **Constraints:** do not present maintenance records as architectural standards or current review proof. Update related docs only; do not execute a repository docs sweep while implementing this plugin. Keep source `SKILL.md` within the existing 12000-byte limit. Routine checks stay local/focused; paid/premium and full-repository runs need separate operator approval.

  **Verify:** run selected Pester/helper and plugin structural cases; show a disposable end-to-end walkthrough that saves a drift, dead-code and design recommendation and honors one selected disposition. Verify the walk leaves implementation untouched and reports remaining audit gaps.

  </details>
- [x] 3.2 Converge distribution and perform one final risk-selected review (REQ-12, RISK-8) [after: 3.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** source, registry, marketplace, dogfood, and foreign consumer installation agree on one independently installable plugin.

  **Likely touchpoints:** manifest, the existing `Sync-PluginScripts.ps1` consumer-owned optional-input table, sync/build tools, generated registry/marketplace/README/dogfood, focused consumer tests, final review.

  **Constraints:** existing generator-owned outputs only; no manual catalog edits or new lifecycle/schema/CI service. Declare only the fixed record as a literal scaffold, with no scaffold `confine` helper. Add only actually referenced consumer-owned docs roots to the existing optional-input table; do not scaffold the plan/architecture/design corpus. Follow the established script-sync, registry, marketplace, dogfood order. Retain normal `/ci` finalization and one whole-plan current-source CR; no duplicated terminal-phase review.

  **Verify:** focused distribution/consumer checks prove file closure, literal record scaffold, helper availability, version/hash agreement, removal ownership, and no source-tree runtime imports. Final review covers the changed plugin, guards, handoffs, tests, and docs.

  **Stop/escalate when:** packaging introduces sibling-path dependencies, generated drift remains, or focused tests/review are incomplete.

  </details>
