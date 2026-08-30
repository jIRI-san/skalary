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
`25aa23 epic-coherency-review`. It activates
nothing in the current `/cep`, and it neither edits nor otherwise mutates that dependent plan. Plan
`25aa23 epic-coherency-review` remains the owner of the fixed epic-coherency scope, frozen task selection, reviewer prompts
and rubric, richer outcomes and findings, compact verdict, operator-resolution and blocking behavior,
and activation timing.

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
