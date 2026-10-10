# Domain

## Terms and meanings

- Coordinator: the app or supported modern VS Code Copilot session running `/ci`, sharing admission, environment selection, worker dispatch, local integration, resume and delivery policy.
- Phase worker: a fresh full native local session/worktree using the current client's verified capabilities, or fresh CLI invocation in selected Docker/Windows Sandbox, executing one phase's admitted work. A later visit uses fresh context.
- Client/harness: app and modern VS Code Copilot share SDK-based harness behavior, not necessarily tool inventories. VS Code's legacy Local extension-host target is outside new local orchestration support.
- Execution environment: local host, Docker container, or Windows Sandbox. App process sandboxing and cloud sandboxes are distinct, not replacements for the retained environments.
- Isolated result transport: existing controlled Git/artifact transfer that makes exact worker commits available locally for acceptance; transcripts/sentinels alone are not completion proof.
- Integration branch: the coordinator's delivery branch. It is unchanged while a worker runs and fast-forwards only to verified worker commits.
- Dependency-ready work: unfinished AI siblings within the first unfinished phase whose explicit prerequisites pass, or independently admitted epic siblings. Every earlier phase must close before a later phase is admitted; missing annotations do not waive that gate.
- Phase close: every phase step is completed and the canonical checklist close is committed and clean; a worker turn ending is not close proof.
- Finalization target: one fresh worker per standalone or epic-child plan, owning terminal evidence/review, conditional compaction, learning publication, and plan archival after that plan's required phases close.
- Epic completion: the coordinator's distinct Goal/Definition-of-done/coherency check and epic-index archival after every child finalization commit is integrated and all children are archived.
- Independent review: a separate read-only context, not a promise of another model family.
- Decision log: mutable execution history at `assets/unattended-decissions.md`; it cannot alter the confirmed intent, requirements, risks, or decisions baseline.

## Actors and boundaries

- Operator confirms intent and performs human-gated actions.
- Coordinator and workers receive bounded authority from the confirmed plan; no unattended decision expands it.
- App native tools materialize and observe local sessions; existing launchers materialize/observe isolated CLI workers. Ordinary Git and existing deterministic scripts establish source and progress facts in every environment.
- Plugin owners generate installed content; instructions never use generated artifacts as authoring authority.

## Interfaces and ownership

- `tools/model-allowlist.psd1` owns model aliases, role effort, host formats, and replacement policy.
- `Sync-ModelBindings.ps1` owns generated aliases and Waza model bindings.
- Continue-implementation owns shared coordinator policy and small client-specific app/VS Code routes. Autopilot remains shared executor/isolated-runtime owner; its dependency/closure remains installed.
- Existing plan/epic helpers own identity, immutable baseline, dependencies, and archival. Replace competing standalone local host/epic orchestration, retaining bounded container/Sandbox target launchers.
- Native `create_session` kickoff explicitly binds model, effort, context, phase scope, source branch, and expected HEAD.
- That tool name is app-specific. VS Code's full-session equivalent must be discovered/verified; shared SDK, UI creation or a same-context subagent cannot establish automatic isolated phase-session support.
- Isolated CLI flags explicitly bind the same Sol high/default setting and exact target/start commit. Their outputs and exit 0/42/43/failure contracts remain distinct; usage sidecars retain exact isolated accounting.
- Live native session or owned isolated process/container state is necessary for observation; committed locally accepted source/checklist state determines progress. Session history, transcripts, sentinels and advisory reports are not success evidence.

## Invariants

- Criteria checks precede mutation and repeat in the worker.
- One phase writer is active at a time.
- Starting commit and integration ancestry are verified; unexpected state stops rather than silently repairing it.
- A partial or blocked phase is not closed.
- Existing three-call limits apply to bounded review/escalation, not routine phase dispatch.
- Explicit operator/destructive-action/push gates remain; retained child work is not silently discarded.
- Historical content is not rewritten to match the new execution policy.
