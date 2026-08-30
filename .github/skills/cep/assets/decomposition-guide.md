# Epic decomposition guide

Loaded by `/cep` for Steps 2 and 3. `/cip` still owns everything inside a child plan; this asset only
covers the cut between children and the order between them.

## Gate: `epic-intent`

Drafting a cut is blocked until the epic's **Goal** section answers all five, with no `TBD` left, and the
operator has confirmed the read-back:

| Question | Why it gates the cut |
|---|---|
| What is the goal, in one sentence? | A goal that needs two sentences is usually two epics. |
| What does "delivered" look like from outside the code? | Names the seams that can ship independently. |
| What signals prove it worked? | Distinguishes child plans that carry value from ones that only carry code. |
| What is explicitly out of scope? | Stops the epic growing a child per stray idea. |
| When is the whole epic done? | Sets the rollup the operator reads once every child is complete. |

The epic captures intent at goal altitude only. Each child captures its own intent later, in `/cip`.

## Gate: `seams`

Before proposing a cut, name the seams the goal already has — the boundaries where work can stop and
still leave the repo consistent. Typical seams: a subsystem boundary, a data contract, a runtime host,
an install surface, a review surface. If no seam survives questioning, say so: the honest answer may be
that the goal is one plan, not an epic.

## Gate: `child-context`

Scaffolding is blocked until every accepted child has a preliminary context package derived from the
confirmed epic discussion. The package must be sufficient for an operator returning weeks later to
understand why the child exists without reopening chat history.

| Required context | Destination after `New-Plan.ps1` |
|---|---|
| Operator discussion points that motivated this child | `assets/references.md` under **Epic discussion provenance** |
| Slice, desired outcome, success signals, boundaries, and done bar | `assets/intent.md` |
| Dependency rationale and prior-plan relationship | `assets/references.md` |
| Settled choices and why they were chosen | `assets/decisions.md` |
| Rejected alternatives and unresolved uncertainty | `assets/decisions.md`; unresolved items are labelled, never silently converted into decisions |

The package is preliminary and `/cip` must confirm and refine it, but that is not permission to leave the
scaffold placeholders in place. If the epic discussion answered a field, preserve the answer. If it did not,
record the unresolved question plus why it matters. Never invent operator intent to make the gate pass.

## Epic question bank

1. **Scale check** — why can this not be one plan? Point at the phase count, the subsystem count, or the
   review surface, not at a feeling that it is "big".
2. **Ordering** — which parts genuinely cannot start before another finishes, and which merely feel
   sequential? Only the first kind becomes a `depends-on` edge.
3. **Shared contracts** — which interfaces do multiple children touch? A contract two children both
   define is a missing first child that defines it once.
4. **Blast radius** — can each child be reverted on its own, or does reverting one strand the others?
5. **Operator checkpoints** — where does the operator want to look at real output before the next child
   starts? Those are child boundaries, not phase boundaries.
6. **Prior art** — what candidates does `Get-PlanIndex.ps1` show for this area? After
   epic/dependency or operator selection, load only relevant artifacts through
   `Get-PlanArtifactConsumerContext.ps1`; reuse accepted decisions instead of relitigating them.

## Cross-plan artifact provenance

The index, epic membership/dependencies, and operator choices discover candidates; they do not
authorize direct plan-folder reads. Pass selected canonical plan IDs and only the needed closed
artifact kinds to `.github/skills/cep/scripts/Get-PlanArtifactConsumerContext.ps1`. First read and
follow `./assets/plan-artifact-consumer-protocol.md`.

Invoke the adapter directly; terminal auto-approval is intentionally unavailable:

```powershell
.github/skills/cep/scripts/Get-PlanArtifactConsumerContext.ps1 -PlanId <canonical-plan-id>,<canonical-plan-id> -ArtifactKind <Intent,Design,Decisions,Reviews,Evidence,Learnings> -Relationship <relationship-per-plan>,<relationship-per-plan> -RepoRoot .
```

For each child that consumes context, write the accepted result metadata to its layout-resolved
`references.md`. Maintain one de-duplicated table sorted by plan ID, artifact kind, path, then
relationship:

| Plan ID | Artifact kind | Path | Relationship |
|---|---|---|---|
| `<canonical-id>` | `<kind>` | `<repo-relative path>` | `<relationship>` |

Use the adapter's `planId`, `artifactKind`, `path`, and `relationship` fields verbatim. Do not create
a receipt or provenance sidecar. Retain these rows with the child's preliminary context until
`/cip` confirms and refines it.

## Independent-executability test

A proposed child is a plan only if **all** of these hold once its declared dependencies are complete:

- It can be implemented, validated, reviewed, and merged with nothing else in flight.
- It has its own intent, its own requirements with typed evidence, and its own risks.
- Its tests pass on its own branch — it does not rely on a sibling's un-merged code.
- Reverting it leaves the repo consistent, if not feature-complete.
- It fits the plan-level size limits (`.github/skills/cip/assets/drafting-guide.md` owns the numbers).

Fail any of these and the candidate is a phase of another plan, not a child of the epic.

## Vertical-slice rule

Cut along value, not along layers. A child that delivers a thin end-to-end slice can be executed,
reviewed, and judged on its own; a child that delivers "all the schemas" cannot be judged at all until
its siblings land, and it hides its own defects until then.

## Dependency rules

- An edge exists only for a **hard** ordering constraint — the later child cannot be implemented or
  validated without the earlier one merged.
- Edges must be acyclic. A cycle means the two children are one plan.
- Declare only direct edges; the transitive ones follow. `A -> B -> C` never needs `A -> C`.
- Prefer few edges. A cut where every child depends on every earlier one is a sequential plan wearing an
  epic's folder structure.
- Edges are written by `New-Epic.ps1 -ChildPlan <ref> -DependsOn <ref>`, one edge per invocation, and
  merge idempotently.

## Anti-patterns

| Anti-pattern | Why it fails | Do instead |
|---|---|---|
| Phase-per-plan | Children cannot be reviewed or merged apart; the epic is one plan with extra folders. | Keep it as one plan with phases. |
| Layer-per-plan (all models, then all APIs, then all UI) | No child delivers observable value; defects surface only in the last child. | Cut vertical slices. |
| Shared in-flight state | Children edit the same contract concurrently and conflict at merge. | Extract a first child that lands the contract. |
| Epic as a backlog | Unrelated goals share an id and the rollup becomes meaningless. | One epic per goal. |
| Hand-written child table | `New-Epic.ps1` regenerates it from markers; hand edits vanish on the next run. | Change membership through the script. |
| Placeholder child handoff | The accepted rationale remains only in chat and the operator cannot resume later. | Pass `child-context` and populate intent, decisions, and provenance immediately after scaffolding. |

## Cut presentation

Present the proposed cut before scaffolding anything, as one table plus the edges:

| Child | Slice it delivers | Depends on | Why it is independently executable |
|---|---|---|---|
| `<slug>` | … | — | … |

Then ask for confirmation with `vscode_askQuestions`. On rejection, revise the cut and present again;
never scaffold folders to "show" a cut.

## Epic-review extension handoff (inactive)

This is an explicitly inactive conformance shape for the later consumer, plan
`25aa23 epic-coherency-review`. It activates nothing in the current `/cep`, and it neither edits nor otherwise mutates that dependent plan.
Activation belongs to phase 2 of that plan. Plan `25aa23 epic-coherency-review` remains the owner of
the fixed epic-coherency scope, richer findings and outcomes, compact verdict, operator-resolution
and blocking behavior, and activation timing. The proportionality rubric below is inactive reviewer
criteria within that fixed scope; it is not a `/ci` check.

### Canonical accepted-cut source

At the future activation point, the sole accepted-cut design source is the existing canonical
`docs/implementation-plans/epics/<yyyy-mm-dd>-<epic-id>-<slug>/epic.md`. Do not assemble a packet
from chat, session memory, child plans, related-plan content, or excerpts. The canonical file has
exactly one each of these existing H2 sections, in this order:

| Section | Required ordered content |
|---|---|
| `## Goal` | The non-empty operator-confirmed goal; then non-empty `**Desired outcome.**`, `**Success signals.**`, `**Non-goals.**`, and `**Definition of done.**` entries, in that order. Signals and non-goals are non-empty lists. |
| `## Child plans` | Before scaffolding, the generated `_(none yet)_` row remains intact and is non-authoritative. After a clean review permits scaffolding, `New-Epic.ps1` replaces it with the generated mirror and the result must exactly match the reviewed accepted-child and direct-dependency tables. |
| `## Decomposition notes` | Exactly these H3s in order: `### Accepted children`, `### Direct dependencies`, `### Delivery routes`, and `### Prior art`. |

Before scaffolding, `### Accepted children` is the membership authority for the review source. It
contains these two fixed tables:

| Table | Columns | Ordering |
|---|---|---|
| Children | `Child`, `Slug`, `Slice`, `Done bar`, `Boundaries and non-overlap`, `Independent delivery and revert` | Canonical child id, ascending ordinal |
| Mechanisms | `Child`, `Mechanism`, `Intent anchor`, `Owner`, `Consumers`, `Demonstrated invariant`, `Prior-art disposition` | Canonical child id, then mechanism, ascending ordinal |

The Children table has one complete row per accepted child. The Mechanisms table inventories every
proposed mechanism, not only shared mechanisms or contracts; each row has exactly one owning child,
names every consuming child/plan, and records either the concrete invariant shared by at least two
named consumers or `—` for a local mechanism. `### Direct dependencies` has one row per edge,
ordered by dependent child and then prerequisite id, naming the delivered behavior that makes the
prerequisite necessary; children without an edge are explicitly marked independent.
`### Delivery routes` contains `**Usable MVP.**` followed by `**MVP to final.**`; each names an
ordered child route and the behavior delivered at every hop. `### Prior art` has one row per
considered candidate, ascending by canonical id or repository-relative path, with `reuse`, `extend`,
or `reject`, the owning child, and a concrete rationale for every rejection.

Before child scaffolding, the generated `| _(none yet)_ | | |` row is permitted only as
non-authoritative scaffold state; the review freezes it together with the authoritative accepted-cut
tables but never treats it as accepted membership. Resolve the epic through existing `Resolve-Epic`
inventory and require the canonical file and every ancestor below the physical epics root to be a
regular, non-link, non-reparse path. Before `Freeze`, fail closed when that identity check fails or
the canonical file is missing, empty or whitespace-only, not strict UTF-8, or over the existing
128 KiB per-artifact review-content limit. Also fail on a missing, duplicate, or out-of-order
required section, table, label, or entry; `TBD` or an empty required body/list/cell; duplicate child,
mechanism, edge, route entry, or prior-art candidate; an unknown child reference; a self-edge or
cycle; or conflicting child identity, membership, dependency, ownership, route, prior-art
disposition, goal, or outcome content across the three sections.

Read `epic.md` once into immutable bytes. Decode, validate, hash, and produce reviewer content from
that same snapshot. The review-run `scope` string is exactly:

`Epic accepted-cut coherency: goal-success-coverage; definition-of-done-coverage; verticality; child-independence-overlap; shared-ownership; necessary-direct-acyclic-dependencies; usable-mvp-to-final-route; prior-art-reuse`

Review the whole snapshot against exactly these eight labelled checks:

| Label | Fixed check |
|---|---|
| `goal-success-coverage` | The accepted children collectively deliver the confirmed goal and every success signal without adding an unrelated goal. |
| `definition-of-done-coverage` | The cut accounts for every whole-epic done condition, with no condition deferred outside the accepted children. |
| `verticality` | Each child is a value-bearing end-to-end slice rather than a horizontal layer or phase disguised as a plan. |
| `child-independence-overlap` | After its direct prerequisites land, each child can be implemented, validated, reviewed, merged, and reverted independently; child scopes neither omit work nor overlap ambiguously. |
| `shared-ownership` | Every shared mechanism or contract has one owning child, consumers name that owner, and siblings do not define it concurrently. |
| `necessary-direct-acyclic-dependencies` | Every edge is direct and required by delivered behavior, the graph is acyclic, and no edge exists only because work feels sequential. |
| `usable-mvp-to-final-route` | The graph contains an early usable outcome and a coherent route from it to the complete definition of done. |
| `prior-art-reuse` | Relevant prior art is reused, or its rejection has a concrete reason tied to the confirmed goal and boundaries. |

### Fixed proportionality rubric

Apply this rubric as reviewer criteria inside the eight checks above. It is not a ninth concern or
check, schema, task, authority, or persisted state. The deterministic inputs are
only the immutable canonical `epic.md` snapshot: the confirmed Goal, desired outcome, success
signals, non-goals, and definition of done; every proposed mechanism in canonical child then
authored order; each mechanism's one owner and all consumers; its demonstrated invariant; every
direct dependency and its prerequisite-delivered-behavior rationale; and the prior-art/reuse
evidence. Do not infer missing proof from names, likely future work, child plans, or reviewer
knowledge.

Classify every proposed mechanism exactly once, in this precedence:

1. **`speculative platform`** when any proof needed to justify the proposed scope is absent,
   including any required-shared proof when shared use is claimed; the semantic capability is
   duplicated across children; ownership or consumers are missing or ambiguous; the mechanism
   anticipates a hypothetical future provider, versioning, or compatibility need; infrastructure
   exists only to support other speculative machinery; or a local/minor finding manufactures a new
   schema, protocol, store, state machine, compatibility layer, provider, or dependency.
2. **`required shared contract`** only when no speculative trigger applies and confirmed intent
   requires the same concrete invariant across at least two named children/plans; deletion, reuse,
   or a child-local implementation is insufficient; exactly one owner and all consumers are named;
   and every associated dependency edge is necessary for delivered behavior.
3. **`local fix`** otherwise. Prefer deletion, reuse of accepted prior art, or the narrowest repair
   wholly owned and consumed by one child.

Compare delivered semantic capability, not mechanism names. A cross-child duplicate passes only
after consolidation to one owner with every consumer and the concrete shared invariant named.
Classification is fail-closed: absent required proof yields `speculative platform`, never an
assumption that a shared contract is required.

For every direct edge, require that the dependent cannot implement or validate its delivered slice
without behavior delivered by the prerequisite. Reject transitive, convenience, sequencing,
platform-first, and infrastructure-only edges. An edge introduced by speculative machinery is
itself speculative.

Every emitted finding states exactly one of the three classes in the existing design-review finding
prose; no new finding shape is introduced. A mechanism that passes need not produce a finding.
`Low`/minor findings and `local fix` findings cannot recommend the prohibited new infrastructure
listed above; without independent `required shared contract` proof, such a recommendation is
`speculative platform`.

Phase 2 owns `keep`/`simplify`/`split`/`defer` rendering, resolution persistence, operator return,
blocking integration, activation, and same-step synchronization of its source payload changes.
Phase 3 owns broader fixtures and final generated-drift proof. Nothing in this rubric activates
current `/cep`, adds a `/ci` check, or changes either phase boundary.

### Existing design-review path

Invoke only the ordinary design-review workflow described by the installed `dr` skill. Supply an
explicit concern filter containing all seven existing concern ids:
`security`, `correctness-reliability`, `architecture-patterns`, `performance`,
`testing-evidence`, `maintainability-consistency`, and `operability-observability`. This fixed filter
overrides size-based concern selection. Use both default design-review model roles from the existing
two-model roster, so the normal matrix freezes fourteen tasks. Invoke the corresponding existing
`dr-<concern>` agents; do not create an epic concern, topical agent, task type, concern version, or
model roster.

Create the ordinary review-run v1 input with `reviewType = design`,
`scopeAuthority.mode = design`, and exactly one path record:
`{ path: <canonical epic.md>, status: modified }`. Here `modified` is the fixed design-review
classification; it is not derived from mutable Git status.
`designSource` is `{ kind: plan, path: <the same canonical path>, digest:
sha256:<lowercase SHA-256 of the exact snapshot bytes> }`; `plan` is an existing enum value.
The engine computes `scopeAuthority.digest`. After `Freeze`, verify the frozen review type, exact
fixed eight-check scope, design mode, exact equality of the sole path+status record, source
kind/path/digest, and engine scope digest before creating Fleet descriptors.

Serialize the full decoded snapshot once through the existing
`skalary/untrusted-review-content@1` boundary and reuse that byte-identical envelope for every frozen
task. Never reread or reassemble the source for dispatch, and never add excerpts, child-plan text,
or related-plan content. The existing design-review workflow still owns review-standards resolution,
model preflight and binding, the complete review-run v1 task plan, `Freeze`, independent dispatch
through the exact frozen Fleet projection, richer result collection, manifest-last publication, and
verified `Summary` and `Full` reads. The eight labels remain in the frozen scope and reviewer
criteria; they do not enter or extend review-run schemas.

Before consuming a result or finalizing the cut, hash the current canonical `epic.md` again and
compare it with the frozen source digest. A mismatch makes the result stale: reconfirm the changed
cut and create a new ordinary review run. Do not reuse findings from the stale snapshot as authority.
This handoff adds no file, parser, schema, store, lifecycle, scheduler, or agent.

After a review-run `Freeze` succeeds, project one Fleet descriptor for every exact ordered frozen
task:

| Fleet field | Projection |
|---|---|
| `Id` | Exact frozen `taskId` |
| `Label` | Bounded one-line concern label |
| `Key` | Exact frozen `model` |
| `Selected` | `$true` |
| `OmissionReason` | Empty string |
| `DependsOn` | Empty collection |

Conserve the frozen ids, order, and count exactly and uniquely. Do not add tasks, infer omissions,
reorder tasks, or introduce dependencies.

Create `New-FleetDispatchPlan` once, call `Start-FleetDispatchRun` once, and render its `PreView`
before any reviewer call. Invoke only the already-admitted tasks in each returned wave and submit
exactly one structured outcome for every admitted task to `Step-FleetDispatchRun`. Continue stepping
until `Done`, then call `Complete-FleetDispatchRun` and render its `FinalView`. Only then continue the
unchanged review-run `Publish` and verified-reader flow.

Only an explicit structured throttle retries once, as the same frozen task. Every other unsuccessful
review outcome projects to Fleet `failed`; richer review outcomes and findings stay separate for
`Publish`. Fleet attendance is invocation-local and non-authoritative. Review-run `Freeze`,
`Publish`, persistence, and rendering remain authoritative, and provider-global concurrency is
unobserved.
