---
description: Architecture note for Installer .github confinement — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "scripts/skalary/**"
---

# Installer .github confinement — Architecture Note

## Boundary

Plugin install, update, and explicit removal mutate files **only** inside the
consuming repo's `.github/` tree. Every payload and managed-state destination is validated before
state reads or filesystem mutation; no flow may touch `docs/`, `scripts/`, `schemas/`, or any path
outside `.github/`.

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Install-Confinement` | provisional | Every install/update/remove/retirement path is confined to `.github/`; escaping and linked dests are rejected |

## Invariants

- Every resolved dest passes `Resolve-GithubConstrainedPath`; traversal (`..`), rooted, and
  absolute dests are rejected.
- Existing destinations and every parent segment are rejected when they are links/reparse points,
  before receipt reads or writes, payload access, deletion, or directory pruning.
- Each installed plugin has exactly one confined receipt with `name`, `version`,
  `sourceIdentity`, and immutable `ref`. Receipt paths and shape are revalidated before use.
- Install and update preflight their complete manifest sets, apply and verify payload bytes, then
  write the receipt last. A failure exposes any partial payload state and leaves the prior receipt
  truth intact for a convergent retry; there is no lock, journal, backup, rollback, or recovery.
- Update overwrites paths authorized by its matching plugin/source receipt, including locally edited
  paths. Install refuses an unowned collision unless explicitly forced.
- Removal materializes the pinned manifest from the receipt ref, verifies every present target before
  unforced deletion, and removes the receipt last. `-Force` is required to remove modified targets
  or bypass dependent-plugin refusal.
- Published retirement metadata refuses install and update. It never deletes an installed plugin;
  explicit `Remove-Plugin` is the sole cleanup authority.
- `Test-Registry` rejects a manifest whose `files[].dest` escapes `.github/`, so an untrusted
  manifest can never widen the blast radius.
- No post-install hook writes outside `.github/`; repo-level scaffolding (e.g. `docs/`) is
  prompt-driven at first use, never installer-driven.

## Depends On / Depended On By

- Depends on: `registry.json` integrity index (per-file sha256), `Resolve-GithubConstrainedPath`,
  versioned source identity, and immutable source materialization.
- Depended on by: every plugin install/update/remove flow; the dogfood mirror.
