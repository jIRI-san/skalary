# Domain

## Terms and meanings

- Coordinator: the app `/ci` session owning new admission/dispatch/integration/resume/delivery. VS Code retains its existing execution route; new native coordination there is deferred.
- Phase worker: a fresh native app session/worktree or fresh CLI invocation in selected Docker/Windows Sandbox, executing one app-admitted phase visit. Retained VS Code execution is not relabeled as a new native worker.
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
- Continue-implementation owns app coordinator policy and explicit app/preserved-VS-Code instruction routes. Autopilot remains shared executor/runtime owner; its dependency/closure remains installed.
- Existing helpers own identity/baseline/dependencies/archival. App dispatch avoids competing host/epic loops; shared launchers remain while VS Code/factory consumers need them.
- Native `create_session` kickoff explicitly binds model, effort, context, phase scope, source branch, and expected HEAD.
- App and VS Code use different `create_session` schemas. VS Code 1.141 exposes native orchestration but has no explicit per-call effort/context/base controls; keep its current execution until a future confirmed replacement proves them or an approved equivalent.
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
