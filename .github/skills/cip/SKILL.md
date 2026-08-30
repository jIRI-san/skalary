---
name: cip
description: 'Create Implementation Plan — use when planning a new feature, designing an implementation, starting development work, or resuming/refining an existing plan. Conducts thorough requirements gathering across all aspects (goals, constraints, API surface, error handling, testing, observability, security, performance), drafts a phased plan with step-level tracking, runs iterative design review via @dr, and saves to docs/implementation-plans/. Invoke with /cip <name> for a new plan or /cip <reference> to resume an existing one.'
argument-hint: 'Plan name for a new plan (e.g. "data persistence"), or an existing plan reference to resume (hash prefix, legacy number, slug, or date)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Create Implementation Plan

> **Goal:** produce a concrete, implementation-ready plan with explicit evidence and phase-aware structure. Resolve ambiguity during interview, not during execution.

> **Interaction rule:** Every question that offers predefined choices (e.g. plan selection, new/resume, yes/no confirmations, continue/stop) **must** use the `vscode_askQuestions` tool with `options` — never plain-text prompts. Free-form questions (e.g. interview topics, open-ended design input) can remain as regular text.

## non-negotiable planning summary

- Rephrase and confirm operator **intent**, domain/design context, and the final pre-draft summary; the plan's `intent.md` is the anchor `/ci` re-reads and `/pfb` measures against.
- Discover prior plans through `Get-PlanIndex.ps1`, then load selected artifacts only through the
  fail-loud `Get-PlanArtifactConsumerContext.ps1` adapter.
- Resolve architecture decisions before drafting; no silent TBDs.
- Keep steps checklist-style, specific, and implementation-oriented.
- Every requirement needs machine-checkable evidence markers in acceptance criteria.
- Keep plans phase-budget aware and size-bounded.
- Run `Test-Plan.ps1` after drafting and after each DR round.
- Maintain the `<!-- cip-stage: ... -->` anchor via `Set-PlanStage.ps1` (never hand-edit it). The stage vocabulary is closed and ordered — `scaffolded` (stamped by `New-Plan.ps1`), `drafted`, `dr-round-<n>`, `done` — and any other value is rejected at write time.
- In every user-facing question, summary, table, status, recommendation, or handoff, identify plans as `<canonical-id> <slug>` (for example, `863d97 evidence-receipt-truth`), never by id alone. Commands may remain id-only (for example, `/ci 863d97`).

## Preservation checklist (legacy Step-4 rules -> assets)

- **Specificity / concise executable steps** -> `./assets/drafting-guide.md` ("Step drafting checklist")
- **Simplest-first mandate** -> `./assets/interview-guide.md` + `./assets/drafting-guide.md`
- **Security-by-design requirements** -> `./assets/interview-guide.md`
- **Architecture lock-in** -> `./assets/interview-guide.md`
- **Cross-reference + evidence integrity** -> `./assets/drafting-guide.md` + `Test-Plan.ps1` gate

## Step 1: Load context and resolve the plan folder

1. Read `docs/architecture-notes/.architecture-notes.md` when present and load touched contracts,
   then read `docs/design-notes/.design-notes.md` and load relevant design notes.
2. **Consult the cross-plan index, never the plan corpus.** Use the generated index only to discover
   bounded candidates across active and archived plans:

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/Get-PlanIndex.ps1 -RepoRoot . -Filter "<topic regex>"
   ```

   It covers both layouts and is deterministic (no timestamps, repo-relative paths). Drop `-Filter`
   only for a genuinely repo-wide topic and use `-Format Json` when selecting canonical plan IDs.
   After topic, epic/dependency, or operator selection has narrowed the candidates, load only the
   artifact kinds needed for the current question:

   ```powershell
   .github/skills/cip/scripts/Get-PlanArtifactConsumerContext.ps1 -PlanId <canonical-plan-id>,<canonical-plan-id> -ArtifactKind <Intent,Design,Decisions,Reviews,Evidence,Learnings> -Relationship <relationship-per-plan>,<relationship-per-plan> -RepoRoot .
   ```

   Read and follow `./assets/plan-artifact-consumer-protocol.md`, then follow the planning-specific
   provenance contract in `./assets/interview-guide.md`.
3. **New plan:** scaffold the folder deterministically with `New-Plan.ps1` — it generates the id, creates `standalone-<yyyy-mm-dd>-<6hex>-<slug>/plan.md`, writes the `<!-- plan-id: <hash> -->` anchor + `# <id>: <Title>` heading, and sanitizes/path-confines the slug. Legacy `NNN-<slug>` folders keep working unchanged.

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/New-Plan.ps1 -Title "<plan title>" -Slug "<slug>" -RepoRoot .
   ```
4. **Resume:** resolve the existing plan via `Resolve-Plan` (accepts a hash prefix, legacy number, slug, or date); exclude `archived/`.
5. If legacy loose plan files exist, migrate them with `.github/skills/cip/scripts/Repair-Plans.ps1` — do not hand-migrate.

## Step 2: Run interview (`./assets/interview-guide.md`)

1. Follow the full question bank and the three ordered confirmation checkpoints from the interview asset, beginning with the `intent` gate.
2. **Intent checkpoint:** capture operator intent first in the layout-resolved `assets/intent.md` (or legacy root `intent.md`). Rephrase all five sections, read them back together, and revise until the operator confirms them. Preserve preliminary `/cep` wording across authored assets and preserve their **Epic discussion provenance** while refining them; never reset them to scaffold templates. `/cip` owns child requirements, risks, evidence, and steps; `/cep` never writes those sections.
3. **Domain/design checkpoint:** write the layout-resolved domain and design assets, rephrase the important boundaries and uncertainty, and revise until the operator approves the concise Mermaid-backed design. Use `./assets/design-template.md`; call stacks are optional and included only when they clarify control flow.
4. Build a provisional MVP-first vertical outline that routes every requirement through usable increments to the complete outcome. This outline is interview material, not the detailed plan.
5. **Final pre-draft checkpoint:** present the confirmed intent, approved design, decisions, uncertainty, rejected alternatives, and provisional vertical outline. Revise the affected asset and repeat the affected checkpoint on correction.
6. After all three checkpoints pass, persist the one lifecycle-owned confirmation marker without advancing the stage:

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/Set-PlanStage.ps1 -PlanFile <plan.md path> -Stage scaffolded -ConfirmPlanningContext
   ```

   On resume, pass the plan's current stage instead of `scaffolded`. The marker binds the current intent and design; either asset changing makes `Get-PlanState` report `stale` until the affected checkpoint is repeated and the marker is refreshed.
7. Do not allow unresolved architecture, placeholder context, or evidence-less requirements.

## Step 3: Draft plan (`./assets/drafting-guide.md` + template)

1. Build/update the plan in-repo using `./assets/plan-template.md`.
2. Follow the drafting checklist in `./assets/drafting-guide.md` (typed evidence legend, MVP-first vertical routing, phase-budget points, concise steps, decisions extraction, size limits).
3. Set the stage anchor with `Set-PlanStage.ps1`:

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/Set-PlanStage.ps1 -PlanFile <plan.md path> -Stage drafted
   ```
4. Run:

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/Test-Plan.ps1 -PlanPath <plan-path> -RepoRoot . -Stage Draft
   ```

## Step 4: Design review (`./assets/dr-guide.md`)

1. Run iterative DR (up to 3 rounds) using the DR asset process and evolution log.
2. After each round, set the stage with `Set-PlanStage.ps1 -PlanFile <plan.md path> -Stage dr-round-N` and re-run `Test-Plan.ps1 -Stage Draft`.

Keep this file orchestration-only: validation logic lives in `.github/skills/cip/scripts/Test-Plan.ps1` and `scripts/validate.ps1`, never as ad-hoc checks embedded in markdown instructions.

## Step 5: Finish

1. Confirm `plan.md` is saved in repo.
2. Confirm the stage anchor reflects the final stage reached.
3. Ask: **"Ready to start implementation? Use `/ci` to begin."**

## Anti-drift contract

Long runs drift; re-anchor every step instead of trusting context memory:

- **Validation authority:** `Test-Plan.ps1` / `npm run validate-plan` is the only authority on plan structure and evidence integrity. Resolve divergence by re-running it, not by reasoning from context.
- **Script-only mutation:** plan scaffolding (`New-Plan`), stage anchors (`Set-PlanStage`), and capture writes (`Add-WorkflowNote`) are script-mediated — never hand-edit those structures.
- **Confirmed context:** `Get-PlanState` must report `Context: confirmed` before drafting. A pending, stale, missing, or invalid enrolled marker blocks progress; repeat the affected checkpoint and refresh it through `Set-PlanStage -ConfirmPlanningContext`.
- **No silent TBDs:** unresolved architecture or evidence-less requirements block drafting; surface them to the user.
