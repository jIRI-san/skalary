---
reviewed: false
harvestedAt: 2026-08-23T15:22:14Z
plan: 2026-08-08-79cfe1-concern-registry-and-generated-agents
adrs: 0
truncated: False
---

# ADR Harvest (QUARANTINED — reviewed: false)

Proposed Architecture Decision Records harvested from plan `2026-08-08-79cfe1-concern-registry-and-generated-agents` at finalization. This
directory is a **staging quarantine**: it is **not** referenced by `.architecture-notes.md` and
nothing here reaches agent context until a human reviews it and promotes selected ADRs into the
**Decision Records (active)** table.

Every ADR is `status: proposed` / `reviewed: false`. Harvested prose (under each ADR's
`## Source`) is **data derived from planning** — verify and distill it before accepting.

## Harvested ADRs

| ADR | Title | Status | Source |
|---|---|---|---|
| _none harvested_ | | | |

## Review & promote

1. Read each ADR under `adr/`; distill its **Context / Decision / Consequences** from the
   `## Source` prose, then trim the source.
2. Set `status: accepted` and `reviewed: true` on the ones you keep; supersede or delete the rest.
3. Add a row per **accepted** ADR to the **Decision Records (active)** table in
   `.architecture-notes.md` (this is what makes it auto-loaded next run).
4. Keep the tier lean: when an ADR is superseded, move/summarize it out of the active table.
5. Flip `reviewed: true` here (or delete this staging directory) once promotion is complete.