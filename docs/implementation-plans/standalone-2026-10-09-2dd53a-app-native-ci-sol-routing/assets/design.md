# Design

## Outcome and proposed behavior

App-first `/ci` selects native local app sessions or retained container/Windows Sandbox CLI workers. VS Code retains its current execution/config route until native replacement is proven. CI owns explicit client routing and shared worker primitives; the operator uses the client, not a manual CLI workflow. Reuse helpers/launchers, not another framework. Requirements and acceptance are in [requirements.md](requirements.md); selections are in [decisions.md](decisions.md).

Model aliases keep their public names for compatibility but all bind to GPT-6.1 Sol. The initial effort policy remains Routine medium and Standard/Deep/Independent high. Phase and finalization kickoff explicitly uses high effort/default context. Existing distinct planning-review contexts remain distinct; unavailable Sol stops visibly rather than dispatching a same-model fallback alias.

## Components and boundaries

| Component | Responsibility |
|---|---|
| CI skill and small installed client assets | App coordinator/environment/settings/integration; explicit preserved VS Code route without app dependencies |
| Shared direct executor | Admitted phase work, focused validation, atomic source/checklist commits, explicit blocked outcomes |
| Local app worker | Fresh native app session/worktree, replacing app in-context and standalone host orchestration |
| Preserved VS Code route | Existing direct/host/epic/isolated behavior and required payloads; native replacement deferred |
| Retained isolated runtime | Docker or Windows Sandbox CLI phase/completion invocation with existing auth, toolchain, offline/rebundle, output and usage handling |
| Existing plan helpers | Criteria baseline, dependency/phase admission, committed close and archive state |
| Existing epic helpers | App dependency-ready child selection/local completion without host dispatch; preserved VS Code wrapper/proof |
| Per-plan finalization worker | Current final evidence/review, conditional compaction, learning and plan archival, once for each standalone or epic-child plan |
| Coordinator completion/delivery | Integrate finalization commits, perform the distinct epic completion check/index archival when applicable, preserve explicit push guards, create at most one requested-run PR |
| Model allowlist and owner generators | One model authority and consistent skill/eval bindings |

Avoid custom app extensions, dynamic workflows, generic configuration frameworks, automatic cleanup, extra persisted lifecycle state, and parallel integration branches. Use native tools for local sessions and existing controlled launchers/transfers for explicitly selected isolated workers. Do not claim those workers are native app child sessions. App local process sandboxing and cloud sandboxes are not replacements for these Docker/Windows Sandbox environments.

## Program flow

This flow describes the new app route. VS Code keeps its existing local/epic/runtime orchestration and completion.

```mermaid
flowchart TD
    A[Resolve plan or epic and check criteria] --> B[Inspect committed progress and existing child state]
    B --> C{Dependency-ready AI work?}
    C -->|Yes| D[Start fresh local app or selected container or Sandbox phase worker at exact HEAD]
    D --> E[Observe owned worker and verify committed result locally]
    E --> F{Accepted progress or full phase close?}
    F -->|Yes| G[Fast-forward integration branch and record bounded decisions]
    G --> B
    F -->|Failure or divergence| H[Preserve work and report blocker]
    C -->|No| I{All required phases closed?}
    I -->|No| H
    I -->|Yes| J[One finalization worker in the selected environment per completed plan]
    J --> K{Current completion gates pass?}
    K -->|No| H
    K -->|Yes| L[Integrate learning and archive commits]
    L --> N{Requested run is an epic?}
    N -->|No| M
    N -->|Yes| P{All children finalized and archived?}
    P -->|No| B
    P -->|Yes| O[Check epic Goal and Definition of done then archive index]
    O --> M[One requested-run PR and decision handoff]
```

### Client capability boundary

The SDK-backed harness is shared; tools are not identical. Keep app/preserved-VS-Code routing in installed CI; app project settings are supplemental. VS Code 1.141 exposes native orchestration but its creation schema lacks explicit effort/context/base controls; current session metadata cannot prove effective worker settings. See the version-pinned execution decision log.

Operator-selected app-first correction permits implementation without simultaneous VS Code native replacement. App tools must still bind/observe exact sessions/settings/source. Preserve VS Code's current route and needed host/epic/factory launchers, not a silent fallback. Its live gate proves preservation only. Future native replacement requires separately confirmed capability/acceptance criteria; inheritance, manual UI or subagents are not current proof.

### Handoff and resume

Before app dispatch, inspect cleanliness/source HEAD. App children bind `base_branch` to integration; isolated workers bind that commit through retained preparation. Workers recheck HEAD/isolation. New app workers use Sol high/default and fresh phase context with no competing loop. Preserved VS Code workers keep existing effort/context behavior under Sol aliases.

Do not mutate the integration checkout while the worker runs. The worker produces source/checklist commits on its isolated branch. Container/Sandbox outputs return via existing controlled Git/artifact transfer; preserve commit ancestry and verify exact commits locally before acceptance. Retain explicit transport-push permissions, but workers do not create phase/child PRs. Do not transport credentials or broad mapped host state. The coordinator verifies criteria remain unchanged, exact phase scope, current focused evidence, clean committed checklist progress, and ancestry before `git merge --ff-only`. Dirty state, out-of-scope changes, missing/corrupt transport, source movement, or divergence stops with recoverable work.

Idle is only a native turn boundary. Read authoritative native session activity or the isolated worker's owned process/container state and launcher outcome, plus phase/commit state. Transcripts, sentinels and exit markers alone do not establish committed acceptance. Keep completed, blocked/operator-action 42, offline-rebundle 43 and other failures distinct. A runtime exit 42 with committed partial work is not automatically acceptance or permission to continue: inspect its named blocker and revalidate unaffected work. Do not duplicate an active worker. On resume, reconcile known native child or runtime identity with committed source state. If integration already occurred, do not integrate or execute it again. Ambiguous active ownership requires operator reconciliation rather than another writer. Use native session context and existing launcher/output/Git state, not a new recovery journal. Keep exact isolated usage sidecar import idempotent, including archive-path re-resolution.

### Human blockers and decisions

Within the first unfinished phase, run independent admitted AI siblings even if a human step is pending. Later phases require every earlier phase to close, including pending human work; missing explicit dependencies grant no exemption. Independently admitted epic siblings can still proceed. Apply this shared policy to all three environments. A worker can return committed accepted partial progress without closing the phase. A later visit creates a fresh native child or isolated CLI invocation.

Implementation discretion may choose bounded details and record them in the requested filename. Each entry names the affected step/criterion, decision, rationale, and consequence. Use existing confinement/secret-screening patterns. Write coordinator entries between integrations, never during a worker's source-bound interval. The log is not part of immutable planning criteria and does not authorize new scope.

A material ambiguity preserves affected work and returns to the operator/CIP confirmation flow. Continue only other work whose independent baseline and prerequisites remain valid. Exhaustion reports completed work, blockers and pending human actions, and decisions; it is not whole-plan success.

### Completion and epic delivery

One explicit finalization worker in the selected environment follows all closed phases of each standalone or epic-child plan: a native child locally or fresh CLI completion invocation inside the container/Sandbox. It owns unchanged-scope terminal review, conditional design-note compaction, learning publication, and plan archive move/commit. Preserve explicit human gates; headless execution skips optional PFB. The coordinator verifies/imports and integrates those commits and owns the only final PR. Retain exact CLI usage recording for isolated targets; do not fabricate local app usage. An all-closed unarchived plan still requires finalization; a finalized archived plan is skipped without requiring a child PR. Do not repeat an unchanged completed boundary.

Epic children each use that complete plan lifecycle and serial phase workers. After all child finalization commits are integrated and all children archived, the coordinator performs one distinct epic Goal/Definition-of-done/coherency check, refreshes the index, and archives/commits the epic index. Pending epic completion still runs on an all-child-archives resume; unchanged completed epic boundaries and existing delivery are not repeated. For new app runs, committed local closure integrated into the requested run's branch replaces the old requirement for a provider PR for every child. Only the final requested run has a delivery PR. Archived legacy plans/epics remain readable without rewriting their historical proof or relaunching them.

### Retained runtimes and local orchestration replacement

CI owns app coordination and preserved VS Code routing; keep autopilot/dependency for shared executor/helpers and runtime payloads. One owner, no duplicate executors/receipt transfer. App-first supersedes simultaneous replacement; migrate app callers, not VS Code to unverified tools.

Preserve container/Sandbox contracts and host/epic/factory launchers needed by retained consumers. App coordinator bypasses competing loops; delete only proven unused app-only paths. Never retire required payloads because app execution becomes native. Existing config, credentials, receipts and archived ledgers stay untouched except authorized owner migration.

App CI selects native local/container/Sandbox explicitly; app host selection maps to app sessions. VS Code keeps host and isolated selections/config without app tools. No global remap, isolation downgrade or unavailable-app CLI fallback. Preserve unrelated tooling and exact isolated usage; never fabricate client accounting.

Run the owning model, script-bundle, registry, marketplace, and dogfood generators; do not hand-edit generated copies. Update active direct-workflow architecture, execution/plan/customization/config notes, operator guides, and README/instructions when structure changes.

## Tradeoffs and open choices

- One model reduces configured model diversity; independent contexts remain useful but cannot be called cross-model corroboration.
- Retaining current role efforts avoids changing model and effort behavior simultaneously. Later effort tuning stays in the same policy; no second model-config file is introduced.
- Serial fast-forward integration is simpler than phase PR orchestration, but phase acceptance is local; final GitHub review remains the delivery boundary.
- Preserving earlier-phase closure limits unattended progress when a human step blocks that phase, even if later work appears independent. Ready AI siblings in the current phase and independently admitted epic siblings still proceed; no cross-phase exemption is added.
- No recovery journal means ambiguous lost-session ownership stops for the operator rather than risking a duplicate writer.
- The operator works in the selected app/VS Code client, but isolated workers remain CLI processes rather than native child sessions. Native remote/container/Sandbox attachment is not promised or required.
- App-first rollout temporarily keeps different orchestration routes. VS Code preservation, not native replacement, is required now; future replacement needs separately confirmed proof.
- App mode keeps launch/auth/offline mechanisms, not competing plan coordinators: one app coordinator owns admission/integration and isolated launchers execute bounded targets. Existing VS Code/factory loops remain for their retained consumers.
- Native-tool/launcher contract tests are necessary but insufficient. Explicit live local, container and Windows Sandbox smokes are human gates.
- No remaining intent choice is delegated silently. Newly discovered material choices use the existing confirmation flow.

## Optional call stacks

The flow above is sufficient; no additional runtime layer is proposed.
