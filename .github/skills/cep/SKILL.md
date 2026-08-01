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

> **Interaction rule:** every multiple-choice prompt (epic selection, new/extend, cut confirmation) uses `vscode_askQuestions` with `options`. Free-form interview questions stay plain text.

## non-negotiable epic summary

- An epic is an **index**, never a container: child plans stay ordinary sibling folders under `docs/implementation-plans/` so every existing consumer resolves them unchanged.
- Membership is the `<!-- epic: <id> -->` marker in the child's `plan.md`; ordering is the existing `<!-- depends-on: ... -->` marker. Both are written by `New-Epic.ps1` — never hand-edited.
- Every child must be **independently executable**: it can be implemented, validated, reviewed, and merged on its own once its declared dependencies are done.
- `/cep` scaffolds and wires; it does **not** draft child plans. Each child goes through `/cip` for its own intent, requirements, risks, and evidence.
- The epic carries goal-level intent only. A child with no intent of its own is not a plan, it is a phase in disguise.

## Step 1: Load context and resolve the epic

1. Read `docs/design-notes/.design-notes.md` and load design notes for the subsystems the goal touches.
2. **Consult the cross-plan index, never the plan corpus** — prior requirements, risks, and decisions across active and archived plans:

   ```powershell
   pwsh -NoProfile -File .github/skills/cep/scripts/Get-PlanIndex.ps1 -RepoRoot . -Filter "<topic regex>"
   ```

3. **New epic:** do **not** scaffold anything yet. The `seams` gate in Step 2 can legitimately conclude the goal is one plan, not an epic; scaffolding before it passes leaves an orphan `epic.md` no script can remove. Scaffolding happens in Step 4, after the operator accepts a cut.
4. **Extend:** resolve the existing epic with `Resolve-Epic` (hash prefix, slug, or date) and read its `epic.md`. Its child table is generated, so treat the child plans' markers as the truth.

## Step 2: Interview at epic altitude (`./assets/decomposition-guide.md`)

Follow the epic question bank and the `epic-intent` and `seams` gates in the decomposition asset. Capture the goal, desired outcome, success signals, non-goals, and definition of done into the epic's **Goal** section before proposing any cut, then read it back for confirmation.

Per-child interviews belong to `/cip`, not here — asking them now produces detail that goes stale before the child is drafted.

## Step 3: Decompose into child plans (`./assets/decomposition-guide.md`)

Propose the cut, present it for confirmation, and revise until the operator accepts. Apply the independent-executability test, the vertical-slice rule, the dependency rules, and the anti-pattern list from the decomposition asset. Never scaffold a cut the operator has not confirmed.

## Step 4: Scaffold and wire the children

Only once the cut is accepted. For a new epic, create the epic folder and `epic.md` first, then write the confirmed goal into its **Goal** section:

```powershell
pwsh -NoProfile -File .github/skills/cep/scripts/New-Epic.ps1 -Title "<epic title>" -Slug "<slug>" -RepoRoot .
```

Then, for each accepted child, in dependency order:

```powershell
pwsh -NoProfile -File .github/skills/cep/scripts/New-Plan.ps1 -Title "<child title>" -Slug "<child slug>" -RepoRoot .
pwsh -NoProfile -File .github/skills/cep/scripts/New-Epic.ps1 -Epic <epic-id> -ChildPlan <child-ref> -DependsOn <dep-ref> -RepoRoot .
```

`-DependsOn` takes one child per invocation, so every dependency edge is stated explicitly. Re-running is safe: membership and dependency markers merge, and the epic child table is rebuilt from the markers on disk.

## Step 5: Draft each child and finish

1. Hand each child to `/cip <child-ref>` for its own interview, requirements, risks, evidence, and DR rounds. Draft dependency-free children first — their decisions constrain the ones that follow.
2. Confirm each drafted child passes:

   ```powershell
   pwsh -NoProfile -File .github/skills/cep/scripts/Test-Plan.ps1 -PlanPath <child-plan-path> -RepoRoot . -Stage Draft
   ```

3. Tell the operator: **"Run `/ci <epic-id>` — it reports epic rollup and selects the next unblocked child plan."**

## Anti-drift contract

- **Structure authority:** `New-Epic.ps1` owns epic folders, membership markers, dependency markers, and the child table. Hand-editing any of them is drift.
- **Membership authority:** the `<!-- epic: <id> -->` marker in each child plan — not `epic.md` — decides what belongs to the epic.
- **Drafting authority:** `/cip` owns child plan content; `/cep` never writes requirements, risks, or steps into a child.
