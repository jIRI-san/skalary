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
