---
description: Required AI-first design-note content, format, ownership, and finalization compaction rules.
globs:
  - docs/design-notes/**
---

# Design Note Writing Style

Design notes are AI reference material first. Write for a capable developer who knows the technology
but not this repository's choices. Preserve only context the source cannot provide cheaply.

| Priority | Include |
|---|---|
| 1 | Non-obvious decisions and rationale |
| 2 | Architectural contracts and concise data/interface shapes |
| 3 | Project-specific patterns and hard constraints |
| 4 | Exceptions and minimal representative examples |

Omit tutorials, generic advice, future/conclusion/background sections, date/status headers, verbatim
source, and cross-cutting principles owned elsewhere. Frontmatter is the overview; do not repeat it in
`Purpose`, `Overview`, or `Background`. Prefer tables for repeated attributes, compressed examples,
source links over copies, and one owner plus short links for shared principles.

## Finalization compaction

When plan work edits `docs/design-notes/**`, CI/autopilot runs one bounded semantic pass. Discovery
starts with the active index, touched notes, scopes, and links/named concepts; never preload the corpus.
Compare full text in sequential batches of five maximum and carry a concise accumulated summary.

Remove stale narration and duplicates while preserving every unique active decision, contract,
constraint, exception, and minimal example. Uncertainty preserves content. Cross-note merge/delete
requires explicit operator approval over candidate paths, resulting owner, preserved unique items, and
the relevant Git diff. The installed protocol owns cancellation, index/link updates, and headless stop.
`docs/operator-guide/**` never participates.

## Required shape

```yaml
---
description: <scope and when to load; this is the overview>
globs:
  - <relevant path glob>
---
```

Use only sections the topic needs:

```markdown
# Title
## Architecture
## Key Patterns
## Design Decisions
## Constraints
```

Keep rationale dense; never leave empty sections.
