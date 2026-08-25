# Decisions

- **Keep the control plane on the host.** Child containers implement one plan; they never select siblings or mutate epic-run state.
- **Reuse `Get-PlanState`.** Epic rollup and `NextChild` remain the graph/selection authority.
- **Reuse the per-plan launcher.** Container creation, child execution, terminal outputs, and existing stop codes stay owned by current launcher machinery.
- **Run one child at a time.** Sequential child execution is the complete v1; parallel children are deferred.
- **Keep one small state file.** Only `epic`, `target`, `currentChild`, `branch`, `run`, and `outcome` persist for resume.
- **Stop for operator merge.** The host verifies terminal output and remote head, then waits; it does not merge or push the target.
- **Refresh after every merge.** Target and dependency graph are recomputed before another child is selected.
- **Never skip failure.** Blocked, failed, or degraded outcomes remain visible and resumable.
- **Use simplified final review.** Invoke `25aa23` when available; otherwise crosscheck epic intent and definition of done directly.
- **Depend only on dispatch behavior.** `8a0644` is required for bounded orchestration. Folder naming, generated concerns, and coherency review are not core sequential-loop blockers.
- **Reject prior expansion.** No Git-bundle transport, provider/state contract family, large exit matrix, capability audit, generated delivery concerns, finalization state machine, or evidence-only finalization PR is included.

## Simplification decision

The accepted 2026-08-22 cut is a thin host loop around existing rollup and launch behavior. Durable state is limited to the six fields needed to resume one current child.
