# Intent

## Goal

Ship one installable factory-loop plugin that lets a single operator try a restartable,
issue-driven software-delivery loop before selecting a real customer integration.

## Desired outcome

Install into another repository or globally into Copilot CLI, run guided setup, and point the
loop at an idea or a prepared plan. Confirm the plan, implement, open a PR, repair failing
checks, wait for human merge, observe test deployment/version, validate feature behavior and
telemetry, ask approval to promote the tested artifact, validate production, publish evidence,
and close the originating item. Confirmed failures create deduplicated bugs and bounded repair
cycles. Loopback providers make this usable without ADO/GitHub credentials.

## Success signals

- A foreign consumer completes zero-AI replay with real local acceptance and Git evidence.
- An opt-in agent-driven demo changes real application code; its original defect is reproduced
  and repaired without weakening acceptance.
- Restart at each external mutation boundary reconciles rather than duplicates the operation.
- A denied promotion, stale version or inaccessible telemetry cannot produce successful closure.
- Polling uses no AI requests; known agent usage and an operator-selected allowance govern
  admission of further calls.

## Non-goals

- Ready-made live ADO/GitHub issue, PR, pipeline or telemetry adapters in this release.
  Guided project-owned adapter authoring is included; live provider verification needs a pilot.
- Shared/multi-tenant service, distributed queue, database, webhook platform, agent swarm,
  automatic merge/rollback, or cross-repository orchestration.
- Continuous monitoring after terminal completion, manual success overrides for inaccessible
  production, automatic initial plan confirmation, or mid-session hard credit enforcement.
- Deployment infrastructure inside Skalary, new repository-owned hosted workflows, generalized
  changes to every plugin for global paths, or a digital-twin platform.

## Definition of done

- All REQ-1 through REQ-22 are covered by focused deterministic evidence and final review.
- Plugin source, manifest, bundled closure, registry, marketplace and dogfood converge.
- Both install layouts work with explicit project selection; dependency bootstrap is documented.
- Demo controls expose human plan confirmation, PR merge and production approval.
- Operator documentation provides local scheduled polling, restart, limits, demo cleanup and
  adapter setup; no live credentials or production data are committed.
- Agent evals are shipped and structurally validated; executing premium evals is optional,
  reported separately and never substituted for deterministic acceptance.
