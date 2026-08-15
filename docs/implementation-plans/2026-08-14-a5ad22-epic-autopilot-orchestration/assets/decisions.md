# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Extend `/ci <epic-id>`, not a new top-level skill.** `/ci` already resolves epics and consumes deterministic `NextChild`; a second skill would duplicate lifecycle semantics.
- **Keep orchestration on the host.** The host owns epic graph, durable state, target authority, runtime lifecycle, verification, merge handoff, and retries; a container owns one child only.
- **Sequential whole-child MVP.** One fresh container and child branch run at a time. Parallel children are deferred until non-overlapping scopes and shared fleet admission can be proven.
- **Merged target state gates dependencies.** An unmerged completed child branch never satisfies a dependent; the host refreshes and recomputes after operator-approved merge.
- **Pause on non-clean outcomes.** Failed, degraded, blocked, conflicting, or human-gated children stop the epic; rejected: silently skip to unrelated work.
- **Reuse existing child execution.** The current container launcher, exit 42/43 contracts, receipts, and package rebundle loop remain the per-plan engine.
