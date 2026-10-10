# Domain

## Terms and meanings

- Coordinator: the app session running `/ci`, owning admission, native child dispatch, local integration, resume, and final delivery.
- Phase worker: a fresh isolated app child executing only admitted work for one named phase. A later admitted visit after a human blocker uses a new child.
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
- App native tools materialize and observe sessions; ordinary Git and existing deterministic scripts establish source and progress facts.
- Plugin owners generate installed content; instructions never use generated artifacts as authoring authority.

## Interfaces and ownership

- `tools/model-allowlist.psd1` owns model aliases, role effort, host formats, and replacement policy.
- `Sync-ModelBindings.ps1` owns generated aliases and Waza model bindings.
- Continue-implementation owns the consolidated CI instructions, executor payload, and bundled helper closure.
- Existing plan/epic helpers own identity, immutable baseline, dependencies, and archival. Retain provider-neutral functions; remove the host-launch loop.
- Native `create_session` kickoff explicitly binds model, effort, context, phase scope, source branch, and expected HEAD.
- Live session state is necessary for observation; committed source/checklist state determines progress. Session history and advisory reports are not success evidence.

## Invariants

- Criteria checks precede mutation and repeat in the worker.
- One phase writer is active at a time.
- Starting commit and integration ancestry are verified; unexpected state stops rather than silently repairing it.
- A partial or blocked phase is not closed.
- Existing three-call limits apply to bounded review/escalation, not routine phase dispatch.
- Explicit operator/destructive-action/push gates remain; retained child work is not silently discarded.
- Historical content is not rewritten to match the new execution policy.
