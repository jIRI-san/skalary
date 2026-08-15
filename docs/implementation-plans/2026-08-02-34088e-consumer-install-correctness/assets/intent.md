# Intent

> Preliminary context captured from epic `33b1f9`, plan `768d7b` handoff D12, and the enforcement-gap review. `/cip` must confirm and refine it.

## Goal

Make every installed customization behave correctly in a repository that does not contain skalary's source tree.

## Desired outcome

A clean consumer installation resolves every skill asset, bundled script, module dependency, scaffold declaration, and canonical configuration value it needs. A manifest-derived matrix covers every active plugin and exercises representative behavior from installed paths with source-tree fallbacks poisoned. Runtime paths outside `.github/` are created only through real first-use scaffold owners. Workflow limits remain with their natural machine owners, while executable parity checks bind every prose, template, generated, and future fleet-scheduler consumer to those values.

## Success signals

- A fresh non-skalar consumer fixture covers every active plugin and can exercise each shipped runtime surface without reaching into `plugins/` or repo-root `scripts/skalary/`.
- Adding or retiring a plugin changes the required consumer probe inventory automatically rather than relying on a hand-maintained plugin count.
- Every runtime path outside `.github/` has an explicit first-use scaffold contract.
- The review invocation budget, plan-size thresholds, phase-budget default, and future fleet concurrency cap cannot drift between their machine owners and consumers unnoticed.
- Registry, marketplace, dogfood, and bundled payloads remain synchronized after changes.

## Non-goals

- Relaxing installer confinement outside `.github/` or adding a post-install hook.
- Reopening the review concern taxonomy.
- A general rewrite of registry or marketplace architecture unrelated to consumer correctness.
- Moving unrelated subsystem limits into one global configuration catalog.
- Requiring network access, credentials, or live provider calls from deterministic consumer tests.

## Definition of done

- A manifest-derived installed-copy matrix proves every active plugin's executable entry points or deterministic preflight contracts and every runtime asset resolve without source-tree assumptions.
- First-use scaffolds, update/remove behavior, and source-bound retirement remain confined and fail loud under hostile and modified-consumer fixtures.
- The Cluster C constants handoff from `768d7b`, including the future scheduler-consumer pattern, is implemented and mutation-gated rather than deferred again.
