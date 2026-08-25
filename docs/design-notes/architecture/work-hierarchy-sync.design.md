---
description: Deterministic local epic and plan projection plus the narrow provider boundary used by GitHub work hierarchy synchronization
globs:
  - scripts/skalary/*WorkHierarchy*
  - plugins/work-hierarchy-sync/**
  - tests/skalary/WorkHierarchy*.Tests.ps1
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
- `ConvertTo-WorkHierarchyProjectionJson` preserves the projection's ordered properties and canonicalizes
  line endings to LF so unchanged local inputs produce byte-identical JSON on every host.

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

## Confirmed Apply

`Invoke-WorkHierarchyApply` accepts the displayed dry run and its exact mapping-file digest. The
confirmation callback receives that dry run and must return exactly one Boolean. A decline performs no
reads or writes. After confirmation, apply re-reads the mapping and remote state and requires the
projection, mapping, and action digests to match before the first mutation.

Apply executes the refreshed actions in their displayed order. Successful creates and updates refresh the
mapping immediately, so a later provider failure leaves a durable successful prefix that a new dry run can
resume. A stable apply-lock sidecar serializes cooperating writers for one mapping path. Before each update,
apply re-reads the issue and verifies the exact title and full body observed by the refreshed action; this
protects managed and unmanaged edits made while earlier actions execute.

GitHub does not document conditional requests for the issue PATCH endpoint, so the immediate pre-write read
is the narrowest supported optimistic check; edits racing between that read and PATCH cannot be made atomic
by this adapter.

File-bound dry runs scan the authoritative repository issue listing for the exact managed start marker
before proposing creation. A unique existing issue requires explicit adoption, and multiple candidates are
ambiguous, so a create that outlives mapping persistence is refused rather than duplicated on retry. The
adapter scans at most 1,000 issues, returns at most two candidates, and refuses larger repositories rather
than falling back to eventually consistent search.

When remote content already equals the projection but stored baseline hashes are stale, dry run emits a
mapping-only update. Apply revalidates the issue and repairs the mapping without a provider mutation, so a
successful PATCH followed by a mapping-save failure remains recoverable.

Parent-child and blocked-by writes use the same provider boundary. After the final write, apply refreshes
all state and fails unless the result is refusal-free and contains only no-op actions; applying that returned
dry run again performs no mutations.

## Mapping File

`Read-WorkHierarchyMappingFile` and `Save-WorkHierarchyMappingFile` own one JSON mapping from canonical
local IDs to GitHub issue numbers and immutable provider IDs. Entries retain the issue kind, URL, and
last-synchronized title and managed-body hashes. Serialization sorts local IDs ordinally and is capped
at 1 MiB.

Every save supplies the digest returned by the matching read. A standalone save holds the stable,
never-unlinked `.lock` sidecar while comparing exact current bytes, writing and flushing a sibling temporary
file, rechecking the source digest, and atomically replacing the mapping. Apply holds that same lock from
its refreshed read through every remote mutation and mapping checkpoint; each mutation first revalidates
the current mapping digest under the lock. Updates revalidate again after their immediate remote
precondition read and before PATCH. Stale or concurrently edited mappings are refused. UTF-8 input may
carry a BOM, but canonical output is BOM-free.

The mapping path is either absent or a regular file. Existing directories and other non-file targets are
rejected during read, save, and the final pre-mutation apply check so a remote write cannot precede an
unpersistable mapping.

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

## Optional Real GitHub Smoke

Live GitHub access is not validation evidence. The deterministic mocked suite is the required proof and
runs without credentials. An operator may additionally smoke-test a disposable repository they own:

1. Verify the selected repository permits issues, sub-issues, and blocked-by relations, then authenticate
   the local `gh` CLI with an account authorized to create and edit those issues.
2. Import `WorkHierarchy.psm1` and `GitHubWorkHierarchy.psm1`; create the projection with
   `New-WorkHierarchyProjection`, a provider with `New-GitHubWorkHierarchyProvider`, and mapping state with
   `Read-WorkHierarchyMappingFile`. Keep the mapping at a gitignored or out-of-tree operator-owned path;
   never commit a disposable smoke mapping.
3. Pass the exact mapping and digest to `New-WorkHierarchyDryRun`, render it with
   `ConvertTo-WorkHierarchyDryRunText`, and inspect every ordered action. Do not apply a run containing a
   refusal or an unexpected target.
4. Call `Invoke-WorkHierarchyApply` only after comparing the confirmation callback's action digest with the
   rendered digest. A decline must leave the repository unchanged.
5. Read the refreshed mapping and run a second dry run. It must contain only no-op actions. Inspect the
   created hierarchy in GitHub, then remove the disposable issues and local mapping through operator-owned
   cleanup.

Never automate this smoke in CI, store a token in repository files, treat a live pass as required evidence,
or run it against production planning issues.

## Distribution

The `work-hierarchy-sync` plugin installs the interactive skill and a byte-identical module closure under
`.github/skills/work-hierarchy-sync/`. `Sync-PluginScripts.ps1` is the only writer of the bundled
`GitHubWorkHierarchy.psm1`, `WorkHierarchy.psm1`, and `PlanState.psm1` copies. The plugin manifest, registry,
marketplace catalog, and dogfood copies use the existing repository generators; no feature-specific
installer or activation path exists.

`WorkHierarchyConsumerInstall.Tests.ps1` installs only manifest-declared files into an isolated repository,
loads all three modules from that installed boundary, and runs projection plus a mocked read-only GitHub dry
run. Live credentials are never part of installed-consumer or generated-drift evidence.
