# References

Preliminary context captured by /cep; /cip must confirm and refine it.

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
| `2366ad` | Partial reuse | Keep untrusted-input treatment; reject durable transport and state expansion. |
| `25aa23` | Partial reuse | Keep proportional decisions; reject fixed review machinery. |
| `a5ad22` | Reuse evidence | Treat long harvest/orchestration paths as deletion targets. |
| `c21cdc` | Reject | Do not retain schema, receipt, or content-addressed authority. |

## Relevant repository guidance

- `docs/design-notes/architecture/self-improvement.design.md`
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/project/copilot-customizations.design.md`
- `plugins/self-improvement/`
- `.github/skills/si/`
- `.github/skills/pfb/`

## Epic discussion provenance

On 2026-09-03 the operator described `/si` and harvest as an overcomplicated atomic-store system for
a straightforward personal workflow. They required ruthless deletion while preserving prompt-
injection guards, individual informed choices, direct pre-approvable scripts, and equivalent VS
Code/Copilot CLI behavior. They approved this bounded recent-lessons child and rejected review
requests for new proposal identity, replay, receipt, rollback, and service semantics.
