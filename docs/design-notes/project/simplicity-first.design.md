---
description: First design rule for this single-operator skill repository. Load before proposing, implementing, or reviewing any change.
globs:
  - "**"
---

# Simplicity First

Prefer deletion, reuse, or a local fix, in that order, before adding machinery. Skalary is a
single-operator skill repository, not a distributed platform. Optimize for understandable local
behavior and operator productivity.

## Review contract

`/dr` and `/cr` cannot override this rule. A finding that adds a service, schema, receipt, cache,
policy engine, compatibility layer, or generalized framework must identify a current user-visible
failure that cannot be fixed locally. Otherwise reject it as overengineering.

Safety remains relevant, but this repository primarily runs in the operator's trusted environment.
When a design cannot stay both simple and safe, choose the simple design and add a
`## Dubious decisions` section to the affected design note. Record the concrete tradeoff and the
condition that would justify revisiting it.

## Boundaries

| Prefer | Avoid |
|---|---|
| Direct commands and readable Markdown | Wrappers, generated policy, and internal schemas |
| Focused deterministic checks | Routine broad suites and duplicated evidence |
| One owner and one implementation path | Parallel adapters, compatibility layers, and speculative extension points |
| Explicit operator decisions | Autonomous policy invented by reviewers |
