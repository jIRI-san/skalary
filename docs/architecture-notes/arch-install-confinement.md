---
description: Architecture note for Installer .github confinement — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "scripts/skalary/**"
---

# Installer .github confinement — Architecture Note

## Boundary

Plugin install, update, explicit removal, and automatic retirement mutate files **only** inside the
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
  before state reads, stats, journal/backup writes, deletion, or directory pruning.
- All mutating plugin operations serialize through `.github/.skalary/mutation.lock`. Removal
  rederives authority while holding that lock.
- Removal journals are untrusted. Recovery validates schema, plugin/source/transaction identity,
  confined destination and backup paths, backup hashes, and the exact receipt pre/post state before
  restoring anything.
- Automatic retirement can delete only the exact intersection of a tombstone-pinned
  source/ref/version/destination/hash set and the current same-source receipt. Modified files remain
  owned by a degraded receipt.
- `Test-Registry` rejects a manifest whose `files[].dest` escapes `.github/`, so an untrusted
  manifest can never widen the blast radius.
- No post-install hook writes outside `.github/`; repo-level scaffolding (e.g. `docs/`) is
  prompt-driven at first use, never installer-driven.

## Depends On / Depended On By

- Depends on: `registry.json` integrity index (per-file sha256), `Resolve-GithubConstrainedPath`,
  versioned source identity, mutation lock, and the removal journal.
- Depended on by: every plugin install/update/remove flow; the dogfood mirror.
