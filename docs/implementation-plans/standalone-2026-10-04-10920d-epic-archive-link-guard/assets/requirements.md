# Requirements

<!-- Every discovered edge case belongs in this table, assets/risks.md, or an explicit non-goal in assets/intent.md. -->

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Immediately after resolving an active epic and before completion/collision gates or `ShouldProcess`, `Archive-Epic.ps1` rejects a linked/reparse `epic.md` or any linked/reparse descendant. This refusal also applies with `-WhatIf`. The source-tree preflight must not descend into link targets. | In a temporary repository, a file symlink and a linked directory each cause a clear refusal; a linked source is also refused with `-WhatIf`. The external target bytes are unchanged, the active epic remains in place, and no archived destination is created. `test:ArchiveEpic.LinkedEpicFile` `test:ArchiveEpic.LinkedDescendant` | 1.1, 1.2 |
| REQ-2 | Refusal occurs before the archive flow invokes `New-Epic.ps1` to refresh the generated child table; ordinary source folders retain existing behavior and gates. | Linked-source cases preserve the original `epic.md` bytes and child table; existing successful archive, incomplete epic, active child, destination collision, `WhatIf`, and already-archived cases still pass. `test:ArchiveEpic` | 1.1, 1.2 |
