# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

`/cep` must run a focused epic coherency review in addition to its interview, seams gate, and operator cut
confirmation. This review is distinct from the detailed implementation-plan review each child receives.

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 4-5: the operator asked whether epics receive review and directed that `/cep` run a coherency review after learning only plans had formal `/dr` coverage.
- Epic `bcece1` Epic coherency review section records the accepted boundary and finding disposition flow.

## Intended review boundary

- Verify goal, desired outcome, success signals, non-goals, and definition of done are collectively covered.
- Verify children are vertical, independently executable, revertible, and useful at operator checkpoints.
- Detect missing, redundant, or overlapping children and ownership split across children.
- Verify shared contracts have one owning child and dependency edges are necessary, direct, and acyclic.
- Reconcile overlap with active and archived plans plus existing epics.
- Verify the decomposition includes both an early MVP path and eventual complete delivery.
- Exclude child implementation details, typed evidence, and code-level design; child `/cip` plus `/dr` own those.

## Orchestration relationship

This child depends on `8a0644` and consumes its shared fleet scheduler. Epic review uses the same four-agent
in-flight cap, declared waves, attendance states, and provider-throttling policy as `/cip`, `/ci`, `/cr`, and
`/dr`; it does not create another dispatch implementation.

## Existing contract to extend

- `.github/skills/cep/SKILL.md` — current interview, accepted-cut, scaffold, and child handoff sequence.
- `.github/skills/cep/assets/decomposition-guide.md` — `epic-intent`, `seams`, verticality, dependency, and
	independent-executability checks currently performed by the orchestrator itself.
- `b0c0d3` REQ-15 — epic index and independently executable child-plan substrate.

## Confirmed planning decisions (2026-08-21)

- The operator confirmed the five-section intent without changes.
- The operator accepted the prior-art relationships below and accepted the scoped index caveat.
- Four epic-specific concerns run across two configured models through the shared fleet.
- Review-run v1 is authoritative and degraded attendance blocks finalization.
- Any revised cut is reconfirmed; review runs at most three automatic rounds before an operator decision.
- Execution is manual, step-scoped, and adds no third-party packages.

## Design review round 1 decision (2026-08-21)

- The operator accepted replacing mutable `epic.md` review input with stable `decomposition.rfc.md` using the existing `rfc` source kind.
- The operator accepted a first-class epic-associated review store and retained report/receipt finalization resolved through epic inventory.
- Deterministic source verification, round state, bounded dispositions, and resumable scaffolding move into scripts and schemas.
- The concern roster remains four concerns across two models, but authorship extends `79cfe1`'s generated concern registry rather than creating unmanaged agents.
- Rejected DR finding: the round-1 prompt-injection report described wrapper text in the review dispatch payload, not content in this plan. Direct hostile-input evidence remains required.

## Design review round 2 decision (2026-08-21)

- The operator accepted `review-concerns@2`: family-specific closed concern sets preserving v1 CR/DR bytes and adding four CEP coherency ids.
- The RFC is script-rendered from `skalary/epic-decomposition@1`; secret scanning precedes persistence and no prose parser drives scaffolding.
- Review rounds are operation-wide across source revisions. A typed host timeout is terminal but host-owned, matching `8a0644`.
- Degraded runs publish and retain blocked evidence; existing children are read-only; only unchanged operation-owned new scaffolds are rollback-eligible.
- `/cep` activation is deferred until runtime payloads, approvals, contracts, generated catalogs, and installed-consumer evidence converge.

## Prior-art reconciliation

- **Reuse `b0c0d3` REQ-15:** keep the epic index, ordinary sibling child plans, membership/dependency markers, and `/ci` next-child selection.
- **Extend `57cc2c`:** apply its complete-plan outcome rule to the decomposition's path from early usable value to full epic delivery.
- **Extend `6a629b`:** apply vertical/full-delivery crosschecks before child plans are created; do not change its implementation-loop ownership.
- **Reuse `34088e` RISK-6 and owner-local decision:** consume the registered scheduler limit rather than copying a cap into `/cep`.
- **Reuse/extend `8a0644` REQ-1, RISK-1, and scheduler decisions:** add `/cep` as a consumer of its fleet, waves, attendance, throttling, and `c21cdc` task records.
- **Extend `79cfe1` REQ-1 through REQ-4 and its generated-authoring decisions:** add the four epic concerns through the registry/schema/template/generator after that dependency completes; do not create a second authoring path.
- **Reuse `a5ad22`'s sequential child-execution boundary:** this plan reviews epic shape and does not orchestrate implementation.
- **No conflict or supersession was identified.** `Get-PlanIndex.ps1` also reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`; that unrelated malformed active path was disclosed and accepted as a scoped index caveat, not treated as complete-corpus evidence.

## Architecture and design context

- `docs/design-notes/architecture/plan-workflow.design.md` — epic index, child-context, prior-art, lifecycle, and distribution contracts.
- `docs/design-notes/architecture/review-reporting.design.md` — frozen task truth, generic review store, publication, verified delivery, and cleanup.
- `docs/architecture-notes/arch-review-run-v1.md` and `schemas/architecture/ARCH-Review-Run-V1.json` — provisional review authority and evidence boundary.
