# Requirements

<!-- Every discovered edge case belongs in this table, assets/risks.md, or an explicit non-goal in assets/intent.md. -->

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Before `ShouldProcess` and the child-table refresh, `Archive-Epic.ps1` rejects a linked/reparse `epic.md` using a local attribute check. No recursive descendant scan or new completion/collision error precedence is required. | In a temporary repository on a capable non-elevated host, a real file-symlink epic.md causes a clear refusal; the external target bytes are unchanged, the active epic remains in place, and no archived destination is created. `test:ArchiveEpic.LinkedEpicFile` | 1.1, 1.2 |
| REQ-2 | Keep inventory reads, existing directory guards, completion/collision checks, confirmation, and ordinary archival unchanged. | The linked-file regression preserves the original child table; existing successful archive, incomplete epic, active child, destination collision, ordinary `WhatIf`, and already-archived cases still pass. `test:ArchiveEpic` | 1.1, 1.2 |
