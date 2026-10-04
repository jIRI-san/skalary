# Domain Model

<!-- Capture project-specific terms, actors, invariants, and boundaries that affect the design. -->

## Terms and meanings

- **Epic source folder:** the active epic directory containing `epic.md`; `Archive-Epic.ps1` refreshes
  its generated child table and then moves this folder into the canonical epic archive.
- **Linked/reparse entry:** a file or directory entry whose filesystem attributes indicate a symbolic
  link, junction, or other reparse point.
- **Archive refusal:** an explicit error before the generated table is rewritten or the source folder
  is moved; no linked directory is descended into.

## Actors and boundaries

- **Operator:** invokes and confirms the existing `Archive-Epic.ps1` mutation.
- **Archive-Epic:** owns completion checks, the confirmation gate, child-table refresh, and directory
  move.
- **Filesystem boundary:** the resolved epic source folder and its descendants inside the repository.

## Interfaces and ownership

- `Archive-Epic.ps1` owns the focused source-tree preflight; `New-Epic.ps1` retains child-table
  generation and update ownership.
- Existing plan inventory, epic rollup, archive destination, and `ShouldProcess` behavior remain in
  place.

## Invariants

- No linked or reparse entry under an epic source folder is modified or moved by the archive flow.
- The archive preflight checks attributes before descending into directories and never opens a link
  target; the existing inventory's earlier read of `epic.md` remains read-only and outside this
  mutation guard.
- A failed preflight leaves both the active epic folder and any link target unchanged.
