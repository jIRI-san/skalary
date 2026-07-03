# Decision: Dual Representation (AI form + human doc)

## Context
There is tension between the format an AI agent consumes best (terse, contract-focused,
context-cheap) and what a human needs (diagrams, links, rationale, narrative). Both must exist
and stay in sync as the architecture evolves.

## Decision
Two synchronized forms, one source of truth.

### AI-optimized form — source of truth
- Lives in `docs/architecture-notes/` (contracts, ADRs, `.architecture-notes.md` index).
- Terse, machine-parseable, optimized purely for agent consumption.
- **Auto-loaded** by `/cip` and `/ci` via the index (mirrors design-notes loading).

### Human-readable form — generated/derived artifact
- Full-scope living document: Mermaid diagrams, resource links, rationale, prose detail.
- **Regenerated after every arch change** by the update flow (`/uan` / update skill).
- **Excluded from AI auto-load** — kept out of the `.architecture-notes.md` load path so it
  never pollutes agent context. Agents read it only on explicit demand.
- **Hierarchy-capable**: for larger projects it can evolve from a single overview into a tree
  (top-level overview → per-subsystem docs).

## Placement
- AI tier: `docs/architecture-notes/**` (auto-loaded).
- Human doc: a dedicated location excluded from the index (e.g. `docs/architecture/**` or a
  clearly non-indexed subtree). Final path decided in Phase 3; the invariant is
  **not indexed for auto-load**.

## Sync / drift control
The AI form is authoritative; the human doc is a generated artifact.

- **Concrete regeneration trigger.** Generation is not a bare convention — it fires from the
  `/uan` update flow (and is checkable as a validation step), so a manual-mode plan still has
  an enforcement point when an arch note changes.
- **Content-hash binding (not mtimes), canonically computed.** The generator embeds a
  **hash of the contract sources** into the human doc; `Test-ArchDocFreshness.ps1` recomputes it
  and flags drift when it diverges. File mtimes are unreliable across clones/rebases/checkouts
  and forgeable, so they are not the signal. The hash is **canonical** so it is stable cross-OS
  and **sensitive to add/delete** (not just edits):
  - enumerate contract sources by **normalized relative path**, **excluding generated docs**;
  - normalize to **UTF-8 + fixed line endings**;
  - hash `(path + NUL + content)` records in **sorted path order**;
  - embed the digest in a **fixed metadata marker** in the human doc.
  A naive "concatenate currently-discovered files" hash would miss a contract add/delete —
  reintroducing silent drift for the exact "grow one contract at a time" workflow — and would be
  flaky across Windows/Linux line endings.

This mirrors the design-note maintenance-protocol and the bundle-drift gate. Regeneration is
part of the update flow's definition-of-done, not optional follow-up.

## Rationale
Keeping the human doc generated (not hand-maintained) prevents the two forms from forking.
Excluding it from auto-load protects the agent context budget — the whole point of the terse
AI form. Hierarchy support lets the human doc scale without bloating the AI tier.
