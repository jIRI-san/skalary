---
description: Deterministic local epic and plan projection plus the narrow provider boundary used by GitHub work hierarchy synchronization
globs:
  - scripts/skalary/*WorkHierarchy*
  - plugins/work-hierarchy-sync/**
  - tests/skalary/WorkHierarchy.Tests.ps1
---

# Work Hierarchy Synchronization

## Ownership

`WorkHierarchy.psm1` owns the provider-neutral desired-state projection. It resolves canonical epic and
plan identities through `PlanState.psm1`, reads layout-dependent assets through
`Resolve-PlanAssetPath`, and emits ordered issue content and relations. It performs no network access.

`GitHubWorkHierarchy.psm1` is the only GitHub transport owner. The core sees a provider with two
handlers: `read(request)` and `write(operation)`. The GitHub provider translates those typed values to
`gh api` argument arrays; remote text remains data and is never evaluated.

## Projection Contract

- Schema: `skalary/work-hierarchy-projection@1`.
- One epic projects to one parent item. Every plan whose header carries that canonical epic ID projects
  to one child item. Archived members remain included so completed work stays visible in the hierarchy;
  later reconciliation may reflect completion without dropping canonical membership.
- Children use ordinal canonical-ID ordering. Phase and step order follows `plan.md`; requirements use
  numeric requirement order; dependencies use ordinal canonical-ID order.
- Child managed content includes the five intent sections, canonical dependencies, phases and steps,
  and requirement/acceptance pairs.
- Managed regions use
  `<!-- skalary:work-hierarchy:<epic|plan>:<local-id>:start|end -->`. Later diff/apply behavior may
  replace only the content between a matching pair.
- Dependency tokens resolve through canonical plan inventory. Unknown, ambiguous, or self dependencies
  fail projection instead of producing a guessed remote relation.
- `ConvertTo-WorkHierarchyProjectionJson` preserves the projection's ordered properties so unchanged
  local inputs produce byte-identical JSON.

## Provider Boundary

The boundary stays deliberately small until a second provider exists:

- `read(request)` obtains inert remote state.
- `write(operation)` performs one explicit mutation.

GitHub v1 supports issue reads and create/update/sub-issue-link writes through `gh api`. Azure DevOps
has no implementation, capability layer, compatibility protocol, or shared provider framework.
