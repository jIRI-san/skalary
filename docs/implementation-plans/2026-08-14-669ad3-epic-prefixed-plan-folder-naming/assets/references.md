# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

Group plan folders by epic identity at the start of the folder name. Standalone plans use the literal
`standalone` in the same position. Migrate existing plans only when they already use the current hash-name
schema; legacy numbered plans stay untouched.

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turn 8: the operator requested the epic hash at the start of plan-folder names, `standalone` in the same position, and migration only for the new hash-name schema.
- Epic `bcece1` Plan-folder grouping section records the accepted creation, attachment, re-parenting, migration, and mixed-grammar behavior.

## Target grammar

- Epic child: `<epic-id>-<yyyy-mm-dd>-<plan-id>-<slug>`.
- Standalone: `standalone-<yyyy-mm-dd>-<plan-id>-<slug>`.
- `epic-id` and `plan-id` are canonical six-hex anchors; the prefix is navigation metadata, not identity.
- Epic folders remain under `epics/` with their existing grammar unless this child's `/cip` interview
  explicitly expands scope; this request concerns plan folders.

## Prior art relationship

- **Supersedes:** `7645b1` REQ-2 and its `<date>-<hash>-<slug>` decision.
- **Narrowly supersedes:** `7645b1`'s "dual-format, no renames" decision for folders matching the current
  hash schema. The no-rename rule remains for legacy `NNN-<slug>` plans.
- **Reuses:** `7645b1` REQ-1/REQ-3/REQ-12 and its stable canonical-ID decisions. Migration never changes a
  `plan-id`, ledger plan key, `depends-on` token, or evidence identity.

## Required lifecycle behavior

1. `New-Plan.ps1` accepts an epic/group context and writes the target grammar immediately. A direct `/cip`
	plan defaults to `standalone`; `/cep` supplies the epic ID while scaffolding children.
2. `New-Epic.ps1` attachment and `-Force` re-parenting rename an eligible hash-schema plan folder together
	with the membership-marker update. Both affected epic mirrors are refreshed after the move.
3. Resolution remains anchor-based. Hash prefix, plan slug, date, and canonical ID continue to work across
	old hash, target hash, and legacy numbered grammars during migration.
4. Archival preserves the group prefix while moving the folder under `archived/`.
5. A dedicated script-owned migration handles active and archived current-hash folders, supports `-WhatIf`,
	preflights collisions and ambiguous membership, is idempotent, and emits an old-to-new manifest.
6. Current-hash folders with one valid `<!-- epic: ... -->` marker receive that epic ID; those without one
	receive `standalone`. Missing or unresolvable epic IDs fail loud rather than guessing.
7. Legacy `NNN-<slug>` folders and loose-file migration behavior remain unchanged.

## Surfaces to reconcile

- `PlanState.psm1`: inventory grammar, date/slug parsing, resolution, epic rollup, archive detection.
- `New-Plan.ps1`, `New-Epic.ps1`, and a dedicated folder migration command.
- `/cip`, `/cep`, `/ci`, autopilot archival, plan-index output, evidence/ledger references, and tests.
- Plan templates, design notes, bundled scripts, dogfood copies, plugin manifests, registry, and marketplace.

## Safety and evidence direction

Use canonicalize-then-confine checks for every source and destination. Compute the complete rename set and
reject any collision before moving the first folder. Tests cover mixed legacy/old-hash/target-hash inventories,
active and archived plans, standalone attachment, cross-epic re-parenting, rollback after a failed preflight,
idempotent replay, and stable plan resolution before and after migration.
