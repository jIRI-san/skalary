# Decisions

- **Use one small run-scoped dispatcher.** `/cip`, `/ci`, `/cr`, `/dr`, and later `/cep` coherency review share planning, ready waves, attendance, and explicit throttle handling without a daemon or persistent scheduler.
- **Cap each workflow run at four admitted tasks.** The cap limits orchestrator dispatch, not provider-global concurrency; larger fleets run in declared waves.
- **Declare the run before dispatch.** The plan lists selected roles or concern/model pairs, total invocations, omissions, cap, wave order, and retry policy before calls begin.
- **Never hide omissions.** Work dropped by scope is named with a reason; throttling cannot silently convert a full run into partial attendance.
- **Preserve independent passes.** Reading batches do not multiply concern passes, and selected concern/model pairs still run independently once.
- **Bound retries, then report degradation.** Retry once only for an explicit host/tool throttle result; replacement calls and unlimited retries are rejected.
- **Reuse review-run v1.** CR/DR keep existing Freeze, persistence, publication, and rendering; the dispatcher only plans frozen tasks and reports attendance.
- **Keep state local to the invocation.** A resumed workflow creates a new dispatch plan; no cross-run lease, budget ledger, append store, or repair protocol is added.
- **Preserve existing execution boundaries.** CI/autopilot keep current worktree/container and promotion behavior; this plan does not create clone, credential, or activation infrastructure.
- **Use ordinary distribution.** Existing plugin generators, sync/version writers, registry, marketplace, installed-consumer checks, and evals distribute the change.
- **Reject durable fleet-platform expansion.** No transaction engine, content-addressed fleet store, global scheduler state, capability protocol, isolated-clone fleet, quarantine system, activation transaction, or new architecture contract belongs in this plan.

## Simplification decision

The accepted 2026-08-22 cut is the current plan body: a pure planner plus a run-scoped orchestration adapter. Later design review must preserve the strong non-goals above unless the operator confirms a new outcome that requires durable infrastructure.
