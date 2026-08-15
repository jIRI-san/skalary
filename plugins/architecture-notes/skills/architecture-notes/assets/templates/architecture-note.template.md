---
description: Architecture note for <SUBSYSTEM> — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "<SCOPE_GLOB>"
---

# <SUBSYSTEM> — Architecture Note

<!-- Terse. Describe the boundary and the unbreakable contracts, not implementation detail.
     Implementation guidance belongs in docs/design-notes/. Keep this note context-cheap. -->

## Boundary

<!-- One or two sentences: what this component is responsible for and what it must never do. -->

## Contracts

<!-- Reference the machine-checkable contract ids that govern this boundary. -->

| Contract Id | Maturity | Enforces |
|---|---|---|
| `<CONTRACT_ID>` | draft | <what the contract guarantees> |

## Invariants

<!-- Bullet the interface-level rules that must always hold. Keep to true contracts, not
     preferences. -->

- <invariant>

## Depends On / Depended On By

<!-- Only the architectural relationships that matter for contract reasoning. -->

- Depends on: <component>
- Depended on by: <component>
