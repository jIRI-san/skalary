---
name: cep
description: 'Create Epic Plan — use when a goal is too large for one implementation plan. Interviews for epic-level intent, decomposes the goal into independently executable child plans wired by depends-on, scaffolds the epic folder and each child plan folder, and hands each child to /cip for full drafting. Invoke with /cep <goal> for a new epic or /cep <reference> to extend an existing one.'
argument-hint: 'Epic goal for a new epic (e.g. "payments rework"), or an existing epic reference (hash prefix, slug, or date)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Create Epic Plan

> **Goal:** turn one oversized goal into a set of child plans that each stand on their own, and record the order between them. Decompose here; draft each child in `/cip`.

> **Host-equivalent choices:** build one ordered option list for every predefined choice. Each option
> includes the same label and decision context in both hosts, any recommendation/default,
> `effort: <1-10>`, and `complexity: <1-10>`. In VS Code, pass that list to
> `vscode_askQuestions`; in Copilot CLI, render the same list as numbered chat options and accept the
> number or exact label. Never stop only because the VS Code picker is unavailable. Free-form
> questions are unchanged.

## non-negotiable epic summary

- An epic is an **index**, never a container: child plans stay ordinary sibling folders under `docs/implementation-plans/` so every existing consumer resolves them unchanged.
- Membership is the `<!-- epic: <id> -->` marker in the child's `plan.md`; `New-Plan.ps1 -EpicId` writes it at creation and `New-Epic.ps1` maintains it for later attachment or re-parenting. Ordering is the existing `<!-- depends-on: ... -->` marker. Never hand-edit either marker.
- Every child must be **independently executable**: it can be implemented, validated, reviewed, and merged on its own once its declared dependencies are done.
- `/cep` scaffolds, wires, and preserves the accepted decomposition context; it does **not** draft requirements, risks, evidence, or steps. Each child goes through `/cip` to confirm and refine its preliminary intent and decisions, then complete the draft.
- The epic carries goal-level intent only. A child with no intent of its own is not a plan, it is a phase in disguise.

## Step 1: Load context and resolve the epic

1. Read `docs/architecture-notes/.architecture-notes.md` when present and load touched contracts,
   then read `docs/design-notes/.design-notes.md` and load notes for the subsystems the goal touches.
2. **Consult the cross-plan index, never the plan corpus** to discover bounded active and archived
   candidates:

   ```powershell
   .github/skills/cep/scripts/Get-PlanIndex.ps1 -RepoRoot . -Filter "<topic regex>"
   ```

   After topic, epic/dependency, or operator selection narrows the candidates, follow
   `./assets/decomposition-guide.md` to load only needed artifacts through the installed fail-loud
   `Get-PlanArtifactConsumerContext.ps1` adapter.
3. **New epic:** do **not** scaffold anything yet. The `seams` gate in Step 2 can legitimately conclude the goal is one plan, not an epic; scaffolding before it passes leaves an orphan `epic.md` no script can remove. Scaffolding happens in Step 4, after the operator accepts a cut.
4. **Extend:** resolve the existing epic with `Resolve-Epic` (hash prefix, slug, or date) and read its `epic.md`. Its child table is generated, so treat the child plans' markers as the truth. Never open selected related-plan folders directly.

## Step 2: Interview at epic altitude (`./assets/decomposition-guide.md`)

Follow the epic question bank and the `epic-intent` and `seams` gates in the decomposition asset.
Capture the goal, desired outcome, success signals, non-goals, and definition of done, read them back
for confirmation, and materialize them in the epic's **Goal** section at Step 4.

Per-child implementation interviews belong to `/cip`, but accepted epic discussion must not disappear. While interviewing and decomposing, keep a preliminary context record for every proposed child: the operator discussion points that motivated it, the slice and outcome, boundaries and non-goals, dependency rationale, settled decisions, rejected alternatives, and named uncertainties. This is planning provenance, not a substitute for the later `/cip` interview.

## Step 3: Decompose into child plans (`./assets/decomposition-guide.md`)

Propose the cut, present it for confirmation, and revise until the operator accepts. Apply the independent-executability test, the vertical-slice rule, the dependency rules, and the anti-pattern list from the decomposition asset. Before scaffolding, pass the asset's `child-context` gate: every accepted child has enough recorded context to explain weeks later why it exists and what was decided. Never scaffold a cut the operator has not confirmed.

## Step 4: Materialize and review the accepted cut

Only once the cut is accepted. For a new epic, create the epic folder and `epic.md` first:

```powershell
.github/skills/cep/scripts/New-Epic.ps1 -Title "<epic title>" -Slug "<slug>" -RepoRoot .
```

Materialize the decomposition guide's complete canonical accepted-cut shape in that `epic.md`:
confirmed goal/success/done content, accepted child and mechanism tables, direct dependencies, delivery
routes, and prior-art dispositions. Do not scaffold a child yet.

Follow the guide's **Epic coherency review** contract. Write the initial verdict only through
`New-Epic.ps1 -SetCoherencyVerdict`, then run the ordinary `/dr` Freeze, fourteen-task dispatch,
Publish, and verified Summary/Full lifecycle over the exact resulting bytes. Decision-changing
findings return to the interactive operator as **keep — retain the accepted cut** (`effort: 1`,
`complexity: 1`), **simplify — remove unnecessary mechanism** (`effort: 3`, `complexity: 2`),
**split — separate overlapping ownership** (`effort: 6`, `complexity: 6`), or
**defer — leave optional work out** (`effort: 1`, `complexity: 1`). Every
accepted source change requires cut reconfirmation and a fresh review UUID. Stop on stale source,
incomplete attendance, unverified output, unresolved blockers, or the existing three-round cap. A
clean final review causes no follow-up `epic.md` write.
Commit the exact clean reviewed `epic.md` alone, with `Epic-Coherency-Review: <run-uuid>` and
`Epic-Coherency-Source: sha256:<digest>` trailers, before creating a child. The verified live review
run remains authority at this boundary; the trailers only make that accepted baseline locatable by
the later bounded Git-history check.

## Step 5: Scaffold and wire the reviewed children

Only after that clean no-write boundary, scaffold each accepted child in dependency order:

```powershell
.github/skills/cep/scripts/New-Plan.ps1 -Title "<child title>" -Slug "<child slug>" -EpicId <epic-id> -RepoRoot .
.github/skills/cep/scripts/New-Epic.ps1 -Epic <epic-id> -ChildPlan <child-ref> -DependsOn <dep-ref> -RepoRoot .
```

`New-Plan.ps1 -EpicId` creates each child directly under its final `<epic-id>-<date>-<plan-id>-<slug>` name and writes membership in the same operation; there is no temporary standalone folder or rename. `-DependsOn` takes one child per `New-Epic.ps1` invocation, so every dependency edge is stated explicitly. Re-running is safe: membership and dependency markers merge, and the epic child table is rebuilt from the markers on disk. Require that generated child/dependency mirror to equal the reviewed accepted-cut tables; a mismatch returns to cut reconfirmation and fresh ordinary design review.

Immediately after `New-Plan.ps1` creates each child, replace the scaffold-only content in these assets before moving to the next child:

- `assets/intent.md` — preliminary Goal, Desired outcome, Success signals, Non-goals, and Definition of done derived from the accepted cut and operator discussion.
- `assets/decisions.md` — every settled decomposition decision and its reason; explicitly label unresolved choices and rejected alternatives instead of dropping them.
- `assets/references.md` — epic ID, relevant prior plans/assets, the accepted-artifact provenance
  table, and a dated **Epic discussion provenance** summary of the operator's material points.

Prefix preliminary sections with `Preliminary context captured by /cep; /cip must confirm and refine it.` Do not leave a `TBD` placeholder where the epic discussion supplied an answer. Never invent missing operator intent: mark it as an unresolved question with the surrounding discussion that made it relevant. `/cip` extends these assets in place and must not reset them to templates.

## Step 6: Draft each child and finish

1. Hand each child to `/cip <child-ref>` to confirm and refine the captured preliminary context, then add requirements, risks, evidence, steps, and DR rounds. Draft dependency-free children first — their decisions constrain the ones that follow.
2. Confirm each drafted child passes:

   ```powershell
   .github/skills/cep/scripts/Test-Plan.ps1 -PlanPath <child-plan-path> -RepoRoot . -Stage Draft
   ```

3. Tell the operator: **"Run `/ci <epic-id>` — it reports epic rollup and selects the next unblocked child plan."**

## Anti-drift contract

- **Structure authority:** `New-Epic.ps1` owns epic folders, membership markers, dependency markers, and the child table. Hand-editing any of them is drift.
- **Review authority:** ordinary review-run v1 Freeze/Publish and verified readers remain authoritative; the marker-managed verdict is written only by `New-Epic.ps1`.
- **Clean boundary:** no child is scaffolded before a clean complete accepted-cut review, and a clean final review never triggers an epic write.
- **Membership authority:** the `<!-- epic: <id> -->` marker in each child plan — not `epic.md` — decides what belongs to the epic.
- **Context authority:** `/cep` owns the preliminary discussion provenance and accepted decomposition decisions in child intent, decisions, and references; `/cip` preserves, confirms, and refines them.
- **Drafting authority:** `/cip` owns child requirements, risks, evidence, and steps; `/cep` never writes those sections.
