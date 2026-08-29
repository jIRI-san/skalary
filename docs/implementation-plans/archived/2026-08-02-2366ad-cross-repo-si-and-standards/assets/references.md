# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` goal and decomposition notes: durable SI activity and generated concern ownership are the only active prerequisites for this plan.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38` (2026-08-01 to 2026-08-02): the operator identified that consumer `/si` improvements belong upstream and considered a locally materialized upstream checkout plus container boundary.
- `docs/design-notes/explorations/si-cross-repo-proposal-protocol.design.md`: typed harvest/propose split, instruction-boundary rationale, evidence asymmetry, and rejected free-form autopilot mode.
- Dependency `1936cb` supplies durable local phase learning and SI due/result activity.
- Dependency `79cfe1` supplies the authoritative concern registry/template/generator; this plan extends that graph with standards rather than rewriting generated agents independently.
- [2026-08-22 simplification review](../../epics/2026-08-22-plan-simplification-review.md) — approved one-artifact upstream handoff and optional local standards through existing ownership; rejects cache, receipt, evidence-registry, and review-run v2 platforms.

## Prior-art reconciliation

- **Extends `1936cb`.** That plan owns durable local learning and SI activity. This plan exports a bounded candidate artifact without extending its storage model.
- **Extends `79cfe1`.** Its concern registry, template, generator, manifest/version sync, dogfood authority, and drift tests remain controlling. This plan adds generic standards fields and optional local resolution without another authoring path.
- **Supersedes `b0c0d3 DEC-10` and `DEC-17` only for consumer flow.** Same-repo `/si` retains the draft-PR behavior. The manual-only consumer handoff is replaced by a validated local upstream checkout with a durable manual-handoff fallback.
- **Reuses `b0c0d3 RISK-9`.** Installed consumer payloads are distribution copies, never the upstream proposal target.
- **Reuses `002 REQ-15` as a distribution constraint.** Dogfood copies remain generated install surfaces and are not treated as source during cross-repo proposal.
- **Conditionally reuses `004 REQ-4`, `RISK-10`, `DEC-7`, and `DEC-8`.** Explicit target and no-force rules apply if a later upstream proposal pushes. Harvest itself never pushes, so these records do not authorize credentials or network writes in phase 1.
- **Preserves `ARCH-Review-Run-V1`.** Resolved standards are inputs to existing CR/DR dispatch; frozen scope, manifest-last publication, verified delivery, and retained evidence authority do not change.

## Index status

- Consulted `Get-PlanIndex.ps1` on 2026-08-21 with cross-repo, self-improvement, standards, proposal, and upstream topic filters.
- The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. Archived `cda9da` records were still indexed; global index completeness is therefore not claimed.
