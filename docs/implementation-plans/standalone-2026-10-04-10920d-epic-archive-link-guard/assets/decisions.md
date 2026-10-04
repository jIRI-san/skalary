# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Keep the guard in `Archive-Epic.ps1`; do not generalize it into a new filesystem framework or
  alter unrelated plan archive flows. The existing `New-Epic.ps1` remains the sole child-table writer.
- Reject any linked/reparse entry inside the epic source tree, not only a linked `epic.md`, because
  the complete source directory is moved by the archive operation. A link target is never traversed.
- Accept the existing trusted single-operator point-in-time preflight model; do not add a mutation
  lock or transaction journal for concurrent local filesystem changes.
