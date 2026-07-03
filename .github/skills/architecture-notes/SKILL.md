---
name: architecture-notes
description: 'Architecture Notes — author and evolve interface-level architectural contracts (the unbreakable, high-level design tier) separate from implementation-level design notes. Use to seed a new project''s architecture, harvest an existing one, add or update a contract, promote a contract to locked, and keep the human-readable architecture doc in sync. Invoke directly, or via the /can and /uan prompt shortcuts.'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Architecture Notes

> This skill is the primary, CLI-standalone experience for the architecture-notes tier.
> `/can` (create) and `/uan` (update) are thin prompt wrappers that defer here.

> **Scaffold note:** the full create/update/review workflow is authored in step 2.1.
> This skeleton establishes the plugin surface and skill contract.

## Step 1: Select operation

1. Determine the requested operation: **create** a contract, **update** a contract, **review**
   the tier, **seed** a greenfield project, or **harvest** an existing one.
2. Load the architecture-notes index (`docs/architecture-notes/.architecture-notes.md`) if present.
3. Defer to the operation-specific procedure (authored in Phase 2/3).
