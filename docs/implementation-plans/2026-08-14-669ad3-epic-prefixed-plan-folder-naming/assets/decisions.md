# Decisions

- **Prefix only new hash plans by default.** New epic children and standalone plans start with their final navigational prefix.
- **Preserve canonical identity.** `plan-id` remains authoritative; folder prefix, branch, worktree, run, and review names do not become identity.
- **Preserve legacy numbered plans.** `NNN-<slug>` folders are never renamed or reinterpreted.
- **Keep current hash folders readable.** Existing unprefixed hash-schema folders remain supported; migration is optional and operator-run.
- **Retain a script-owned migration capability.** Confirmed intent requires a migration path, so one simple command provides deterministic `-WhatIf`, mapping, apply, and resume.
- **Preflight before movement.** Collision, identity, membership, and confinement errors reject the run before any folder moves.
- **Use sequential recovery.** One existing repository lock or safe sequential move plus mapping progress is sufficient; no namespace transaction protocol is needed.
- **Defer bulk migration.** This implementation ships and tests the command but does not automatically migrate active or archived plans.
- **Reuse shared resolution.** Inventory, plan state, epic rollup, archive, and test consumers learn the additional grammar through existing helpers.
- **Reject prior platform expansion.** No namespace protocol, capability/journal schemas, new exits, review-run contract changes, container relaunches, host authority mounts, four-tuple CI aggregation, or new architecture contract is included.

## Simplification decision

The accepted cut separates future naming from corpus migration. New plans gain the prefix immediately; existing plans remain valid until an operator explicitly reviews and applies the bounded migration mapping.
