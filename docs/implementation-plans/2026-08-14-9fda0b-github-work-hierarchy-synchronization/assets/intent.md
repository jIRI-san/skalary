# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Synchronize implementation epics and plans into a useful GitHub work hierarchy while keeping the model extensible to Azure DevOps later.

## Desired outcome

Existing or new local epics and plans can create or update a GitHub Projects v2 and issue hierarchy carrying goals, purpose, dependencies, and acceptance criteria. Stable local identities and remote links support repeated synchronization and extension without duplicating work items.

## Success signals

- A whole epic can populate a navigable GitHub hierarchy with meaningful descriptions and acceptance criteria.
- Existing GitHub epics, features, or work items can be linked and extended idempotently.
- Local plan and epic IDs retain stable remote mappings and synchronization reports conflicts instead of guessing.
- Provider-neutral interfaces leave a clear Azure DevOps extension seam.

## Non-goals

- Live Azure DevOps integration in the first delivery.
- Making GitHub the authority for local plan content or lifecycle state.
- Automatic destructive reconciliation of remote user edits.

## Definition of done

- A real local epic can be synchronized to GitHub, updated on a second run without duplication, and traced both directions through stable recorded links.
