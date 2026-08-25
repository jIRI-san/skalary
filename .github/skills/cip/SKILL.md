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

- Capture and confirm operator **intent** before drafting; the plan's `intent.md` is the anchor `/ci` re-reads and `/pfb` measures against.
- Reconcile against prior plans through `Get-PlanIndex.ps1`, not by reading the plan corpus.
- Resolve architecture decisions before drafting; no silent TBDs.
- Keep steps checklist-style, specific, and implementation-oriented.
- Every requirement needs machine-checkable evidence markers in acceptance criteria.
- Keep plans phase-budget aware and size-bounded.
- Run `Test-Plan.ps1` after drafting and after each DR round.
- Maintain the `<!-- cip-stage: ... -->` anchor via `Set-PlanStage.ps1` (never hand-edit it). The stage vocabulary is closed and ordered — `scaffolded` (stamped by `New-Plan.ps1`), `drafted`, `dr-round-<n>`, `done` — and any other value is rejected at write time.

## Preservation checklist (legacy Step-4 rules -> assets)

- **Specificity / concise executable steps** -> `./assets/drafting-guide.md` ("Step drafting checklist")
- **Simplest-first mandate** -> `./assets/interview-guide.md` + `./assets/drafting-guide.md`
- **Security-by-design requirements** -> `./assets/interview-guide.md`
- **Architecture lock-in** -> `./assets/interview-guide.md`
- **Cross-reference + evidence integrity** -> `./assets/drafting-guide.md` + `Test-Plan.ps1` gate

## Step 1: Load context and resolve the plan folder

1. Read `docs/design-notes/.design-notes.md` and load relevant design notes for touched subsystems.
2. **Consult the cross-plan index, never the plan corpus.** Prior requirements, risks, and decisions are read from the generated index — reading the plans themselves does not scale with the archive and misses archived ones:

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/Get-PlanIndex.ps1 -RepoRoot . -Filter "<topic regex>"
   ```

   It covers active **and** archived plans in both layouts, and is deterministic (no timestamps, repo-relative paths). Drop `-Filter` for the whole corpus, add `-Format Json` when you need the records structured. Feed what it returns into the `prior-art` gate in `./assets/interview-guide.md`.
3. **New plan:** scaffold the folder deterministically with `New-Plan.ps1` — it generates the id, creates `<yyyy-mm-dd>-<6hex>-<slug>/plan.md`, writes the `<!-- plan-id: <hash> -->` anchor + `# <id>: <Title>` heading, and sanitizes/path-confines the slug. Legacy `NNN-<slug>` folders keep working unchanged.

   ```powershell
   pwsh -NoProfile -File .github/skills/cip/scripts/New-Plan.ps1 -Title "<plan title>" -Slug "<slug>" -RepoRoot .
   ```
4. **Resume:** resolve the existing plan via `Resolve-Plan` (accepts a hash prefix, legacy number, slug, or date); exclude `archived/`.
5. If legacy loose plan files exist, migrate them with `.github/skills/cip/scripts/Repair-Plans.ps1` — do not hand-migrate.

## Step 2: Run interview (`./assets/interview-guide.md`)

1. Follow the full question bank and the `intent`, `no-tbd`, `evidence`, and `pre-draft` gates from the interview asset.
2. Capture operator intent **first** into the plan's intent asset (`assets/intent.md`, or the plan-folder root for legacy plans — resolve with `Resolve-PlanAssetPath`, never a hand-built path). When `/cep` already populated preliminary intent, decisions, or references, read them back as interview input, preserve their **Epic discussion provenance**, and refine them in place — never reset them to scaffold templates. The `intent` gate blocks drafting until intent carries no `TBD` and the operator has confirmed it read back.
3. Do not allow unresolved architecture or evidence-less requirements.
4. Confirm interview summary with the user before drafting.

## Step 3: Draft plan (`./assets/drafting-guide.md` + template)

1. Build/update the plan in-repo using `./assets/plan-template.md`.
2. Follow the drafting checklist in `./assets/drafting-guide.md` (typed evidence legend, phase-budget points, concise steps, decisions extraction, size limits).
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
- **No silent TBDs:** unresolved architecture or evidence-less requirements block drafting; surface them to the user.
