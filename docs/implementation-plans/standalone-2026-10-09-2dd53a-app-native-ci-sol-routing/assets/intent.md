# Intent

## Goal

Deliver app-first phase coordination: replace the app's direct/in-context and standalone local host orchestration with verified native local phase sessions. Retain VS Code's existing execution route until its replacement is proven, and retain container and Windows Sandbox autopilot with CLI internally. Prefer GPT-6.1 Sol throughout existing model categories because of the operator's current cost preference.

## Desired outcome

- `/ci` in the app coordinates a confirmed plan/epic using local native phase sessions, container workers or Windows Sandbox workers and shared executor rules. VS Code keeps its existing route with no app-only tool dependency.
- New app-coordinated phase workers use GPT-6.1 Sol, high reasoning, default context in each environment; isolated workers run CLI internally without manual CLI interaction. Retained VS Code execution keeps its existing effort/context/configuration behavior with the global Sol alias migration.
- Interactive and unattended runs differ in decision policy; one coordinator dispatches environment-specific workers.
- The coordinator integrates accepted phases locally, continues dependency-ready work around human blockers, and publishes one final PR for the requested run.
- All six existing model aliases resolve to GPT-6.1 Sol; existing category effort settings remain initially.

### Selected operator wording and confirmed interpretation

- Source/date: this session, 2026-10-09.
- Operator wording:

  > ok, this will be unattended run of the implementation. you will orchestrate the implementation of all parts of the plan which are not depending on human input as far as possible. if there are decisions you will make along the way, record them on unattended-decissions.md in plan assets and present them when done.
  >
  > each phase of the plan will be executed in new subsession gpt 6.1 sol high default, you will orchestrate the merges of phases and execution of the next phases.

  > i think this would replace and merge in context autopilot and host autopilot, i do not use copilot cli anymore, only copilot app

  > with current pricing it makes most sense for me to use sol 6.1 for almost everything and tune just the effort level
  >
  > we want to update those models too, to use gpt 6.1 sol, because it is most cost effective way right now

- Confirmed selections: "App-only replacement (Recommended)"; "Local integration; one final plan PR (Recommended)"; "Create implementation plan (Recommended)"; "GPT-6.1 Sol for all categories (Recommended)".
- Correction/source: this session, 2026-10-10. Operator wording:

  > wait wait, we want to keep container autopilot and sandbox autopilot. can we use copilot app instead of cli there?

- Selected correction: "Yes—app interface, isolated CLI workers (Recommended)" in response to whether retaining CLI internally is acceptable when the app initiates and coordinates the run.
- Additional operator wording, 2026-10-10:

  > so: we keep working container and sandbox autopilot, only things replaced are in context and host autpilot. btw, how will this affect running in vscode? i think there should be now same harness in copilot app and vscode, so i hope all will work fine

- Selected host requirement: "Support app and modern VS Code Copilot (Recommended)". Verify actual full-session creation/observation/handoff, not shared-harness inference; add live VS Code acceptance and explicit capability-stop behavior.
- Selected rollout correction, 2026-10-10: "App-first; retain VS Code’s existing route (Recommended)" after VS Code 1.141 native session tools did not establish explicit per-worker effort/context/base controls. Implement exact-setting native phase sessions in the app; keep VS Code's current execution until its replacement is proven.
- Confirmed interpretation: migrate app local/epic orchestration; retain VS Code's current route and any host/epic/factory payload it needs. Retain container/Sandbox plugin/config/auth/offline/usage surfaces. Keep serial app integration and all Sol aliases/current effort defaults. Separate-context review remains, not model diversity.
- Scope/exception: app-first supersedes the simultaneous two-client replacement/live-native-VS-Code gate, not VS Code preservation. Do not infer support from shared harness or silently move VS Code to app tools. No native remote attachment is promised. New app phase settings stay high/default, Routine medium. Preserve the exact `unattended-decissions.md` filename.

## Success signals

- Local native children and isolated CLI workers start at exact accepted commits; only verified committed phase closures are integrated. Isolated commit transport is accepted locally before advancing.
- Human-dependent work stays pending; independently admitted AI work proceeds without weakening phase gates or dependencies.
- Each standalone or epic-child plan has one terminal workflow owning final review, compaction when applicable, learning, and plan archival. The coordinator owns the subsequent epic-level completion check/archive and one requested-run PR.
- No app coordinator invokes a competing standalone host/epic loop. Keep existing host/epic/factory launchers while VS Code or another unmigrated consumer needs them. Container/Sandbox retain isolation, configuration, authentication, offline handling and exact usage.
- Generated model consumers resolve all six aliases to the requested model.
- Bounded live local-app, container and Sandbox smokes prove actual worker settings, isolation and integration; static tests are not presented as that proof.
- A VS Code preservation gate proves its existing local/epic/isolated routes remain usable without app tools. New VS Code native phase coordination is deferred, not simulated with subagents or inherited settings.

## Non-goals

- Parallel phase writers, automatic conflict resolution, or a new scheduler/journal/receipt system.
- Automatic GitHub PR merging, production deployment, or authorization to perform human steps.
- Changing confirmed plan criteria during unattended execution.
- Rewriting archived plans, old credit ledgers, or historical model/pricing records.
- Removing unrelated CLI packaging, Waza, or cross-host planning/review support.
- Retiring the autopilot plugin, container or Windows Sandbox execution; replacing those environments with app process sandboxing/cloud sandboxes; or requiring unverified native remote attachment.
- Guaranteeing compatibility with VS Code's legacy Local extension-host harness, or inventing absent client session tools/extension integrations.
- Delivering new VS Code native phase orchestration or changing its existing worker settings in this app-first run.
- Inventing app usage statistics or unsupported eval effort configuration.
- Changing category effort defaults beyond the already selected high/default phase-worker setting.

### Delegated discretion and deferred choices

- Authorized choice and bounds: reuse or locally extract existing admission, confinement, close, archive, and model-generation helpers. Choose compact installed assets and executor naming without adding a framework. Record execution decisions with affected step/criterion, rationale, and consequence.
- Fixed boundaries: exact app phase-worker settings, serial local worktrees or selected container/Sandbox workers, app fast-forward integration, retained VS Code/isolated runtime contracts, no silent human-step completion, one final PR, and all aliases using Sol.
- Deferred choice, owner, and resolve-or-stop condition: a material new scope/acceptance decision belongs to the operator through `/cip`; preserve progress and stop that affected work. Other independently admitted work can proceed if the stop does not invalidate its baseline or prerequisites.
- Model unavailable: stop the affected call visibly rather than redirect to a different model or pretend a same-model alias is a fallback.
- Live local native-tool and retained container/Sandbox acceptance require the operator's isolated smoke approval after implementation; these are human gates, not synthetic automated evidence.
- VS Code replacement is deferred; missing native settings proof does not block app implementation. Keep its current route and required launchers. A future replacement requires its own confirmed criteria and live capability proof before removal.
- Operator-selected pre-confirmation correction: independent AI siblings may proceed within the first unfinished phase, and independently admitted epic siblings may proceed. Later phases wait for every earlier phase to close, even without an explicit unmet dependency annotation.
- Operator-selected pre-confirmation correction: finalize each child plan once, then perform the coordinator-owned epic completion check and index archival; retain one final PR for the requested run.

## Definition of done

Source, distribution, docs, deterministic regressions and live app/local/container/Sandbox acceptance agree on app coordination and Sol routing. Live VS Code preservation confirms its existing route remains usable. New VS Code native orchestration is explicitly deferred and is not a completion blocker; required app and preservation gates remain blocking.
