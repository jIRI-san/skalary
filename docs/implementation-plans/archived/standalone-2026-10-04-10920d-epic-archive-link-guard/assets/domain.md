# Domain Model

<!-- Capture project-specific terms, actors, invariants, and boundaries that affect the design. -->

## Terms and meanings

- **Epic source folder:** the active epic directory containing `epic.md`; `Archive-Epic.ps1` refreshes
  its generated child table and then moves this folder into the canonical epic archive.
- **Linked/reparse entry:** a file or directory entry whose filesystem attributes indicate a symbolic
  link, junction, or other reparse point.
- **Archive refusal:** an explicit error for a linked epic.md before confirmation, table refresh,
  or source-folder move.

## Actors and boundaries

- **Operator:** invokes and confirms the existing `Archive-Epic.ps1` mutation.
- **Archive-Epic:** owns completion checks, the confirmation gate, child-table refresh, and directory
  move.
- **Filesystem boundary:** the epic.md path used by the archive child-table refresh.

## Interfaces and ownership

- `Archive-Epic.ps1` owns the local epic.md attribute guard; `New-Epic.ps1` retains child-table
  generation and update ownership.
- Existing plan inventory, epic rollup, archive destination, and `ShouldProcess` behavior remain in
  place.

## Invariants

- The archive refresh does not write through a linked/reparse epic.md.
- The guard checks epic.md attributes, not descendants; the inventory's earlier read remains
  read-only and outside this mutation guard.
- Guard refusal leaves the active epic folder and linked target unchanged. Nested links and
  concurrent replacement are outside the new guarantee.
