# 2dd53a: App-native CI execution and GPT-6.1 Sol routing
<!-- plan-id: 2dd53a -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:e50b57fe032cb4fdd9e4ba2fc9251905f2fb2708a9ff4491644d84bc29b5726a -->
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

- [x] 1.1 Map all six public aliases to GPT-6.1 Sol and make replacement semantics honest (REQ-1, REQ-2, RISK-1) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** primary and secondary aliases use `gpt-6.1-sol` / `GPT-6.1 Sol (copilot)`; existing Routine medium and Standard/Deep/Independent high effort settings remain.

  **Likely touchpoints:** `tools/model-allowlist.psd1`, model/review skill instructions, `scripts/skalary/{Sync-ModelBindings,Test-ModelAllowlist}.ps1`, `tests/skalary/ModelAllowlist.Tests.ps1`.

  **Constraints:** preserve the six public alias names; resolve host identifiers explicitly; a same-model alias is not an availability fallback. Review independence means a separate context, not a different model.

  **Verify:** focused alias/effort and unavailable-model regressions prove each binding and visible refusal without retrying an unavailable Sol through another alias.

  **Stop/escalate when:** a host cannot accept the exact requested model identifier; do not silently select an older or different model.

  </details>
- [x] 1.2 Regenerate model consumers and update directly affected guidance (REQ-1, REQ-2, RISK-1) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** generated skill assets and Waza executor/judge bindings use the same policy; planning/review instructions no longer promise cross-model diversity.

  **Likely touchpoints:** `Sync-ModelBindings.ps1`, declared model assets, `plugins/*/evals/waza/**`, model configuration catalog, affected design notes.

  **Constraints:** use owner generators and the source-first distribution sequence; do not add unsupported Waza effort fields or change eval tool pins, approval gates, or pricing claims.

  **Verify:** model binding check, model allowlist check, focused model consumers, and applicable deterministic eval-schema checks.

  </details>

## Phase 2: App coordinator and isolated phase integration

- [ ] 2.1 Unify CI coordination across app/VS Code and retained isolated workers (REQ-3, REQ-4, REQ-5, REQ-12, REQ-17, REQ-18, RISK-2, RISK-9) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/ci` in the app or modern VS Code Copilot selects a confirmed plan, extent, and explicit environment: fresh native local sessions, Docker workers, or Windows Sandbox workers. Both clients and both autonomy modes share coordinator/executor policy; retained isolated workers use CLI internally without manual CLI interaction.

  **Likely touchpoints:** `plugins/continue-implementation/skills/ci/**`, small app/VS Code host-specific instruction assets, shared executor in `plugins/autopilot/**`, `scripts/skalary/{PlanState,DirectWorkflow}.psm1`. App-only project instructions cannot be the shared authority.

  **Constraints:** discover/verify actual modern VS Code full-session creation, model/effort/context configuration, observation and handoff before claiming support; record the supported target/version and capability evidence. Shared SDK, UI session creation, or a same-context subagent alone is insufficient. Use small client-specific instruction routes, not a new framework. Local kickoff explicitly binds Sol high/default, canonical phase, exact source branch/commit and non-planning execution. Isolated workers bind equivalent flags through retained launchers. Dispatch one admitted phase visit/finalization, never a nested whole-plan loop. Workers never recursively coordinate; selected isolation is not a missing-native-tool fallback.

  **Verify:** capability evidence and policy/contract tests cover both clients, full local phase-session identity/isolation/settings, all three environment routes, unavailable-tool refusal, worker boundaries, criteria admission and phase/finalization ownership. Live acceptance is separate for each client.

  **Stop/escalate when:** a client cannot expose the required automatic full-session creation/observation/handoff or exact settings, admission cannot distinguish worker/coordinator, or the chosen environment cannot start at the exact commit. Report the capability gap for an operator decision before removing that client's local execution route; do not simulate success or silently fall back to in-context/host execution.

  </details>
- [ ] 2.2 Verify committed phase closure and fast-forward the integration branch (REQ-5, REQ-6, REQ-7, REQ-17, RISK-2, RISK-3, RISK-8) [after: 2.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** only verified phase commits reach the integration branch; dependent work starts from that accepted head.

  **Likely touchpoints:** CI app asset, `Get-PhaseExecutionState.ps1`, retained container/Sandbox result-transfer and target-dispatch seams, existing Git/admission helpers, focused tests in `tests/{skalary,autopilot}/`.

  **Constraints:** run workers serially; keep the integration checkout unchanged while a worker runs. For native children inspect live state; for isolated workers inspect owned process/container state and exact launcher outcomes. Neither idle, transcripts, sentinels nor messages alone prove success. Import isolated commits through the existing controlled Git/artifact transfer, preserving the expected-start ancestry; verify them locally before fast-forward. Do not transfer secrets or arbitrary mapped host state. Unexpected divergence stops. Workers do not create phase/child PRs; retain explicit permissions for any transport push. Do not stash user work, silently resolve conflicts, or discard work-bearing sessions/runtime outputs.

  **Verify:** disposable Git fixtures prove exact-head handoff, incomplete/dirty close refusal, branch divergence refusal, no duplicate integration, and recovery after integration occurred but the coordinator turn ended. Retained runtime fixtures also cover missing/corrupt result transport, nonzero/42/43 outcomes, and isolated commits remaining recoverable before local acceptance.

  </details>

## Phase 3: Unattended readiness, decisions, and epic execution

- [ ] 3.1 Execute dependency-ready AI work around human blockers and record bounded decisions (REQ-8, REQ-9, REQ-10, RISK-4) [after: 2.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** unattended execution exhausts reachable admitted AI work, preserves human-dependent work, and produces one concise decision/blocker handoff.

  **Likely touchpoints:** CI coordinator/worker instructions, `PlanState.psm1` admission/dependency helpers, `DirectWorkflow.psm1` confinement helpers, plan scaffold contract.

  **Constraints:** select dependency-ready AI siblings within the first unfinished phase. Every earlier phase must close before a later phase is admitted; missing dependency annotations grant no exemption. Allow partial-phase work where independent AI steps remain; create a fresh worker context on a later admitted visit. Apply the same policy to local, container and Sandbox execution; offline rebundle 43 remains distinct from operator action 42 or successful partial progress. A partially blocked phase is not closed. The decision log is mutable execution history, not confirmed criteria.

  **Verify:** fixtures cover a human step with an independent AI sibling, a dependent AI step, a later phase blocked despite having no explicit unmet dependencies and admitted only after earlier-phase closure, no-ready-work exhaustion, and material ambiguity that cannot be decided unattended.

  **Stop/escalate when:** advancing independent work requires weakening a confirmed prerequisite or changing intent, acceptance, or scope.

  </details>
- [ ] 3.2 Route epic children through the same coordinator and local completion proof (REQ-11, REQ-12, RISK-5) [after: 3.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** `/ci <epic-id>` in the app selects dependency-ready child plans and coordinates their chosen local/container/Sandbox workers without invoking a competing host-only epic orchestration loop.

  **Likely touchpoints:** `PlanState.psm1` epic rollup/admission, reusable portions of `EpicAutopilot.psm1`, `Invoke-EpicAutopilot.ps1` retirement, `Archive-Epic.ps1`, `tests/{skalary,autopilot}` epic tests.

  **Constraints:** retain plan identity, child dependencies, criteria checks, close checks, and archive confinement. Each child plan has its own terminal finalization target. After all child finalization commits are integrated and all children archived, the coordinator owns one epic Goal/Definition-of-done/coherency check and epic-index archival. Local committed/integrated child completion replaces mandatory per-child provider PR proof for new app runs; old archived histories remain history. Publish at most one final PR for the requested epic run, not one PR per phase or child.

  **Verify:** epic fixtures cover a blocked child plus a ready sibling, local completed-child proof, all-closed unarchived children still requiring finalization, finalized archived children skipped without child PRs, pending epic completion after all child archives, unchanged completed epic boundaries not repeated, and no host launcher dispatch.

  </details>

## Phase 4: Completion ownership and retained runtime integration

- [ ] 4.1 Give each plan one finalization child and the coordinator the final PR handoff (REQ-12, REQ-13, RISK-3, RISK-5) [after: 3.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** each fully closed standalone or epic-child plan is finalized once; the source, learning, and archive commits are integrated before the coordinator publishes the single final PR for the requested run.

  **Likely touchpoints:** CI completion asset, shared autopilot compaction instructions, retained container/Sandbox explicit completion targets, `Get-DesignNoteCompactionContext.ps1`, `Write-RecentLearning.ps1`, `Archive-Plan.ps1`, final review consumers.

  **Constraints:** use one native finalization child for local execution or one fresh CLI completion invocation in the selected container/Sandbox environment. Keep active current-run evidence, one unchanged-scope terminal review, conditional compaction, criteria protection, and explicit push guards. Headless execution skips optional PFB. Cross-note merge/delete and other unresolved human gates stop visibly. Phase dispatch is not counted as a review/escalation call; bounded role retries remain bounded. Record exact isolated CLI usage through the retained sidecar/ledger path; local app usage is not fabricated. No worker PR, GitHub PR merge or deployment is authorized.

  **Verify:** completion fixtures cover pending phases, all-closed unarchived plans that still require finalization, finalized archived plans that are skipped, human finalization gates, learning-before-archive ordering, archive-path re-resolution, and prevention of duplicate per-plan finalization or requested-run publication.

  </details>
- [ ] 4.2 Retain isolated autopilot and replace only competing local host orchestration (REQ-14, REQ-15, REQ-17, REQ-18, RISK-6, RISK-8, RISK-9) [after: 4.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** continue-implementation owns the app coordinator; autopilot remains the shared isolated executor/runtime plugin. Local native sessions replace standalone local host orchestration without removing container or Windows Sandbox support.

  **Likely touchpoints:** `plugins/{autopilot,continue-implementation}/plugin.json`, shared executor, `launch.ps1`, local host/epic launcher callers, retained container/Sandbox target dispatch and config schemas/templates, Skalary config catalog/readers, affected factory-loop integration contracts and tests.

  **Constraints:** do not retire the autopilot plugin or remove its dependency while CI uses its isolated payloads. Preserve container/Sandbox launchers, toolchains, auth, offline feeds/rebundling, config, exit contracts, and exact usage recording. Remove obsolete local orchestration only after app and modern VS Code replacement routes are established and live consumers, including factory repair, migrated. Capability failure stops rather than removing a still-needed route. Retain one owner per path and source-first removal semantics. Never delete user configs/credentials or alter history. Map legacy local host selection to the current client's native route; retain valid container/Sandbox selections.

  **Verify:** focused install/update, config, target-dispatch, container/Sandbox/offline/usage, and factory-consumer tests prove retained modes remain available and local orchestration has no dangling callers. Source/dogfood manifests retain their required runtime assets without destination collisions.

  **Stop/escalate when:** a live consumer of a deleted launcher cannot be migrated without removing unrelated behavior; identify it rather than ship a dangling reference.

  </details>

## Phase 5: Distribution, documentation, and acceptance

- [ ] 5.1 Converge distribution and update active architecture/operator guidance (REQ-1, REQ-14, REQ-15, REQ-16, RISK-6) [after: 4.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** installed CI/runtime payloads match sources; active contracts/operator docs describe one shared coordinator policy in app and modern VS Code Copilot, client-specific native local session routes, retained container/Sandbox execution and Sol routing.

  **Likely touchpoints:** canonical manifests, `Sync-PluginScripts.ps1`, registry/marketplace/dogfood generators, affected architecture/design notes, `docs/operator-guide/**`, README and repository instructions where structure changes.

  **Constraints:** do not rewrite archived plans or historical pricing/model facts. Follow the distribution owner's generator/version order and skill-size limits. Keep locked contracts intact; the affected direct-workflow contract is provisional and must be updated with this change.

  **Verify:** detect-only model/bundle/registry/marketplace/dogfood checks, focused consumer installation tests, and affected documentation/reference checks.

  </details>
- [ ] 5.2 Run the regression matrix and prepare bounded live smokes for all environments (REQ-6, REQ-7, REQ-8, REQ-9, REQ-11, REQ-12, REQ-16, REQ-17) [after: 5.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** deterministic tests cover readiness, integration, resume, completion, and local-host migration while preserving isolated runtime behavior; an operator can execute each live environment smoke without guessing setup or success conditions.

  **Likely touchpoints:** existing focused Git/consumer fixtures, affected tests under `tests/{skalary,autopilot,evals,factory-loop}`, operator acceptance guidance.

  **Constraints:** prefer existing runners and small fixtures; no new scheduler, state journal, dynamic workflow, or provider API. Static prompt tests cannot prove native app session creation or model settings.

  **Verify:** focused suites pass; live acceptance instructions specify disposable confirmed two-phase fixtures in app and supported modern VS Code, human-blocked independent work, exact expected heads, local session or isolated CLI settings, controlled transport, phase closures, exact usage where available and one finalization handoff. VS Code coverage names target/version and excludes the legacy Local extension-host harness.

  </details>

## Phase 6: Live app and isolated runtime acceptance

- [ ] 6.1 Confirm native child execution, human blocking, and local integration in the app (REQ-4, REQ-6, REQ-8, REQ-9, REQ-12, REQ-16, RISK-7) @human [after: 5.2] `M`
  <details><summary>Operator acceptance</summary>

  **Steps:**
  1. Approve a disposable app smoke session based on the implementation commit, with the documented confirmed two-phase fixture. Keep it isolated from unrelated work.
  2. Select local execution in unattended `/ci`; inspect each child for GPT-6.1 Sol, high effort, default context, isolated worktree, and the exact expected starting commit.
  3. Verify independent AI work proceeds around the fixture's human blocker while dependent work remains pending and no phase is falsely closed.
  4. Resolve that fixture blocker, resume, and verify a fresh admitted worker continues without repeating completed work, both phase closures are integrated locally, and only one finalization target runs.
  5. Inspect the decision handoff and final PR boundary. Do not merge a GitHub PR or deploy as part of this smoke.

  **Verify:** native session settings and Git heads match the acceptance instructions; no standalone local host launcher is used, recursive phase coordinator is spawned, duplicate phase integration/finalization occurs, or human-dependent work is marked done.

  **Rollback:** stop the disposable smoke sessions, retain their commits/worktrees for inspection, and leave the implementation and delivery branches unchanged. Remove smoke artifacts only with explicit operator authorization.

  </details>

- [ ] 6.2 Confirm app-coordinated container execution and retained isolation (REQ-4, REQ-6, REQ-12, REQ-16, REQ-17, RISK-7, RISK-8) @human [after: 5.2] `M`
  <details><summary>Container acceptance</summary>

  **Steps:**
  1. Approve the disposable confirmed Docker/auth/feed fixture; expose no credentials.
  2. From the app select container execution; inspect fresh Sol high/default CLI phases and exact HEAD inside Docker.
  3. Verify locally accepted commit transport, human-blocked partial progress and duplicate-free resume.
  4. Check one completion target, recoverable output, exact usage and bounded offline rebundle.

  **Verify:** fixture outcomes/settings/usage match; no manual CLI, native-attachment claim, isolation downgrade, worker PR or duplicate integration/finalization.

  **Rollback:** stop only the identified fixture container/process; preserve output/commits and unrelated resources/credentials/branches. Cleanup needs authorization.

  </details>

- [ ] 6.3 Confirm app-coordinated Windows Sandbox execution (REQ-4, REQ-6, REQ-12, REQ-16, REQ-17, RISK-7, RISK-8) @human [after: 5.2] `M`
  <details><summary>Windows Sandbox acceptance</summary>

  **Steps:**
  1. Approve the disposable confirmed Windows Sandbox fixture, host capability and explicit mappings/toolchain/auth.
  2. From the app verify fresh Sol high/default CLI phases at the exact commit inside Windows Sandbox.
  3. Check sentinel/exit versus local commit acceptance, human-blocker/resume and controlled transport.
  4. Verify one completion target, exact usage, offline rebundle and recoverable output.

  **Verify:** disposable Windows isolation, not app process sandboxing; no manual CLI, native-attachment claim, worker PR, duplicate work or lost output.

  **Rollback:** stop only the fixture Sandbox process; retain mapped output/commits and unrelated environments/config/credentials/branches. Cleanup needs authorization.

  </details>

## Phase 7: Live modern VS Code acceptance

- [ ] 7.1 Confirm local orchestration and retained runtime dispatch from VS Code (REQ-3, REQ-4, REQ-6, REQ-12, REQ-16, REQ-17, REQ-18, RISK-9) @human [after: 5.2] `M`
  <details><summary>VS Code acceptance</summary>

  **Steps:**
  1. Approve confirmed fixtures in the supported VS Code version/modern Copilot Agent Host target, not legacy Local.
  2. Verify automatic fresh full-session/worktree creation, Sol high/default, exact HEAD, observation and handoff; subagents/manual UI are insufficient.
  3. Check human blocker/independent sibling/resume, accepted fast-forwards, no duplicate writer and one terminal target/final PR.
  4. From VS Code run retained container/Sandbox fixtures; verify settings/transport/isolation without app-only tools or manual CLI.

  **Verify:** named host/version evidence proves native local and isolated dispatch; absent tools are blockers, not shared-SDK claims or legacy/manual fallback.

  **Rollback:** stop only fixture sessions/processes; retain commits/output and unrelated sessions/environments/config/branches. Cleanup needs authorization.

  </details>
