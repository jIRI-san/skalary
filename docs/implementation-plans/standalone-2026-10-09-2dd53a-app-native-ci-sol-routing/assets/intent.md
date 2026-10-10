# Intent

## Goal

Replace the competing direct/in-context and host-autopilot CI execution routes with one Copilot-app-native coordinator. Prefer GPT-6.1 Sol throughout the existing model categories because of the operator's current cost preference.

## Desired outcome

- `/ci` coordinates a confirmed plan or epic using fresh isolated app phase sessions and one shared executor.
- Phase workers use GPT-6.1 Sol, high reasoning, default context; independent review contexts use the same model rather than another model family.
- Interactive and unattended runs differ in decision policy, not execution engines.
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
- Confirmed interpretation: retire the old execution routes and migrate epic callers; use serial phase children and local fast-forward integration; map primary and secondary aliases to Sol while retaining current effort settings initially. Separate-context review remains, but different-model diversity and model-availability fallback do not.
- Scope/exception: app-only applies to `/ci` execution, not unrelated CLI tooling for plugin lifecycle or evals. Phase settings remain high/default even though Routine has medium effort. The exact supplied `unattended-decissions.md` filename is preserved.

## Success signals

- Native children start at exact accepted commits; only verified committed phase closures are integrated.
- Human-dependent work stays pending; independently admitted AI work proceeds without weakening phase gates or dependencies.
- Each standalone or epic-child plan has one terminal workflow owning final review, compaction when applicable, learning, and plan archival. The coordinator owns the subsequent epic-level completion check/archive and one requested-run PR.
- No active execution route or epic caller launches the removed runtime.
- Generated model consumers resolve all six aliases to the requested model.
- A bounded live app smoke proves actual session creation/settings and integration; static tests are not presented as that proof.

## Non-goals

- Parallel phase writers, automatic conflict resolution, or a new scheduler/journal/receipt system.
- Automatic GitHub PR merging, production deployment, or authorization to perform human steps.
- Changing confirmed plan criteria during unattended execution.
- Rewriting archived plans, old credit ledgers, or historical model/pricing records.
- Removing unrelated CLI packaging, Waza, or cross-host planning/review support.
- Inventing app usage statistics or unsupported eval effort configuration.
- Changing category effort defaults beyond the already selected high/default phase-worker setting.

### Delegated discretion and deferred choices

- Authorized choice and bounds: reuse or locally extract existing admission, confinement, close, archive, and model-generation helpers. Choose compact installed assets and executor naming without adding a framework. Record execution decisions with affected step/criterion, rationale, and consequence.
- Fixed boundaries: exact phase-worker settings, serial isolated worktrees, local fast-forward integration, no silent human-step completion, one final PR, and all aliases using Sol.
- Deferred choice, owner, and resolve-or-stop condition: a material new scope/acceptance decision belongs to the operator through `/cip`; preserve progress and stop that affected work. Other independently admitted work can proceed if the stop does not invalidate its baseline or prerequisites.
- Model unavailable: stop the affected call visibly rather than redirect to a different model or pretend a same-model alias is a fallback.
- Live native-tool acceptance requires the operator's isolated smoke approval after implementation; it is explicitly a human gate, not synthetic automated evidence.
- Operator-selected pre-confirmation correction: independent AI siblings may proceed within the first unfinished phase, and independently admitted epic siblings may proceed. Later phases wait for every earlier phase to close, even without an explicit unmet dependency annotation.
- Operator-selected pre-confirmation correction: finalize each child plan once, then perform the coordinator-owned epic completion check and index archival; retain one final PR for the requested run.

## Definition of done

Source, generated distribution, active documentation, deterministic regression coverage, and live app acceptance agree on the one app-native execution path and Sol policy. The plan cannot be reported completed while the explicit live acceptance gate is pending.
