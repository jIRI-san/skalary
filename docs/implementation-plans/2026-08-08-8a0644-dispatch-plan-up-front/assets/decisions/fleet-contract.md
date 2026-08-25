# Fleet dispatch contract

## Scope

Fleet dispatch is a pure planner plus a thin adapter inside one workflow invocation. It does not coordinate separate processes or survive a restart. Existing workflow logs and review-run artifacts remain responsible for durable history.

The contract proves what the orchestrator asked to run and what it observed. It does not claim to measure or control provider-global concurrency.

## Task and plan shape

Each caller supplies ordered task descriptors with:

- stable task id;
- display label and role/model key already owned by the caller;
- selected state or an explicit omission reason;
- zero or more dependency task ids.

The planner rejects duplicate ids, unknown dependencies, cycles, and selected tasks that depend on omitted tasks without an omission reason. It preserves caller order and returns:

- selected and omitted tasks;
- a cap of four admitted tasks;
- deterministic ready waves;
- the retry policy;
- an initially empty attendance record.

The planner has no filesystem store, lock, ledger, schema registry, host identity, or background process.

## Dispatch behavior

1. Render the complete plan before the first agent call.
2. Launch only selected tasks from the returned ready wave, with at most four admitted in that wave.
3. Record started and terminal outcomes in the run-local attendance record.
4. On success, admit newly ready tasks in stable caller order.
5. On failure, cancel transitive dependents and continue unrelated ready tasks.
6. Retry once only when the host/tool result explicitly identifies throttling. Show both attempts.
7. Render final attendance and any degradation after all planned tasks are terminal.

The four-task cap is an orchestrator admission rule. Output must say provider concurrency is unobserved; the plan must not infer it from timing or error prose.

## Caller adapters

- `/cip` plans Designer and Requirements Validator together, then Judge after their successful completion.
- `/ci` and autopilot plan Designer and Validator, then Implementor, then Judge according to their existing workflow boundaries. Existing worktree/container and promotion behavior is unchanged.
- `/cr` and `/dr` convert the already-frozen review-run task list into the shared plan. Review-run keeps ownership of persistence, publication, and final review views.
- The local CEP conformance fixture proves that a later epic-review caller can use the same shape. Plan `25aa23` owns its actual integration.

## Explicit non-goals

This plan adds none of the following:

- signing keys, authentication tokens, process nonces, or host attestation;
- credential isolation, secret scanning, or a new prompt-injection framework;
- a persistent fleet store, global budget ledger, recovery journal, or cleanup protocol;
- clone management, quarantine, disk escrow, or large-tree performance infrastructure;
- activation transactions, dormant/active modes, or a dedicated CI workflow;
- a new architecture contract above the existing design-note level.

Normal repository and platform security behavior still applies. This feature does not weaken existing review-run validation, CI/autopilot isolation, plugin confinement, or model allowlist handling; it does not duplicate them.

## Evidence ownership

| Evidence | Test id | Focus |
|---|---|---|
| planner | `FleetDispatch.Planning` | validation, omissions, stable waves, four/five boundary |
| pre/post rendering | `FleetDispatch.Rendering` | complete declaration and attendance |
| execution | `FleetDispatch.Execution` | planned-only dispatch, dependency failure, one throttle retry |
| CIP adapter | `FleetDispatch.CipContract` | role order and installed skill contract |
| CI/autopilot adapter | `FleetDispatch.CiContract` | role order and unchanged execution boundaries |
| CR/DR adapters | `FleetDispatch.ReviewAdapters` | frozen task conservation and unchanged publication |
| CEP conformance | `FleetDispatch.CepConformance` | generic shape and no cross-plan mutation |
| distribution | `FleetDispatch.ConsumerInstall` | source/bundle/catalog/eval parity |

## Documentation and distribution

The implementation updates the fleet design note and the existing customization, plan-workflow, review, and autopilot notes where behavior changes. Plugin payload changes use the repository's existing script sync, version bump, registry, marketplace, installed-consumer, and eval paths. No separate activation phase exists.