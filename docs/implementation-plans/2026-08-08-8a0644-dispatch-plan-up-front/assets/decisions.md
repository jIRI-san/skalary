# Decisions

<!-- Key decisions made during planning - one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Use one small run-scoped dispatcher.** `/cip`, `/ci`, `/cr`, `/dr`, and later `/cep` coherency review share planning, waves, attendance, and throttling semantics without a daemon or persistent scheduler.
- **Cap each workflow run at four admitted tasks.** The cap limits orchestrator dispatch, not provider-global concurrency; larger fleets run in declared waves.
- **Declare the run before dispatch.** The plan lists selected roles or concern/model pairs, total invocations, omissions, cap, wave order, and retry policy before calls begin.
- **Never hide omissions.** Work dropped by scope is named with a reason; throttling cannot silently convert a full run into partial attendance.
- **Preserve independent passes.** Reading batches do not multiply concern passes, and selected concern/model pairs still run independently once.
- **Bound retries, then report degradation.** Rejected: replacement calls or unlimited retries that obscure what ran.
- **Reuse the `c21cdc` review-run contract.** CR/DR keep existing Freeze, persistence, publication, and rendering; the dispatcher only groups frozen tasks into waves and reports attendance.
- **Keep state local to the invocation.** A resumed workflow creates a new dispatch plan; no cross-run lease or budget ledger is added.
- **Preserve existing execution boundaries.** CI/autopilot keep their current worktree/container and promotion behavior; this plan does not create a clone manager or credential broker.
- **Use the ordinary plugin distribution path.** Source changes flow through existing sync, version, registry, marketplace, installed-consumer, and eval checks; no activation transaction is added.
- **Reject infrastructure security accretion.** Signing keys, authenticated host telemetry, process nonces, secret-scanning protocols, content-addressed stores, quarantine systems, and adversarial prompt frameworks do not address the confirmed local-skill requirement and are out of scope.