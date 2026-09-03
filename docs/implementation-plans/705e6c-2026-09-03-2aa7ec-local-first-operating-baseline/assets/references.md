# References

Preliminary context captured by /cep; /cip must confirm and refine it.

## Epic

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Child `2aa7ec` owns the dependency-free local operating baseline.

## Accepted prior-art provenance

| Source | Disposition | Use here |
|---|---|---|
| `25aa23` | Partial reuse | Keep proportionality; reject its review machinery. |
| `31a3ef` | Reject | Mandatory hosted CI and complete-tier coverage conflict with operator intent. |
| `768d7b` | Partial reuse | Keep focused fail-loud selection; remove tiers, profiles, and workflow enforcement. |
| `a5ad22` | Reuse evidence | Use the 76-minute suite profile and 14-hour orchestration record to prioritize deletion. |
| `c21cdc` | Reject | Schema/receipt authority is intentionally removed by another child. |

## Relevant repository guidance

- `docs/design-notes/.design-notes.md`
- `docs/architecture-notes/.architecture-notes.md`
- `docs/design-notes/project/ci-gates.design.md`
- `docs/design-notes/project/dev-rules.design.md`
- `docs/design-notes/project/copilot-customizations.design.md`
- `docs/implementation-plans/archived/2026-08-14-a5ad22-epic-autopilot-orchestration/assets/test-suite-profile-evidence.md`
- `docs/implementation-plans/archived/2026-08-14-a5ad22-epic-autopilot-orchestration/assets/subsession-execution-statistics.md`

## Epic discussion provenance

On 2026-09-03 the operator identified runtime, review, and state complexity as a direct productivity
problem. They required local-only execution, explicit-only full-suite runs, ruthless value-based test
pruning, human-readable internal formats, direct pre-approvable scripts, equivalent VS Code/CLI
choices, strategic agent use, and simplicity over speculative safety. After three coherency rounds,
the operator read and accepted the four-child plan and explicitly rejected review findings that would
restore receipts, journals, hosted automation, policy authorities, or similar complexity.
