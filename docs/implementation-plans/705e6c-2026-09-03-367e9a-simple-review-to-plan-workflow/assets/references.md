# References

Preliminary context captured by /cep; /cip must confirm and refine it.

## Epic and dependency

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `2aa7ec` for focused commands, format ownership, informed choices, bounded history, and
  accepted cost budgets.
- Produces the bounded learning artifact consumed by `3a4498`.

## Accepted prior-art provenance

| Source | Disposition | Use here |
|---|---|---|
| `25aa23` | Partial reuse | Keep proportionality and explicit operator decisions; remove fixed review machinery. |
| `31a3ef` | Reject | Remove CI coupling and suite-tier enforcement. |
| `c21cdc` | Reject mechanism | Remove review-run JSON, schemas, manifests, canonicalization, and receipts while retaining data fencing and secret handling where needed. |
| `2366ad` | Partial reuse | Keep bounded untrusted learning input; reject durable transport and lifecycle state. |

## Relevant repository guidance

- `docs/design-notes/architecture/review-reporting.design.md`
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/architecture/autopilot-execution.design.md`
- `docs/design-notes/architecture/autopilot-skill.design.md`
- `docs/design-notes/architecture/fleet-dispatch.design.md`
- `docs/design-notes/architecture/review-concern-authoring.design.md`
- `docs/architecture-notes/arch-review-run-v1.md`

## Epic discussion provenance

On 2026-09-03 the operator said repeated DR/CR rounds turn simple designs into architectural
astronautics, consume too many agents and context reloads, and ask questions without enough context.
They required simplicity to constrain review, informed choices to include effort and complexity,
criteria preservation without signed receipts, bounded prior-plan lookup, and equivalent VS Code/CLI
operation. They later read and accepted the four-child plan and directed that review demands which
restore platform complexity be removed rather than propagated.
