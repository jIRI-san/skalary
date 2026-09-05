# References

Preliminary context captured by /cep; /cip must confirm and refine it.

## Epic and dependency

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `2aa7ec` for focused commands, external/internal JSON classification, direct-script rules,
  and assigned lifecycle cleanup rows.
- Depends on `33a78a` for the final premium-eval model and grader policy before this child prunes
  plugin-lifecycle tests.
- Transferred rows are enumerated in
  `docs/implementation-plans/705e6c-2026-09-03-2aa7ec-local-first-operating-baseline/assets/ownership.md`;
  `623cc2` owns every row carrying that owner id.

## Accepted prior-art provenance

| Source | Disposition | Use here |
|---|---|---|
| `a5ad22` | Reuse evidence | Treat long orchestration and lifecycle test costs as deletion targets. |
| `34088e` | Reassess | Keep only externally required correctness and direct confinement behavior. |
| `c21cdc` | Reject mechanism | Do not use receipts, content addressing, or schema authority internally. |
| `768d7b` | Partial reuse | Keep focused fail-loud validation; reject suite tiers and hosted enforcement. |

## Relevant repository guidance

- `docs/design-notes/architecture/plugin-registry.design.md`
- `docs/design-notes/architecture/plugin-manager.design.md`
- `docs/architecture-notes/arch-install-confinement.md`
- `schemas/plugin/plugin.schema.json`
- `schemas/registry/registry.schema.json`
- `schemas/marketplace/marketplace.schema.json`

## Epic discussion provenance

On 2026-09-03 the operator described harvest and lifecycle infrastructure as overengineered for a
personal skill repository and asked for ruthless removal of machinery that does not improve their
productivity. They accepted retaining prompt-injection and concrete path-safety guards while treating
security as secondary to usability in this trusted environment. They later approved this child and
rejected final-review demands to restore journals, receipts, rollback systems, and platform authority.
