# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

> Confirmed by the operator without changes on 2026-08-16 during `/cip 669ad3`.

## Goal

Group hash-schema plan folders by epic at the start of their names, using `standalone` for plans with no epic, while preserving canonical plan identity.

## Desired outcome

New child folders use `<epic-id>-<yyyy-mm-dd>-<plan-id>-<slug>` immediately and direct `/cip` plans use `standalone-...`. A script-owned migration safely renames eligible active and archived hash-schema folders, while resolution, archival, re-parenting, and all consumers support both old and target grammars during rollout.

## Success signals

- Plans sort into navigable epic groups in the filesystem without changing their six-hex IDs.
- `/cep` never creates a temporary standalone child name before attaching it.
- Migration is confined, collision-preflighted, idempotent, supports `-WhatIf`, and emits an old-to-new manifest.
- Legacy `NNN-<slug>` plans remain untouched and resolvable.

## Non-goals

- Renaming legacy numbered plans.
- Using folder prefixes as canonical identity.
- Changing epic-folder naming unless the later `/cip` interview explicitly expands scope.

## Definition of done

- New creation, attachment, re-parenting, archival, migration, and resolution paths preserve identity and work across mixed legacy, old-hash, and prefixed-hash inventories.
