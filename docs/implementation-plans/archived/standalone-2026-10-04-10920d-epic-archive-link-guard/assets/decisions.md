# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Keep the guard in `Archive-Epic.ps1`; do not generalize it into a new filesystem framework or
  alter unrelated plan archive flows. The existing `New-Epic.ps1` remains the sole child-table writer.
- Reject linked/reparse `epic.md` only: it is the path refreshed by the archive flow. Do not add a
  recursive descendant scan; moving nested links is not the demonstrated write-through defect.
- Place the guard before `ShouldProcess` and refresh, without requiring it to precede existing
  completion/collision errors. No separate linked-source `WhatIf` acceptance criterion.
- Prove the write-through refusal with a real file symlink on a capable non-elevated host. Do not
  elevate the coding app or change Windows Developer Mode for this test.
- Accept the existing trusted single-operator point-in-time preflight model; do not add a mutation
  lock or transaction journal for concurrent local filesystem changes.
