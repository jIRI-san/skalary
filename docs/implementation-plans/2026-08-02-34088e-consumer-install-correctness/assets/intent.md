# Intent

> Preliminary context captured from epic `33b1f9`, plan `768d7b` handoff D12, and the enforcement-gap review. `/cip` must confirm and refine it.

## Goal

Make every installed customization behave correctly in a repository that does not contain skalary's source tree.

## Desired outcome

A clean consumer installation resolves every skill asset, bundled script, module dependency, scaffold declaration, and canonical configuration value it needs. Consumer behavior is tested from installed paths, and constants now copied into prose are derived from or checked against one source of truth.

## Success signals

- A fresh non-skalar consumer fixture can invoke shipped skills without reaching into `plugins/` or repo-root `scripts/skalary/`.
- Every runtime path outside `.github/` has an explicit first-use scaffold contract.
- The invocation budget, plan-size thresholds, and phase-budget default cannot drift between code and prose unnoticed.
- Registry, marketplace, dogfood, and bundled payloads remain synchronized after changes.

## Non-goals

- Relaxing installer confinement outside `.github/` or adding a post-install hook.
- Reopening the review concern taxonomy.
- A general rewrite of registry or marketplace architecture unrelated to consumer correctness.

## Definition of done

- Installed-copy tests prove all shipped entry points and assets work without source-tree assumptions.
- The Cluster C constants handoff from `768d7b` is implemented and regression-gated rather than deferred again.
