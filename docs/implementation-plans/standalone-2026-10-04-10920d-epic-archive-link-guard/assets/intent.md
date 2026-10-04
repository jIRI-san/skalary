# Intent

<!-- Captured during the /cip interview. -->

## Goal

Prevent epic archival from following a linked epic source into a write outside the repository.

## Desired outcome

When `Archive-Epic.ps1` targets an active epic whose `epic.md` or any entry under the epic folder is
a link or reparse point, reject the archive before the generated child table is refreshed or the
folder is moved. A linked target remains unchanged, the epic remains active, and normal archival
behavior for an ordinary epic folder is preserved.

### Selected operator wording and confirmed interpretation

- Source/date: RCS follow-up selection, 2026-10-04
- Operator wording: "Create a corrective plan via /cip (Recommended)"
- Confirmed interpretation: Plan a focused correction to reject linked or reparse epic sources before `New-Epic.ps1` refreshes the child table or `Archive-Epic.ps1` moves the folder.
- Scope/exception: Applies to the epic source folder and its entries during `Archive-Epic.ps1`; preserve current confirmation, completion, collision, and ordinary archive behavior. No generalized filesystem framework or lock.

## Success signals

- A linked `epic.md` fixture is refused without changing the external target or moving the active
  epic; a linked descendant fixture is also refused without traversing it.
- Existing archive completion, collision, `WhatIf`, and successful ordinary-epic behaviors remain
  covered and unchanged.

## Non-goals

- Changing `New-Epic.ps1` behavior outside the archive-refresh call path or broadening this into
  general plan inventory/link hardening.
- A new filesystem abstraction, mutation lock, archive journal, or race-proof transaction.
- Changing standalone plan archival, completion criteria, operator confirmation, or generated child
  table ownership.

### Delegated discretion and deferred choices

- Authorized choice and bounds: choose the smallest local preflight that rejects linked/reparse epic
  entries without traversing them; preserve the existing archive lifecycle.
- Deferred choice, owner, and resolve-or-stop condition: none. If a required link fixture cannot be
  created on the host, stop and report the exact unverified case rather than weakening the criterion.

## Definition of done

- Focused linked-file and linked-directory regression tests pass; existing archive gates and ordinary
  archive behavior remain unchanged.
