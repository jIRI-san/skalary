# Architecture Notes

Interface-level architectural contracts and decision records (ADRs) for this project. This
tier is the **AI-optimized source of truth**: terse, contract-focused, and auto-loaded by
`/cip` and `/ci`. It captures the **unbreakable, high-level contracts** a human owns — the
*what* and the boundaries — while implementation detail lives in `docs/design-notes/`.

> The human-readable architecture document (diagrams, rationale, links) is a **generated
> artifact** kept **out of this index** so it never pollutes agent context. Read it only on
> explicit demand.

## How These Work

- Load this index first. Then read only the arch note(s) and contract(s) relevant to the task.
- Contracts are schema-validated and locked content is digest-pinned by the architecture-notes
  write and repository integrity gates.
- `locked` contracts are reviewer-approved and content-pinned; `draft`/`provisional` are advisory.
  Human promotion is reviewer-enforced policy, not machine-authenticated identity.

## Maintenance Protocol (Required)

When a change alters an interface-level contract or an architectural boundary, update the
corresponding arch note and/or contract **in the same change**. Regenerate the human-readable
document via the update flow (`/uan`). Treat these as part of the definition of done, not
optional follow-up.

Keep the auto-loaded tier lean: retire superseded ADRs (archive/summarize) so only **active**
decisions remain here.

## Contracts

| Contract Id | Title | Maturity | Applies To | Note |
|---|---|---|---|---|
| _none yet_ | | | | |

## Architecture Notes

| File | Scope | Contracts |
|---|---|---|
| _none yet_ | | |

## Decision Records (active)

| ADR | Decision | Status | Date |
|---|---|---|---|
| _none yet_ | | | |

## Adding a Contract or Note

1. Author or update the contract JSON under `schemas/` (validated by
   `architecture-contract.schema.json`); start at `draft` maturity.
2. Add a terse arch note (see the arch-note template) describing the boundary and referencing
   the contract id(s).
3. Add rows to the tables above.
4. Regenerate the human-readable doc via `/uan`.
