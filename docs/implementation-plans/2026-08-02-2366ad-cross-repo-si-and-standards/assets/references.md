# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` goal and decomposition notes: consumer correctness and durable SI state are hard dependencies before cross-repo proposals can be trusted.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38` (2026-08-01 to 2026-08-02): the operator identified that consumer `/si` improvements belong upstream and considered a locally materialized upstream checkout plus container boundary.
- `docs/design-notes/explorations/si-cross-repo-proposal-protocol.design.md`: typed harvest/propose split, instruction-boundary rationale, evidence asymmetry, and rejected free-form autopilot mode.
- Dependencies: `1936cb` supplies durable SI state; `34088e` supplies correct consumer-installed behavior.
- Dependency `79cfe1` supplies the authoritative concern registry/template/generator; this plan extends that graph with standards rather than rewriting generated agents independently.

## Prior-art reconciliation

- **Extends `1936cb REQ-1`, `REQ-2`, `REQ-6`, `REQ-7`, `REQ-8`, and `DEC-16`.** That plan owns bounded immutable SI runs, resolver receipts, 0-5 candidates, archive/repair, fixed branches, trusted exact-head sync, and operator completion while deliberately deferring cross-repo transport. This plan adds only a digest-bound projection, verified upstream identity, disposable checkout/import, and foreign-source transitions to that authority.
- **Extends `79cfe1 REQ-1` through `REQ-8`.** Its concern registry, schema, template, generator, manifest/version lock, dogfood authority, gate placement, and design-note ownership remain controlling. This plan adds typed standards fields and generated runtime inventory to that same graph; it does not introduce a second agent authoring path.
- **Supersedes `b0c0d3 DEC-10` and `DEC-17` only for consumer flow.** Same-repo `/si` retains the draft-PR behavior. The manual-only consumer handoff is replaced by a validated local upstream checkout with a durable manual-handoff fallback.
- **Reuses `b0c0d3 RISK-9`.** Installed consumer payloads are distribution copies, never the upstream proposal target.
- **Reuses `002 REQ-15` as a distribution constraint.** Dogfood copies remain generated install surfaces and are not treated as source during cross-repo proposal.
- **Conditionally reuses `004 REQ-4`, `RISK-10`, `DEC-7`, and `DEC-8`.** Explicit target and no-force rules apply if a later upstream proposal pushes. Harvest itself never pushes, so these records do not authorize credentials or network writes in phase 1.
- **Analogous, not controlling:** `21f21d` and `cda9da` keep architecture promotion human-owned. This plan adopts human approval for generic review-standard promotion but defines its own corroboration evidence contract.
- **Extends `ARCH-Review-Run-V1`.** Resolved standards digests, applied override ids, and typed violated rule ids become part of frozen and manifest-bound review authority; mutable paths and free-text citations are insufficient.

## Index status

- Consulted `Get-PlanIndex.ps1` on 2026-08-21 with cross-repo, self-improvement, standards, proposal, and upstream topic filters.
- The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. Archived `cda9da` records were still indexed; global index completeness is therefore not claimed.
