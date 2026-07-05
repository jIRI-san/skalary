---
description: Architecture note for Installer .github confinement — its interface-level boundary and the contracts that govern it. Load when working on code under the scope globs below.
globs:
  - "scripts/skalary/**"
---

# Installer .github confinement — Architecture Note

## Boundary

The plugin installer writes files **only** inside the consuming repo's `.github/` tree. Every
resolved destination is validated before any write; it must never write to `docs/`, `scripts/`,
`schemas/`, or any path outside `.github/`.

## Contracts

| Contract Id | Maturity | Enforces |
|---|---|---|
| `ARCH-Install-Confinement` | provisional | Every install/update write path is confined to `.github/`; escaping dests are rejected |

## Invariants

- Every resolved dest passes `Resolve-GithubConstrainedPath`; traversal (`..`), rooted, and
  absolute dests are rejected.
- `Test-Registry` rejects a manifest whose `files[].dest` escapes `.github/`, so an untrusted
  manifest can never widen the blast radius.
- No post-install hook writes outside `.github/`; repo-level scaffolding (e.g. `docs/`) is
  prompt-driven at first use, never installer-driven.

## Depends On / Depended On By

- Depends on: `registry.json` integrity index (per-file sha256), `Resolve-GithubConstrainedPath`.
- Depended on by: every plugin install/update/remove flow; the dogfood mirror.
