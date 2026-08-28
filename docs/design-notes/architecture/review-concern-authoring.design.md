---
description: Single-source authoring and deterministic generation for CR/DR concern agents and concern-to-ledger mappings. Load before changing the concern registry, template, generator, generated concern payloads, or their tests.
globs:
  - tools/review-concerns.json
  - tools/review-concern-agent.template.md
  - schemas/review/review-concerns.schema.json
  - scripts/skalary/Sync-ReviewConcerns.ps1
  - plugins/{code-review,design-review}/agents/{cr,dr}-*.agent.md
  - plugins/{code-review,design-review}/skills/{cr,dr}/assets/concern-ledger-map.md
  - tests/skalary/ReviewConcerns.Tests.ps1
---

# Review concern authoring

## Ownership

| Surface | Authority | Rule |
|---|---|---|
| Concern policy | `tools/review-concerns.json` | Defines the closed seven-concern roster in canonical order, shared guidance, optional generic standards, explicit CR/DR variants, and total ledger mappings. |
| Agent structure and safety | `tools/review-concern-agent.template.md` | Owns read-only tools, no-model binding, untrusted-content handling, architecture-before-design context loading, and finding output shape. Registry prose cannot alter these controls. |
| Registry shape | `schemas/review/review-concerns.schema.json` | Rejects missing variants, mappings, or malformed fields before rendering. |
| Generation | `scripts/skalary/Sync-ReviewConcerns.ps1` | Renders all 14 agents, both mapping views, and both generic-standards assets; validates the complete candidate set before writing; and removes only extra `cr-*.agent.md`/`dr-*.agent.md` files in its confined managed directories. |
| Generated plugin payloads | `plugins/code-review/agents/cr-*.agent.md`, `plugins/design-review/agents/dr-*.agent.md`, and each review skill's `concern-ledger-map.md` and `review-standards.json` | Never hand-edit. Regenerate with `Sync-ReviewConcerns.ps1`; the template applies only to agents, while dedicated renderers own map and standards structure. |

The taxonomy is settled policy, not an extension point. Adding, removing, reordering, or redefining a
concern requires a separately reviewed policy change; ordinary guidance changes preserve all seven ids.
Model selection also stays outside this source: generated agents declare no `model`, and the CR/DR
orchestrators remain the explicit model-binding authority.

Optional `standards[]` entries attach bounded generic guidance to a concern. Each stable id declares
whether repository-local guidance may refine it. `Resolve-ReviewStandards.ps1` reads the fixed optional
`docs/review-standards.md` file and accepts only `extend` or `replace` lines for ids marked
`localizable`; unknown, duplicate, non-localizable, malformed, oversized, non-UTF-8, or link-routed
input fails closed. The local file remains repository-owned and absence returns the generic set
unchanged.

## Generation contract

`Sync-ReviewConcerns.ps1` canonicalizes the repository root, rejects path escapes and reparse points,
validates every registry substitution, renders every output in memory, and only then mutates files.
Output order and LF/UTF-8-without-BOM bytes are deterministic. `-WhatIf` compares exact bytes and is
detect-only: changed, missing, hand-edited, encoding-drifted, or extra generated agents/mappings fail
without repairing the tree.

Template placeholders are a closed interface between the template and generator. Adding or removing a
placeholder requires updating both sides and the placeholder assertion in
`tests/skalary/ReviewConcerns.Tests.ps1`; unresolved placeholders are generation failures. Free-form
registry prose rejects line breaks, template-token characters, and Markdown block-forming prefixes so it
cannot create template structure or tokens.

## Distribution boundary

Generation stops at plugin sources. Generated agents, maps, and standards assets must each be declared exactly once by their owning
plugin manifest. A payload-byte change requires the owning plugin version to move, followed by the
existing dogfood, marketplace, and registry writers. Those writers retain their own authority:
`Sync-Dogfood.ps1` mirrors installed `.github/` payloads, `Build-Marketplace.ps1` publishes manifest
versions, and `Build-Registry.ps1` publishes versions plus payload hashes.

`test:ReviewConcerns.GeneratedBehaviorAndDistribution` proves that chain. The generator does not absorb
manifest editing, versioning, dogfood synchronization, or catalog publication; combining those
responsibilities would duplicate the repository's packaging transaction model.

## Evidence

| Test marker | Invariant |
|---|---|
| `test:ReviewConcerns.RegistryAndTemplate` | Closed roster, valid variants/mappings, and template-owned safety/context/output structure. |
| `test:ReviewConcerns.DeterministicGeneration` | Confined all-before-write rendering, explicit surface differences, convergence, and refusal of unsafe outputs. |
| `test:ReviewConcerns.GeneratedBehaviorAndDistribution` | Generated behavior, manifest declarations, dogfood bytes, versions, and registry hashes stay aligned. |
| `test:ReviewConcerns.GenerationDrift` | Detect-only failure for changed, missing, extra, hand-edited, and encoding-drifted outputs; a registry mutation changes every expected output and a second pass is byte-stable. |
| `test:ReviewStandards.GenericLocalResolution` | Generic-only and absent-local behavior are stable; bounded local extension/replacement is explicit and malformed or non-localizable input fails closed. |
