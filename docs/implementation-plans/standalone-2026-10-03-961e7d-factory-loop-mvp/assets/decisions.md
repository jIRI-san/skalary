# Decisions

- User-selected scope: loopback-first with guided project-owned live scripts, not built-in
  ADO/GitHub adapters. Describe live support as a contract/onboarding seam, not a verified integration.
- User-selected distribution: repository and global Copilot CLI entry points. Existing dependency
  paths may be satisfied by explicit local bootstrap; installation confinement stays unchanged.
- User-selected repairs: pre-authorized within the confirmed feature, maximum two repair PRs per
  incident; human PR merge and artifact-specific production approval remain required.
- User-confirmed defaults: 60-second zero-AI polling, one chain/repair per project, configurable
  five-minute demo observation window, restart reconciliation and visible missing-access stops.
- Initial plan confirmation remains required. A narrow factory repair mode on the existing launcher
  validates original Test-PlanCriteriaBaseline, skips completed-phase admission, and forbids criteria/
  marker writes. Widening scope returns to /cip; ordinary admission remains unchanged.
- Bound build-fix invocations to two per stable incident lineage across successor PRs and heads.
- Mutation keys exist durably before dispatch; staged restart proofs require the same reconciled identity.
- Demo merge is a real Git merge; source SHA, merge commit and artifact digest remain distinct.
- Unanswered production approval waits with zero AI; decline blocks promotion.
- Evidence lives on a separate branch not merged into main; use source references rather than routinely
  merging main. Consumer setup owns deployment-trigger exclusion and publication readiness.
- Production promotes the same artifact validated in test. Production checks default read-only; no
  manual success override or automatic rollback in v1.
- One plugin and local scripts/state; no service, database, custom scheduling platform or agent swarm.
  Scheduler setup is explicit, opt-in and personal; no hosted workflow is added to Skalary.
- Both replay and agent-driven demo modes exercise the same contracts. Replay uses deterministic
  implementation; agent mode changes actual demo code. Infrastructure remains explicitly simulated.
- Operator-selected allowance gates further calls using chain usage imported idempotently from every
  planning/implementation/repair execution; missing usage blocks. It cannot guarantee a hard
  mid-invocation cap. Do not add a provider billing API.
- No new third-party packages are expected; prefer existing PowerShell, Git, Pester and Waza routes.
  Premium eval execution is explicit and optional, never a configured deterministic gate.
