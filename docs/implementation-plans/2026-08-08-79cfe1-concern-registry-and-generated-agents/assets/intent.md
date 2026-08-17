# Intent

> Preliminary context captured from the 2026-08-08 comparison discussion for epic `33b1f9`. `/cip` must confirm and refine it.
> Confirmed without changes by the operator on 2026-08-16.

## Goal

Make the existing review concern taxonomy and concern-agent bodies single-authored so code-review and design-review surfaces cannot drift.

## Desired outcome

One concern registry defines the settled seven concerns and drives generated `cr-*` and `dr-*` agent variants plus related mappings. A deterministic sync command produces installed payloads, and a drift gate proves generated files match their source.

## Success signals

- Editing concern guidance or mappings requires one registry edit rather than synchronized hand edits; changing the fixed taxonomy remains an explicitly reviewed policy change outside this plan.
- Shared concern guidance reaches both review surfaces while preserving explicit surface-specific variants.
- Generated agents, manifests, dogfood copies, marketplace data, and registry hashes remain synchronized.
- Existing injection guards, read-only stance, and concern completeness tests remain enforced.

## Non-goals

- Changing which seven concerns exist or what they mean.
- Merging code review and design review into one generic reviewer.
- A registry that nothing derives from and therefore becomes another copy of the list.

## Definition of done

- All concern agents and mappings are reproducibly generated from one source, and committed drift fails validation.
