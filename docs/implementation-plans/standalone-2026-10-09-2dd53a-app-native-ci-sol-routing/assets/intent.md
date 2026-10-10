# Intent

## Goal

Replace competing direct/in-context and standalone local host orchestration with one shared coordinator policy usable in the Copilot app and modern VS Code Copilot. Use verified client-specific native local session tools; retain container and Windows Sandbox autopilot with CLI as their internal runtime. Prefer GPT-6.1 Sol throughout existing model categories because of the operator's current cost preference.

## Desired outcome

- `/ci` in the app and modern VS Code Copilot coordinates a confirmed plan/epic using explicitly selected local native phase sessions, container workers or Windows Sandbox workers and shared executor rules.
- Phase workers use GPT-6.1 Sol, high reasoning, default context in each environment; isolated workers run CLI internally without manual CLI interaction. Independent review contexts use the same model rather than another model family.
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
- Confirmed interpretation: replace only competing local orchestration; migrate epic callers to shared app/modern-VS-Code coordinator policy; retain container/Sandbox plugin/config/auth/offline/usage surfaces. Keep serial workers/local fast-forward integration; map all aliases to Sol with current effort defaults. Separate-context review remains, not model diversity or availability fallback.
- Scope/exception: the 2026-10-10 corrections supersede blanket host/container/Sandbox retirement and app-only client support. Operator interaction occurs in the selected app/modern-VS-Code client; internal CLI is allowed for isolated workers. No native remote attachment is promised. Phase settings stay high/default, Routine medium. Preserve the exact `unattended-decissions.md` filename.

## Success signals

- Local native children and isolated CLI workers start at exact accepted commits; only verified committed phase closures are integrated. Isolated commit transport is accepted locally before advancing.
- Human-dependent work stays pending; independently admitted AI work proceeds without weakening phase gates or dependencies.
- Each standalone or epic-child plan has one terminal workflow owning final review, compaction when applicable, learning, and plan archival. The coordinator owns the subsequent epic-level completion check/archive and one requested-run PR.
- No active local execution route or epic caller invokes a competing standalone host orchestration loop. Container/Sandbox execution retains isolation, runtime configuration, authentication, offline handling and exact CLI usage recording.
- Generated model consumers resolve all six aliases to the requested model.
- Bounded live local-app, container and Sandbox smokes prove actual worker settings, isolation and integration; static tests are not presented as that proof.
- Modern VS Code has its own verified local session route and live gate; client tool differences cannot silently break its retained runtime dispatch or be papered over with same-context subagents.

## Non-goals

- Parallel phase writers, automatic conflict resolution, or a new scheduler/journal/receipt system.
- Automatic GitHub PR merging, production deployment, or authorization to perform human steps.
- Changing confirmed plan criteria during unattended execution.
- Rewriting archived plans, old credit ledgers, or historical model/pricing records.
- Removing unrelated CLI packaging, Waza, or cross-host planning/review support.
- Retiring the autopilot plugin, container or Windows Sandbox execution; replacing those environments with app process sandboxing/cloud sandboxes; or requiring unverified native remote attachment.
- Guaranteeing compatibility with VS Code's legacy Local extension-host harness, or inventing absent client session tools/extension integrations.
- Inventing app usage statistics or unsupported eval effort configuration.
- Changing category effort defaults beyond the already selected high/default phase-worker setting.

### Delegated discretion and deferred choices

- Authorized choice and bounds: reuse or locally extract existing admission, confinement, close, archive, and model-generation helpers. Choose compact installed assets and executor naming without adding a framework. Record execution decisions with affected step/criterion, rationale, and consequence.
- Fixed boundaries: exact phase-worker settings, serial local isolated worktrees or selected container/Sandbox workers, local fast-forward integration, retained isolated runtime contracts, no silent human-step completion, one final PR, and all aliases using Sol.
- Deferred choice, owner, and resolve-or-stop condition: a material new scope/acceptance decision belongs to the operator through `/cip`; preserve progress and stop that affected work. Other independently admitted work can proceed if the stop does not invalidate its baseline or prerequisites.
- Model unavailable: stop the affected call visibly rather than redirect to a different model or pretend a same-model alias is a fallback.
- Live local native-tool and retained container/Sandbox acceptance require the operator's isolated smoke approval after implementation; these are human gates, not synthetic automated evidence.
- Modern VS Code capability discovery must establish an automatic fresh full-session/worktree route with exact settings, observation and handoff before removing its prior local route. Missing capability is an operator blocker, not permission for silent fallback or unsupported success claims.
- Operator-selected pre-confirmation correction: independent AI siblings may proceed within the first unfinished phase, and independently admitted epic siblings may proceed. Later phases wait for every earlier phase to close, even without an explicit unmet dependency annotation.
- Operator-selected pre-confirmation correction: finalize each child plan once, then perform the coordinator-owned epic completion check and index archival; retain one final PR for the requested run.

## Definition of done

Source, distribution, documentation, deterministic regressions and live app/modern-VS-Code/local/container/Sandbox acceptance agree on shared coordinator/executor rules, client-specific native session tools, retained runtime contracts and Sol routing. No explicit live acceptance or client-capability blocker may remain when declaring completion.
