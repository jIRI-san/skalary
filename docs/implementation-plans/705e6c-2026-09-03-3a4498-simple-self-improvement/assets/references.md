# References

## Epic and dependency

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `367e9a`, which owns and delivers the bounded fenced recent-learning artifact.
- Depends on `33a78a` for the final AI-credit budget, default-context rule, and model escalation
  policy used by the simplified SI flow.
- Also consumes the informed-choice, direct-script, focused-test, and cost-budget conventions from
  transitive dependency `2aa7ec`.
- Transferred rows are enumerated in
  `docs/implementation-plans/705e6c-2026-09-03-2aa7ec-local-first-operating-baseline/assets/ownership.md`;
  `3a4498` owns every row carrying that owner id.

## Accepted prior-art provenance

| Source | Disposition | Use here |
|---|---|---|
| `2366ad` | Partial reuse | Keep untrusted-input treatment and upstream re-judgment; delete its durable cross-repository transport, state, publication, and receipt machinery. |
| `25aa23` | Partial reuse | Keep proportional decisions; reject fixed review machinery. |
| `a5ad22` | Reuse evidence | Treat long harvest/orchestration paths as deletion targets. |
| `c21cdc` | Reject | Do not retain schema, receipt, or content-addressed authority. |
| `367e9a` | Dependency | Keep the single 16 KiB/10-item cited recent-learning handoff, current Git evidence, and visible interruption behavior. |
| `33a78a` | Dependency | Keep direct work, default context, the cheap-first model ladder, and the three-call ceiling. |

## Relevant repository guidance

- `docs/design-notes/architecture/self-improvement.design.md`
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/project/copilot-customizations.design.md`
- `plugins/self-improvement/`
- `.github/skills/si/`
- `.github/skills/pfb/`
- `tests/skalary/RecentLearning.Tests.ps1`
- `tests/skalary/SiWriteScope.Tests.ps1`
- `tests/skalary/FeedbackQueue.Tests.ps1`
- `plugins/autopilot/agents/autopilot.agent.md`
- `plugins/continue-implementation/skills/ci/SKILL.md`

## Epic discussion provenance

On 2026-09-03 the operator described `/si` and harvest as an overcomplicated atomic-store system for
a straightforward personal workflow. They required ruthless deletion while preserving prompt-
injection guards, individual informed choices, direct pre-approvable scripts, and equivalent VS
Code/Copilot CLI behavior. They approved this bounded recent-lessons child and rejected review
requests for new proposal identity, replay, receipt, rollback, and service semantics.

## Confirmed 2026-09-05 refinements

- Keep `/pfb` as a stateless interactive comparison; remove its queue and headless persistence.
- Limit direct `/si` targets to canonical Markdown customization sources. Generated distribution changes
  remain owned by existing trusted generators.
- Apply selected changes in the current worktree. Do not retain branch, worktree, PR, or cross-repository
  proposal lifecycle.
