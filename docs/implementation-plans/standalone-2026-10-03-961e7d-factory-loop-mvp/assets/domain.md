# Domain Model

## Terms and meanings

- Chain: one originating work item and its plan, implementation PR, deployments, incidents and evidence.
- Adapter: project-owned command accepting bound inputs and returning a validated small result.
- Environment profile: test, optional pre-prod, or prod configuration sharing the same contracts.
- Artifact: immutable runnable demo snapshot digest or live release identity. Keep PR source SHA,
  actual merge commit and artifact identity distinct; prod reuses the test artifact.
- Incident: confirmed in-scope failure with stable fingerprint, linked bug, original reproducer
  and at most two repair PRs. Deployment occurrences attach to the incident.
- Evidence: sanitized committed facts about an artifact/environment/time window; not permanent health.
- Tick: finite deterministic reconciliation; optionally admits one bounded agent action.
- Build incident: stable failing-check lineage across changed heads and replacement PRs;
  corrective-call counters do not reset when a new PR opens.

## Actors and boundaries

- Operator confirms initial criteria, grants bounded repair authority, merges PRs, approves
  production per artifact, and supplies authentication outside repository configuration.
- Plugin owns orchestration, small contracts, guided setup and simulated provider commands.
- Consumer owns acceptance, environment mappings, adapter scripts and trigger exclusions.
- Personal machine owns authentication, scheduler and uncommitted checkpoints/locks.
- Pipeline owns build/deployment and any native approvals. The loop observes it, not replaces it.

## Interfaces and ownership

Commands cover work-item read/find/create/update, PR open/read/check status, deployment
read/trigger, running-version read, acceptance execution and telemetry read. Mutation commands
accept an operation key and support lookup/reconciliation. Results carry provider identity,
status, provenance and actionable errors; logs are untrusted data.

Repository installation uses the ordinary confined lifecycle. Global factory tools resolve
assets relative to themselves; explicit setup may install existing planning/execution dependencies
locally when their `.github` paths require that layout. Both paths bind one canonical consumer root.

## Invariants

- Initial plan confirmation and immutable criteria remain existing workflow authority; factory
  repair mode validates original criteria without ordinary completed-phase admission or new markers.
- Production triggering requires affirmative approval for the tested artifact; repair changes invalidate it.
- No live fallback in loopback; simulated provider evidence is labeled.
- Missing access, unknown mutation outcome and missing evidence are not success.
- One active chain per project, no automatic PR merge and no weakening tests to resolve a failure.
- Evidence branch is not merged into main and is excluded from consumer deployment triggers.
