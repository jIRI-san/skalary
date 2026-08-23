# Intent

> Preliminary context captured from epic `33b1f9`, plan `768d7b` handoff D12, and the enforcement-gap review. `/cip` must confirm and refine it.

## Goal

Make every installed customization behave correctly in a repository that does not contain skalary's source tree.

## Desired outcome

A clean consumer installation resolves every skill asset, bundled script, module dependency, and scaffold declaration it needs. A manifest-derived matrix covers every active plugin and exercises representative behavior from installed paths with source-tree fallbacks poisoned. Runtime paths outside `.github/` are created only through real first-use scaffold owners.

## Success signals

- A fresh non-skalar consumer fixture covers every active plugin and can exercise each shipped runtime surface without reaching into `plugins/` or repo-root `scripts/skalary/`.
- Adding or retiring a plugin changes the required consumer probe inventory automatically rather than relying on a hand-maintained plugin count.
- Every runtime path outside `.github/` has an explicit first-use scaffold contract.
- Registry, marketplace, dogfood, and bundled payloads remain synchronized after changes.

## Non-goals

- Relaxing installer confinement outside `.github/` or adding a post-install hook.
- Reopening the review concern taxonomy.
- A general rewrite of registry or marketplace architecture unrelated to consumer correctness.
- Moving unrelated subsystem limits into one global configuration catalog.
- Requiring network access, credentials, or live provider calls from deterministic consumer tests.
- Owning workflow-limit parity, fleet-scheduler handoff, architecture-retirement transitions, or a new per-plugin process/report protocol.

## Definition of done

- A manifest-derived installed-copy matrix proves every active plugin's executable entry points or deterministic preflight contracts and every runtime asset resolve without source-tree assumptions.
- First-use scaffolds remain confined and fail loud under hostile and modified-consumer fixtures.
- Current bundle, dogfood, manifest, marketplace, and registry drift checks pass.
