# 2dd53a: App-native CI execution and GPT-6.1 Sol routing
<!-- plan-id: 2dd53a -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:04d1bc542467b3dc4b00bd66aaa0e00cdbed741abac0805b7afa168511797a93 -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Domain - [assets/domain.md](assets/domain.md)
- Design - [assets/design.md](assets/design.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Unattended execution decisions - `assets/unattended-decissions.md`, created only when execution makes a decision.
- Reviews - advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`.

## Phase 1: One model policy, existing effort categories

- [ ] 1.1 Map all six public aliases to GPT-6.1 Sol and make replacement semantics honest (REQ-1, REQ-2, RISK-1) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** primary and secondary aliases use `gpt-6.1-sol` / `GPT-6.1 Sol (copilot)`; existing Routine medium and Standard/Deep/Independent high effort settings remain.

  **Likely touchpoints:** `tools/model-allowlist.psd1`, model/review skill instructions, `scripts/skalary/{Sync-ModelBindings,Test-ModelAllowlist}.ps1`, `tests/skalary/ModelAllowlist.Tests.ps1`.

  **Constraints:** preserve the six public alias names; resolve host identifiers explicitly; a same-model alias is not an availability fallback. Review independence means a separate context, not a different model.

  **Verify:** focused alias/effort and unavailable-model regressions prove each binding and visible refusal without retrying an unavailable Sol through another alias.

  **Stop/escalate when:** a host cannot accept the exact requested model identifier; do not silently select an older or different model.

  </details>
- [ ] 1.2 Regenerate model consumers and update directly affected guidance (REQ-1, REQ-2, RISK-1) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** generated skill assets and Waza executor/judge bindings use the same policy; planning/review instructions no longer promise cross-model diversity.

  **Likely touchpoints:** `Sync-ModelBindings.ps1`, declared model assets, `plugins/*/evals/waza/**`, model configuration catalog, affected design notes.

  **Constraints:** use owner generators and the source-first distribution sequence; do not add unsupported Waza effort fields or change eval tool pins, approval gates, or pricing claims.

  **Verify:** model binding check, model allowlist check, focused model consumers, and applicable deterministic eval-schema checks.

  </details>

## Phase 2: App coordinator and isolated phase integration

- [ ] 2.1 Unify CI and the shared executor around native app sessions (REQ-3, REQ-4, REQ-5, REQ-12, RISK-2) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/ci` selects a confirmed plan and execution extent, then coordinates fresh phase workers using native app tools; interactive and unattended execution share this path.

  **Likely touchpoints:** `plugins/continue-implementation/skills/ci/**`, reusable executor content in `plugins/autopilot/**`, `scripts/skalary/{PlanState,DirectWorkflow}.psm1`, applicable app project instructions.

  **Constraints:** phase kickoff explicitly sets `model: gpt-6.1-sol`, `reasoning_effort: high`, `context_tier: default`, and an execution mode that does not pause for a second implementation plan. Bind canonical plan, phase, source branch, and exact expected commit. Workers never recursively launch the coordinator.

  **Verify:** policy/contract tests cover kickoff settings, missing native-tool refusal, worker boundaries, criteria-baseline admission, and phase versus finalization ownership.

  **Stop/escalate when:** admission cannot distinguish the coordinator from a worker, or the host cannot create an isolated child at the exact source commit.

  </details>
- [ ] 2.2 Verify committed phase closure and fast-forward the integration branch (REQ-5, REQ-6, REQ-7, RISK-2, RISK-3) [after: 2.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** only verified phase commits reach the integration branch; dependent work starts from that accepted head.

  **Likely touchpoints:** CI app asset, `Get-PhaseExecutionState.ps1`, existing Git/admission helpers, focused tests in `tests/skalary/`.

  **Constraints:** run children serially; keep the integration checkout unchanged while a child runs; inspect live state and commit/phase evidence rather than treating idle or a message as success. Use local fast-forward integration; unexpected divergence stops. Do not create phase PRs, stash user work, resolve conflicts silently, or archive work-bearing children without authorization.

  **Verify:** disposable Git fixtures prove exact-head handoff, incomplete/dirty close refusal, branch divergence refusal, no duplicate integration, and recovery after integration occurred but the coordinator turn ended.

  </details>

## Phase 3: Unattended readiness, decisions, and epic execution

- [ ] 3.1 Execute dependency-ready AI work around human blockers and record bounded decisions (REQ-8, REQ-9, REQ-10, RISK-4) [after: 2.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** unattended execution exhausts reachable admitted AI work, preserves human-dependent work, and produces one concise decision/blocker handoff.

  **Likely touchpoints:** CI coordinator/worker instructions, `PlanState.psm1` admission/dependency helpers, `DirectWorkflow.psm1` confinement helpers, plan scaffold contract.

  **Constraints:** select dependency-ready AI siblings within the first unfinished phase. Every earlier phase must close before a later phase is admitted; missing dependency annotations grant no exemption. Allow partial-phase work where independent AI steps remain; create a new phase child on a later admitted visit rather than reusing completed worker context. A partially blocked phase is not closed. The decision log is mutable execution history, not confirmed criteria.

  **Verify:** fixtures cover a human step with an independent AI sibling, a dependent AI step, a later phase blocked despite having no explicit unmet dependencies and admitted only after earlier-phase closure, no-ready-work exhaustion, and material ambiguity that cannot be decided unattended.

  **Stop/escalate when:** advancing independent work requires weakening a confirmed prerequisite or changing intent, acceptance, or scope.

  </details>
- [ ] 3.2 Route epic children through the same coordinator and local completion proof (REQ-11, REQ-12, RISK-5) [after: 3.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/ci <epic-id>` selects dependency-ready child plans and executes them through the app path without invoking the host-only wrapper.

  **Likely touchpoints:** `PlanState.psm1` epic rollup/admission, reusable portions of `EpicAutopilot.psm1`, `Invoke-EpicAutopilot.ps1` retirement, `Archive-Epic.ps1`, `tests/{skalary,autopilot}` epic tests.

  **Constraints:** retain plan identity, child dependencies, criteria checks, close checks, and archive confinement. Each child plan has its own terminal finalization target. After all child finalization commits are integrated and all children archived, the coordinator owns one epic Goal/Definition-of-done/coherency check and epic-index archival. Local committed/integrated child completion replaces mandatory per-child provider PR proof for new app runs; old archived histories remain history. Publish at most one final PR for the requested epic run, not one PR per phase or child.

  **Verify:** epic fixtures cover a blocked child plus a ready sibling, local completed-child proof, all-closed unarchived children still requiring finalization, finalized archived children skipped without child PRs, pending epic completion after all child archives, unchanged completed epic boundaries not repeated, and no host launcher dispatch.

  </details>

## Phase 4: Completion ownership and legacy retirement

- [ ] 4.1 Give each plan one finalization child and the coordinator the final PR handoff (REQ-12, REQ-13, RISK-3, RISK-5) [after: 3.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** each fully closed standalone or epic-child plan is finalized once; the source, learning, and archive commits are integrated before the coordinator publishes the single final PR for the requested run.

  **Likely touchpoints:** CI completion asset, compaction instructions moved from autopilot, `Get-DesignNoteCompactionContext.ps1`, `Write-RecentLearning.ps1`, `Archive-Plan.ps1`, final review consumers.

  **Constraints:** keep active current-run evidence, one unchanged-scope terminal review, conditional compaction, criteria protection, and explicit push guards. Headless execution skips optional PFB. Cross-note merge/delete and other unresolved human gates stop visibly. Phase dispatch is not counted as a review/escalation call; bounded role retries remain bounded. No GitHub PR merge or deployment is authorized.

  **Verify:** completion fixtures cover pending phases, all-closed unarchived plans that still require finalization, finalized archived plans that are skipped, human finalization gates, learning-before-archive ordering, archive-path re-resolution, and prevention of duplicate per-plan finalization or requested-run publication.

  </details>
- [ ] 4.2 Retire the standalone autopilot runtime and migrate its active consumers (REQ-14, REQ-15, RISK-6) [after: 4.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** continue-implementation owns the retained executor/helper payloads; no active app execution path, dependency, or documentation requires the removed runtime.

  **Likely touchpoints:** `plugins/{autopilot,continue-implementation}/plugin.json`, `registry-retirements.json`, launcher/config/container assets, model generator ownership lists, Skalary config catalog/readers, affected factory-loop integration contracts and tests.

  **Constraints:** use the existing retirement and receipt-pinned removal protocol; avoid destination ownership collisions. Remove obsolete source/dogfood payloads through their owners, not arbitrary recursive cleanup. Preserve archived plans/ledgers and unrelated CLI packaging/eval tooling. Do not delete a consumer's local configuration or credentials. Explain unsupported old execution-mode markers and obsolete user-owned configuration explicitly.

  **Verify:** focused retirement/install/update fixtures, generator ownership checks, active-reference checks, and config-category tests prove clean new installs and an explicit migration path for existing installs.

  **Stop/escalate when:** a live consumer of a deleted launcher cannot be migrated without removing unrelated behavior; identify it rather than ship a dangling reference.

  </details>

## Phase 5: Distribution, documentation, and acceptance

- [ ] 5.1 Converge distribution and update active architecture/operator guidance (REQ-1, REQ-14, REQ-15, REQ-16, RISK-6) [after: 4.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** installed CI payloads match canonical sources; active contracts and operator docs describe the one app path and Sol policy.

  **Likely touchpoints:** canonical manifests, `Sync-PluginScripts.ps1`, registry/marketplace/dogfood generators, affected architecture/design notes, `docs/operator-guide/**`, README and repository instructions where structure changes.

  **Constraints:** do not rewrite archived plans or historical pricing/model facts. Follow the distribution owner's generator/version order and skill-size limits. Keep locked contracts intact; the affected direct-workflow contract is provisional and must be updated with this change.

  **Verify:** detect-only model/bundle/registry/marketplace/dogfood checks, focused consumer installation tests, and affected documentation/reference checks.

  </details>
- [ ] 5.2 Run the regression matrix and prepare the bounded live app smoke (REQ-6, REQ-7, REQ-8, REQ-9, REQ-11, REQ-12, REQ-16) [after: 5.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** deterministic tests cover readiness, integration, resume, completion, and migration; an operator can execute the exact live smoke without guessing setup or success conditions.

  **Likely touchpoints:** existing focused Git/consumer fixtures, affected tests under `tests/{skalary,autopilot,evals,factory-loop}`, operator acceptance guidance.

  **Constraints:** prefer existing runners and small fixtures; no new scheduler, state journal, dynamic workflow, or provider API. Static prompt tests cannot prove native app session creation or model settings.

  **Verify:** focused suites pass; live acceptance instructions specify a disposable confirmed two-phase plan, a human-blocked independent step, exact expected heads, visible child settings, phase closures, and one finalization handoff.

  </details>

## Phase 6: Live app acceptance

- [ ] 6.1 Confirm native child execution, human blocking, and local integration in the app (REQ-4, REQ-6, REQ-8, REQ-9, REQ-12, REQ-16, RISK-7) @human [after: 5.2] `M`
  <details><summary>Operator acceptance</summary>

  **Steps:**
  1. Approve a disposable app smoke session based on the implementation commit, with the documented confirmed two-phase fixture. Keep it isolated from unrelated work.
  2. Run unattended `/ci`; inspect each child for GPT-6.1 Sol, high effort, default context, isolated worktree, and the exact expected starting commit.
  3. Verify independent AI work proceeds around the fixture's human blocker while dependent work remains pending and no phase is falsely closed.
  4. Resolve that fixture blocker, resume, and verify a fresh admitted worker continues without repeating completed work, both phase closures are integrated locally, and only one finalization target runs.
  5. Inspect the decision handoff and final PR boundary. Do not merge a GitHub PR or deploy as part of this smoke.

  **Verify:** native session settings and Git heads match the acceptance instructions; no CLI runtime is launched, recursive phase coordinator is spawned, duplicate phase integration/finalization occurs, or human-dependent work is marked done.

  **Rollback:** stop the disposable smoke sessions, retain their commits/worktrees for inspection, and leave the implementation and delivery branches unchanged. Remove smoke artifacts only with explicit operator authorization.

  </details>
