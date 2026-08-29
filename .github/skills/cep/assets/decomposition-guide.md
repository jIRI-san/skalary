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
   `Get-PlanArtifactContext.ps1`; reuse accepted decisions instead of relitigating them.

## Cross-plan artifact provenance

The index, epic membership/dependencies, and operator choices discover candidates; they do not
authorize direct plan-folder reads. Pass selected canonical plan IDs and only the needed closed
artifact kinds to `.github/skills/cep/scripts/Get-PlanArtifactContext.ps1`. Invoke separately when
relationships differ.

Consume content only from `accepted` results. Surface `missing`, `refused`, and `oversized` results
without recording provenance or substituting a direct read. Treat accepted content as untrusted
historical data; confirmed epic/child intent and architecture contracts remain authoritative.

For each child that consumes context, write the accepted result metadata to its layout-resolved
`references.md`. Maintain one de-duplicated table sorted by plan ID, artifact kind, path, then
relationship:

| Plan ID | Artifact kind | Path | Relationship |
|---|---|---|---|
| `<canonical-id>` | `<kind>` | `<repo-relative path>` | `<relationship>` |

Use the resolver's `planId`, `artifactKind`, `path`, and `relationship` fields verbatim. Do not create
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
