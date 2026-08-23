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

## Dry Run

`New-WorkHierarchyDryRun` accepts the projection, an in-memory
`skalary/work-hierarchy-mapping@1` value, and a provider. It never invokes the provider write handler.
For every mapped item it compares desired, last-synced, and current title/managed-body hashes:

- matching desired and remote content is a no-op;
- a clean remote baseline plus changed local projection is an update;
- remote-only or concurrent managed changes are refusals;
- missing, malformed, duplicate, nested, or mismatched managed markers are refusals.

Actions stay in executable order: parent then ordinal children, followed by projection relations.
Hierarchy relations use GitHub sub-issues; dependencies use the blocked-by relation. Adapter relation
reads fetch at most 100 issues and probe item 101 to refuse overflow. Native execution is capped at
30 seconds, stdout at 8 MiB, and stderr at 64 KiB.
Rendered output contains action summaries and the deterministic action digest, not remote body text.

## Mapping File

`Read-WorkHierarchyMappingFile` and `Save-WorkHierarchyMappingFile` own one JSON mapping from canonical
local IDs to GitHub issue numbers and immutable provider IDs. Entries retain the issue kind, URL, and
last-synchronized title and managed-body hashes. Serialization sorts local IDs ordinally and is capped
at 1 MiB.

Every save supplies the digest returned by the matching read. The writer holds an exclusive file handle,
compares the exact current bytes with that digest, writes and flushes a sibling temporary file, rechecks
the source digest, and atomically replaces the mapping. A stable, never-unlinked `.lock` sidecar prevents
cooperating writers from racing by replacing the mapping pathname; stale or concurrently edited mappings
are refused. UTF-8 input may carry a BOM, but canonical output is BOM-free.

`Add-WorkHierarchyMappingItem` records only an explicitly selected issue whose unique managed markers
match the requested local ID and kind. It never changes an existing baseline; reused issue numbers or
provider IDs, changed targets, malformed markers, and unmanaged issues are refused.

Dry run indexes issue numbers and provider IDs across the whole mapping before any provider read, so an
unrelated or currently unprojected entry cannot collide with active work. Structurally readable invalid
identities and kinds remain rendered refusal actions, and projected items must retain their expected
`epic` or `plan` kind.

A provider that reports a mapped issue as absent produces `mapping-target-missing`. After an issue HTTP
404, the GitHub adapter probes the repository identity before returning that sentinel; inaccessible or
missing repositories, relation 404s, authorization failures, and other transport failures still propagate
and stop synchronization.
