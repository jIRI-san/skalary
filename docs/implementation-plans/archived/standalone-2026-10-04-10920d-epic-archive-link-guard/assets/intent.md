# Intent

<!-- Captured during the /cip interview. -->

## Goal

Prevent epic archival from following a linked epic source into a write outside the repository.

## Desired outcome

When `Archive-Epic.ps1` targets an active epic whose `epic.md` is a link or reparse point, reject the
archive before confirmation and child-table refresh. The linked target remains unchanged, the epic
remains active, and normal archival behavior for an ordinary epic file is preserved.

### Selected operator wording and confirmed interpretation

- Source/date: RCS follow-up scope correction, 2026-10-04
- Operator wording: "ok, lets go with that" (the reduced epic.md write-guard scope).
- Confirmed interpretation: Guard the epic.md write path locally before confirmation and refresh; do not scan descendants or add a separate linked-source WhatIf acceptance requirement.
- Scope/exception: Preserve inventory reads, existing directory guards, completion/collision checks, and ordinary archive behavior. No generalized filesystem framework or lock.

## Success signals

- A real file-symlink `epic.md` fixture is refused without changing the external target or moving the
  active epic.
- Existing archive completion, collision, `WhatIf`, and successful ordinary-epic behaviors remain
  covered and unchanged.

## Non-goals

- Changing `New-Epic.ps1` behavior outside the archive-refresh call path or broadening this into
  general plan inventory/link hardening.
- A new filesystem abstraction, mutation lock, archive journal, or race-proof transaction.
- Changing standalone plan archival, completion criteria, operator confirmation, or generated child
  table ownership.
- Recursive descendant-link hardening, junction fixtures, collision/completion error precedence, or
  a separate linked-source `-WhatIf` acceptance requirement.

### Delegated discretion and deferred choices

- Authorized choice and bounds: choose the smallest local attribute check that rejects a linked/reparse
  epic.md before confirmation and refresh; preserve the existing archive lifecycle.
- Deferred choice, owner, and resolve-or-stop condition: none. If a required link fixture cannot be
  created on this host, use an available symlink-capable non-elevated host (such as Linux). If none is
  available, report the unverified case and stop without claiming acceptance. Do not elevate the
  coding app or change host-wide settings for this test.

## Definition of done

- The focused real file-symlink regression passes; existing archive gates and ordinary archive behavior
  remain unchanged.
