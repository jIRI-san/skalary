# Decision: Seeding & Evolution Flows

## Context
Architecture notes must support "no big design upfront" (pillar a): start small, grow one
contract at a time. Two entry scenarios exist — new project and existing project.

## Greenfield (new project) — always short interview on init
`/architecture-notes init` (and the init skill path) runs a **short** seeding interview:
- Asks for system type, top-level layers, primary module boundaries.
- Seeds **1–2 `draft` contracts** + a **human-doc skeleton**.
- Everything starts `draft` (warn-only) — nothing `locked` until deliberately promoted.
Thereafter `/cip` grows the notes: architecture decisions made during planning become new
`draft` contracts, promoted to `locked` when you are ready to enforce them.

## Brownfield (existing project) — harvest → draft → review → lock
1. **Harvest.** The skill scans repo structure, project/solution files, namespaces, existing
   interfaces, and the dependency graph to infer candidate layers/boundaries/contracts.
2. **Draft.** Writes an initial arch-notes set + generates the human doc — **all `draft`
   (warn-only)**. Inferred ≠ intended, so nothing blocks the build on import.
3. **Human review.** You correct/confirm; promote the contracts you actually want enforced to
   `locked`. Arch tests only start blocking once a contract is locked.
4. **Evolve.** Identical to greenfield thereafter.

## Convergence
Both scenarios converge on the same steady-state loop:
`/cip` → decisions → contracts → arch tests → ADR harvest → `/uan` regenerates human doc.
They differ only in the **seeding** step (empty/light vs harvest+review).

## Rationale
Harvested contracts landing as warn-only means importing arch notes into a messy existing
codebase never instantly breaks its build — you lock incrementally, which doubles as a
tech-debt burn-down tool. The always-on greenfield interview seeds just enough structure to be
useful without big design upfront.
