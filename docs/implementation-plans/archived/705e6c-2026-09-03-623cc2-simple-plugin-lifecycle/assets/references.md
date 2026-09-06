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
| `2aa7ec` decisions | Dependency; loaded through the bounded artifact adapter | Reuse deletion-first design, direct scripts, focused 30/60-second validation, external/internal JSON classification, and no compatibility machinery. |
| `33a78a` decisions | Dependency; loaded through the bounded artifact adapter | Use direct work, deterministic evidence, container autopilot's cheap-first routing, and one risk-selected final review. |
| `34088e` decisions | Reuse; loaded through the bounded artifact adapter | Reuse the production installer, manifest-derived foreign fixture, physical confinement, and existing distribution writers. |
| `a5ad22` index record | Reuse evidence | Treat long orchestration and lifecycle test costs as deletion targets. |
| `c21cdc` index record | Reject mechanism | Do not restore content-addressed authority, schema-led internal state, or receipt handshakes. |
| `768d7b` index record | Partial reuse | Keep fail-loud focused validation and named confinement tests; reject suite tiers and hosted enforcement. |

## Relevant repository guidance

- `docs/design-notes/architecture/plugin-registry.design.md`
- `docs/design-notes/architecture/plugin-manager.design.md`
- `docs/design-notes/project/simplicity-first.design.md`
- `docs/design-notes/project/ci-gates.design.md`
- `docs/architecture-notes/arch-install-confinement.md`
- `scripts/skalary/{Install-Plugin,Update-Plugin,Remove-Plugin,Get-Plugin,Find-Plugin,_Common}.ps1`
- `scripts/skalary/{Build-Registry,Test-Registry,Sync-PluginScripts,Build-Marketplace,Sync-Dogfood}.ps1`
- `tests/skalary/{PluginRetirement,ConsumerInstall,Marketplace,PluginScriptBundle}.Tests.ps1`
- `schemas/plugin/plugin.schema.json`
- `schemas/registry/registry.schema.json`
- `schemas/marketplace/marketplace.schema.json`

## Epic discussion provenance

On 2026-09-03 the operator described harvest and lifecycle infrastructure as overengineered for a
personal skill repository and asked for ruthless removal of machinery that does not improve their
productivity. They accepted retaining prompt-injection and concrete path-safety guards while treating
security as secondary to usability in this trusted environment. They later approved this child and
rejected final-review demands to restore journals, receipts, rollback systems, and platform authority.

On 2026-09-06 the operator refined the receipt decision: retain only per-plugin installed identity,
version, source identity, and immutable ref so updates can be detected without a shared lockfile. They
selected pre-mutation removal refusal with explicit `-Force`, receipt-owned overwrite for explicit
updates, and registry refusal plus explicit removal for retirement.
