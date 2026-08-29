# Decisions

- **Preserve confirmed intent.** The five-section intent asset remains the execution anchor; vertical slicing changes organization, not `/cip`'s responsibility to plan the complete outcome.
- **Use three confirmation checkpoints.** `/cip` confirms intent, domain/design context, and the final pre-draft summary. Corrections return to the affected checkpoint.
- **Use existing Markdown assets.** Intent, domain, design, decisions, risks, and references hold human meaning. No parallel JSON authority is introduced.
- **Use one lifecycle marker.** Current lifecycle machinery writes and reads one confirmation marker after all three checkpoints and invalidates it when intent or design changes.
- **Keep design concise.** A Mermaid program flow is required; call stacks are optional when they clarify important control flow.
- **Keep semantic judgment human.** Deterministic checks prove required sections, routing, and marker freshness. The operator and design review judge whether the plan and slices express the intended behavior.
- **Reuse existing distribution machinery.** Layout resolvers, `Set-PlanStage`, `Get-PlanState`, plugin generators, sync writers, and current test infrastructure remain authoritative.
- **Reject the prior Interview Gates platform.** Do not add an Interview Gates schema/service, installed reader/writer fleet, separate enrollment state, lock or repair protocol, version negotiation, revocation protocol, cache, telemetry, or a new architecture contract. These mechanisms are disproportionate to three confirmations and must not be reintroduced by later design review without new confirmed operator intent.
- **Reject infrastructure-only dependencies.** This plan has no child-plan dependency; richer cross-plan context may be consumed when available but cannot block confirming local intent and design.
- **Use the existing evidence receipt.** Typed tests and design review markers feed current receipt machinery; no second receipt or activation path is created.

## Simplification decision

The 2026-08-22 review found that a local interview behavior had expanded into a durable protocol family. The accepted cut is the smallest behavior that satisfies confirmed intent: existing Markdown assets, three checkpoints, one lifecycle-written confirmation marker, and invalidation on intent/design edits.
