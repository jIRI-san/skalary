# Unattended execution decisions

## 1.1: Preserve replacement slots without an availability retry

- Choice: retain existing `Fallback` keys and aliases; instruction consumers refuse equal-binding
  availability retries. No new model resolver or availability service.
- Rationale: current launchers resolve one configured alias and do not implement automatic fallback;
  six Sol bindings eliminate cross-model availability replacement.
- Consequence: existing configuration/API shape and bounded context-replacement budgets stay intact.
  Unavailable Sol is a visible stop; separate review contexts are not model diversity.

## 1.2: Keep unrelated Waza inventory failures out of the model migration

- Choice: leave two pre-existing `tests/evals/WazaCreditPolicy.Tests.ps1` failures unchanged.
- Rationale: confirmed baseline `e3099c88` already contains 28 tasks while the test expects 26,
  and a factory-loop `judge_model` with deterministic-only tasks. Model sync changes only identifiers,
  not task count, grader disposition or judge-field presence.
- Consequence: model acceptance uses the four named ModelAllowlist tests plus all 10 affected Waza
  convention fixtures, runtime/model and skill-contract regressions (161 passing tests).
  The wider credit-policy file remains non-clean; no whole-repository clean result is claimed.

## 2.1: Stop at the modern VS Code native-session settings boundary

- Choice: preserve every existing local/container/Sandbox route and leave 2.1 pending.
  Outcome is operator action `42`, not completion or proof that VS Code lacks orchestration.
- Evidence: the available `code --version` reports VS Code `1.141.0`, commit
  `2a59476c9bfcb90b3ddc372c36762471b7dfad1c`. The official source at that exact commit exposes
  native `create_session`, `list_sessions`, `get_session_context` and `send_message`.
  Full independent sessions/worktrees are supported; default `currentSession` creates a peer chat.
- Gap: the creation schema accepts relationship/prompt/workspace/worktree/title/model, not explicit
  reasoning effort, context tier, mode or starting branch/commit. `applyCreateSessionTool` copies
  provider configuration but an explicit model creates `{ id }`, not the source model's picker
  configuration. Omitting model instead inherits the source model/configuration; that is not the
  confirmed per-worker explicit Sol high/default binding. Serialized session metadata does not
  expose effective model effort/context for an automated verification step.
- Disconfirming evidence: the launcher supports picker/global reasoning overrides and context
  selection, but these are separate from the creation tool schema. Source inheritance could be an
  operator-approved alternative; no live evidence here proves exact effective settings or base HEAD.
  Documentation also retains confirmation requirements for session messaging; no bypass is assumed.
- Affected criteria: step 2.1, REQ-4 and REQ-18 require actual automatic full-session creation,
  exact settings, observation and handoff. Its stop condition requires an operator decision before
  old local route removal. REQ-14 forbids removal before both client replacements are established.
- Consequence: phase 1 is committed; orchestration/runtime migration has not started. A relaxed
  inheritance/setup contract or app-first rollout must return through affected CIP confirmation;
  otherwise retain the strict baseline and pause.

Sources (public, version-pinned implementation evidence; not live acceptance):

- [VS Code 1.141 session tools/schema and creation](https://github.com/microsoft/vscode/blob/2a59476c9bfcb90b3ddc372c36762471b7dfad1c/src/vs/platform/agentHost/node/shared/sessionServerTools.ts)
- [VS Code 1.141 effective effort/context resolution](https://github.com/microsoft/vscode/blob/2a59476c9bfcb90b3ddc372c36762471b7dfad1c/src/vs/platform/agentHost/node/copilot/copilotSessionLauncher.ts)
- [Official session orchestration and confirmations](https://code.visualstudio.com/docs/agents/run/sessions/manage-sessions#_orchestrate-sessions-from-agent-host-sessions)

## 2.1: Operator-selected app-first disposition

- Operator choice: "App-first; retain VS Code’s existing route (Recommended)".
- Consequence: correct only affected plan criteria through CIP confirmation. App exact-setting
  native coordination proceeds after reconfirmation; retain VS Code's current route/settings and
  required host/epic/factory payloads. Replace the simultaneous native VS Code gate with live
  preservation, not a completed native acceptance claim.
- Boundary: the capability stop above remains historical evidence. This disposition is not a
  confirmation stamp or permission to implement against stale criteria; baseline must pass first.

## 2.1-2.2: Reuse launchers with explicit app-only bounded modes

- Choice: retain existing launcher ownership and `next-phase`/`whole-plan` consumers; add explicit
  `app-phase`/`app-finalization` modes and one stateless result checker. No new scheduler or journal.
- Rationale: the app must bypass legacy PR-close loops without changing VS Code/factory behavior.
  Launch isolated workers from an owned transport checkout because existing transcripts/usage write
  locally. Verify exact retry HEAD separately from original-source ancestry after offline rebundling.
- Consequence: coordinator checkout stays unchanged while workers run; exact usage is committed in
  transport before local import. Git/checklist checks do not substitute for current scope/evidence.
  Six named app acceptance markers pass; live app/container/Sandbox and VS Code preservation remain
  pending human gates.
- Existing failure: `ContainerOffline.Tests.ps1` calls absent `Wait-AutopilotProcessUntil` on baseline
  `ff6805be`. Leave it unchanged; do not claim the wider container fixture clean.

## 3.1-3.2: Opt-in app readiness with existing canonical admission

- Choice: add `-AllowIndependentAi` to the existing phase-state helper. Select only ready AI
  siblings inside the first unfinished phase, then run the unchanged phase/dependency/criteria guards.
  Exhaustion returns `operator-action`; retained callers without the switch keep existing semantics.
- Consequence: app local/isolated policy can progress around human blockers without a new scheduler,
  later-phase exemption or automatic human completion. App epics use existing dependency facts plus
  per-child local finalization/archive proof; VS Code keeps its wrapper/provider proof.
- Evidence: four named readiness/epic/decision markers pass. The broader unchanged ArchiveEpic
  symlink fixture fails on this host with "A required privilege is not held by the client."
  No skip or clean claim replaces that missing host capability.

## 4.1-4.2: Keep completion proof stateless and defer app usage import

- Choice: strengthen the existing result checker with plan/source identity and ordered source,
  learning and archive commits. Current review and focused evidence remain caller-owned.
- Rationale: existence of an old recent-learning file cannot prove this finalization. App launchers
  must not write usage against the transport checkout's pre-worker active plan before fetching an
  archived result; retain sidecars outside Git until checkout, then use the existing exact normalizer.
- Consequence: no new completion journal, usage schema or competing orchestrator. App container
  visits retain unique named workspaces; Sandbox preserves commits and confined local dirty-work
  recovery without auto-staging/publication. Existing non-app normalization and consumers remain.

## 5.1-5.2: Narrow heavy regressions without weakening the runtime deadline

- Choice: retain the existing 60-second process-tree deadline and validate selected surfaces in
  bounded groups. The focused consumer fixture snapshots current canonical payloads, then installs
  CI with its five-plugin dependency closure rather than provisioning every unrelated plugin.
- Rationale: concurrent broad setup exceeded the deadline; an accidentally nested focused fixture
  also invoked the broad parent setup. Corrected its scope. The isolated distribution gate, focused
  install, source/readiness/transport fixtures, completion guards and factory handoff/admission/bounds
  now pass. Slow warnings remain evidence; the timed-out broad attempts are not clean suite results.
- Consequence: distribution and active guide links agree; no new installer abstraction, timeout
  increase or broad/premium workaround. Existing Waza, absent container wait helper and symlink-host
  limitations recorded above remain unresolved, not silently skipped.
- Handoff: `docs/operator-guide/app-ci-acceptance.md` defines the confirmed disposable two-phase
  fixture, human blocker/resume, exact settings/heads, transport/usage/recovery and completion/PR
  boundaries for native app, Docker, Windows Sandbox and named-version VS Code preservation.
  Steps 6.1-6.3 and 7.1 remain pending human evidence. No whole-plan finalization or PR yet.

## 3.1/6.1: Repair completed-prerequisite context exposed by native acceptance

- Operator choice: "Repair readiness and resume smoke (Recommended)".
- Evidence: disposable fixture 4c8316 accepted independent work and separately committed human
  approval, but canonical app admission falsely reported completed 1.1/1.2 as unmet prerequisites.
  Four regressions reproduced the same-phase and earlier-phase failure in canonical and installed
  helpers before repair.
- Choice: pass all completed steps alongside ready AI candidates to the existing `Get-NextStep`.
  Completed steps supply dependency facts, never new execution candidates. Keep canonical admission,
  first-unfinished-phase ordering and no-ready-work exhaustion unchanged; no fallback or new scheduler.
- Validation: 10 focused dependency/human-exhaustion/worker-boundary tests pass, including source and
  installed same-phase/earlier-phase cases and calls without the opt-in switch. Detect-only bundle,
  registry, marketplace and dogfood convergence passes. Current direct scope review found no findings;
  this does not replace the pending whole-plan terminal review or live acceptance.
- Consequence: commit the repair in the implementation branch and apply only that repair to the
  disposable smoke branch. Retain the pre-repair held worker without release; resume from the
  explicitly repaired HEAD in a fresh settings-verified worker. Fixture criteria and prior accepted
  evidence remain intact. Native acceptance 6.1 is still pending; no publication, smoke-to-parent
  integration or cleanup is authorized.
