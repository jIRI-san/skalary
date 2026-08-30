---
name: ci
description: 'Continue Implementation — execute a plan from docs/implementation-plans/, track step state, implement one step at a time, validate with build/test, review with @cr, and commit progress.'
argument-hint: 'Optional plan reference (hash prefix, legacy number, slug, or date)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Continue Implementation

Requires agent mode. Edits files, runs commands, and commits. Use `vscode_askQuestions`
with `options` for every multiple-choice prompt. In user-facing text, identify plans and epics
as `<canonical-id> <slug>`; commands may use only the id.

## Step 1: Select plan and load context

1. Resolve a non-archived plan by hash prefix, legacy number, slug, or date through
   `Resolve-Plan`, then read `plan.md`. An epic id/slug is also valid: `Get-PlanState` (Step 2)
   returns its rollup and `NextChild`. Do not pick a child yourself; use that result.
   `<!-- epic: <id> -->` is membership authority, while `epic.md` is generated.
2. **Load `assets/` on demand, never wholesale.** A plan folder uses either the current `plan.md` + `assets/` layout or the legacy flat layout; `Get-PlanMetadata` resolves requirements/risks/decisions from either, so never hand-parse. Read an asset only when the current work needs it:

   | Asset | Read it when |
   |---|---|
   | `assets/intent.md` | **always** — before implementing any step, and again at phase crosscheck to re-anchor |
   | `assets/requirements.md` | validating the acceptance criteria of the step's `REQ-N` refs |
   | `assets/risks.md` | the step references a `RISK-N` |
   | `assets/decisions.md`, `assets/decisions/<topic>.md` | a trade-off call needs prior rationale |
   | `assets/references.md`, `assets/evolution-log.md` | reconciling against prior review rounds or consulted sources |
   | `assets/evidence.md` | phase/plan crosscheck and the archival gate |
   | `assets/logs/{capture,cr-log,learnings}.md` | harvest at plan completion (written only via `Add-WorkflowNote`) |

   Never load the whole tree. Resolve every current or legacy asset with
   `Resolve-PlanAssetPath`. Intent is mandatory before each step and again at phase crosscheck.
   If the intent asset is missing, or **any** of its five sections is still a `TBD` placeholder,
   stop and return the plan to `/cip` instead of guessing.
3. Read `docs/design-notes/.design-notes.md` and load relevant design notes for the current step.
4. If legacy loose plan files exist, detect them now but defer migration until the read-only phase admission in Step 2 returns `ready`. Then migrate them deterministically with `.github/skills/ci/scripts/Repair-Plans.ps1` — do not hand-migrate.
5. Run dependency preflight as a hard gate when the selected plan declares `depends-on: <id>`:

```powershell
pwsh -NoProfile -File .github/skills/ci/scripts/Test-DependencyPlan006.ps1 -RepoRoot . -PlanPath <selected-plan-path>
```

If it exits non-zero, stop immediately.

## Step 2: Plan state and next step (always)

Surface deterministic state before any work. Invoke the production state command once in JSON mode,
then render its progress, next-step, planning-context, and admission fields for the operator from that
single result:

```powershell
pwsh -NoProfile -File .github/skills/ci/scripts/Get-PlanState.ps1 <plan-or-epic-reference> -RepoRoot . -Json
```

For an epic, use its ordered, dependency-ready `NextChild`; an empty value means all children
are complete or a dependency is unresolved. Re-run state against that child. For a plan, state
reports progress and the first non-`[x]` step, including `@human`, `[discovery]`, and
`blocked-by-after`; it never silently skips blocked work. Add only this judgment:

- **Confirmed planning context:** an enrolled plan must report `Context: confirmed`. Stop before branch or file
  mutation on `pending`, `stale`, `missing`, or `invalid` and return the plan to `/cip` for the affected
  confirmation checkpoint. Marker-less legacy plans retain existing behavior.
- **Resume / reset `[~]`:** resume a `[~]` step from uncommitted changes when the tree is dirty; otherwise reset it to `[ ]` and restart it clean.
- **Mark active `[~]`:** mark the step you are about to execute as `[~]` first.
- **Honor stops:** on a `@human` or `[discovery]` flag, stop and hand off to the user — never auto-execute. For `@human`, print the step's full `Handoff:` block from `Get-PlanState` verbatim (**Steps**, **Verify**, **Rollback**), not just the step title: that block is what makes the operator round-trip single-pass. If the block is missing or incomplete, say so — the plan did not clear the `human-step-detail` gate.

### Phase admission (read-only hard gate)

Before branch/worktree creation, checklist edits, `Repair-Plans`, or workflow-log initialization,
consume the `Admission` result from the single state invocation above. The CLI builds one
`Get-PlanInventory` snapshot and delegates the complete policy to `Get-PhaseAdmission`: dependency
completion and resolution, first-incomplete-phase and `[after:]` eligibility, confirmed/legacy intent
availability, and phase requirement mapping. Do not reconstruct any part of that policy in the skill.

Admission has the closed states `ready`, `blocked`, `missing`, `ambiguous`, and `stale-input`. Report
`Admission.ApplicableRequirements` before execution. Only `ready` permits deferred repair,
branch/worktree mutation, `[~]`, or log initialization. Every other result stops with
`Admission.Reason` and leaves the plan tree byte-for-byte unchanged.

## Step 3: Determine execution mode and branch/worktree

1. **Read the plan's declared execution mode.** Parse the plan header for `<!-- execution-mode: manual | host-autopilot | container-autopilot | sandbox-autopilot -->` and `<!-- scope: step | phase | plan -->`. This marker is a *runtime* selector, not a pacing hint — `*-autopilot` means the plan is meant to run autonomously, not interactively with approvals.

2. **Always present the full mode menu.** Use `vscode_askQuestions`, list every mode below,
   and recommend the declared mode. Missing config does not hide a mode; autopilot bootstraps it.

   | Option | Kind | Description |
   |---|---|---|
   | **Interactive (approve each step)** | in-session | Pause for approval at each step. Recommended when marker is `manual` or absent. |
   | **Autopilot (autoapprove)** | in-session | Run in this session without per-step approval prompts. |
   | **Host autopilot** | autonomous | Headless via `launch.ps1 -Runtime host`. Recommended when marker is `host-autopilot`. |
   | **Container autopilot** | autonomous | Headless via `launch.ps1 -Runtime container`. Recommended when marker is `container-autopilot`. |
   | **Sandbox autopilot** | autonomous | Headless via `launch.ps1 -Runtime sandbox`. Recommended when marker is `sandbox-autopilot`. |

   Never silently downgrade an `*-autopilot` plan to interactive — always confirm with the user via this menu.

3. **Environment suppressions (security, not config gaps):**
   - `AUTOPILOT_CONTAINER=true` (already inside the autopilot container): omit all autonomous options **and** Autopilot; execute in-place per the marker.
   - `AUTOPILOT_DISABLE_HOST=true`: omit **Host autopilot** only (`launch.ps1` also refuses `-Runtime host`).

4. **Execution extent.** For Host / Container / Sandbox, ask exactly **One phase** or
   **Whole plan**. `scope: step|phase` recommends One phase; `scope: plan` recommends Whole plan.
   Missing or invalid scope never infers `whole-plan`: report it and recommend One phase. Map the
   answer to `next-phase` or `whole-plan`.

5. **Autonomous handoff.** Read `.github/skills/autopilot/SKILL.md`; pass the selected runtime and
   launcher mode without another menu. Do not create an implementation-role fleet in `/ci` on this
   path; the launched autopilot agent owns the same per-step fleet so each role is declared once.
   Block on the launcher, preserve its exit status, report its completion/operator-stop/failure
   outcome, and exit `/ci`.

   - **Offline rebundle:** container/sandbox exit `43` after committing only a missing package's
     manifest; host `launch.ps1` runs `prepare-packages.ps1 -Branch`, pushes the lockfile, and
     relaunches up to `maxRebundles`. Exit `42` remains the `@human` stop.
   - **Progression contract.** `next-phase` stops after the first admitted phase completes its phase-close flow. `whole-plan` applies the same admission and close contract to each remaining phase and advances only after the current gate passes; an operator or evidence stop leaves checklist progress intact for a later resume.

6. **In-session execution (Interactive / Autopilot).** Validate or create the expected branch/worktree naming, then continue to Step 4. Autopilot skips per-step approval prompts; Interactive pauses at each step.

7. Record `<!-- worktree: <branch> -->` in the current phase when first running in that worktree.

## Step 4: Implement (`./assets/execution-guide.md`)

Before implementing a step, run the validation reconcile gate:

```powershell
npm run validate-plan
```

If it reports blocking failures, fix them before starting execution. This gate — not in-context memory — is the authority on whether the plan is internally consistent. Do not add inline validation logic in this orchestrator; all plan validation delegates to `.github/skills/ci/scripts/Test-Plan.ps1` via `npm run validate-plan` or `scripts/validate.ps1`.

Use the execution asset for the implement/build/test/code-review/commit loop.

### Implementation-role fleet dispatch

For in-session execution, create the fleet only after phase admission, execution-mode selection,
branch/worktree setup, active-step marking, and the plan reconcile gate have succeeded. Import
`.github/skills/ci/scripts/FleetDispatch.psm1` and create one `New-FleetDispatchPlan` per active step
from these ordered descriptors:

| Id | Label | Key | DependsOn |
|---|---|---|---|
| `ci-designer` | `CI Designer` | the existing Designer role/model binding | none |
| `ci-validator` | `CI Validator` | the existing Validator role/model binding | none |
| `ci-implementor` | `CI Implementor` | the existing Implementor role/model binding | `ci-designer`, `ci-validator` |
| `ci-judge` | `CI Judge` | the existing Judge role/model binding | `ci-implementor` |

All four tasks are selected. Descriptor keys record the caller-resolved role/model bindings; the
adapter does not change role prompts, tool sets, model selection, or the execution guide. Render the
complete `Format-FleetDispatchPlan` pre-view before the first role invocation, including the
four-task admission cap, waves, ready order, retry policy, omissions, and the statement that
provider-global concurrency is unobserved. Pass that exact plan to `Invoke-FleetDispatchPlan` and
launch only its current ready wave.

Designer and Validator may run together. Implementor runs the existing file-edit, focused
build/test, formatting, design-note, and fix loop only after both complete. Judge runs only after
Implementor completes and validates the active step's acceptance criteria. Retry once only for the
explicit structured `throttled` outcome; diagnostic text and ordinary failures never trigger a
retry. A failed prerequisite cancels only its transitive dependents.

Render final attendance and write it through the existing Capture path. Commit and phase promotion
remain outside the adapter and occur only after Judge completes. Any failed or cancelled role leaves
the step `[~]` for a later run-scoped plan. The adapter adds no clone, credential, worktree,
container, promotion, review, or persistence mechanism.

## Step 5: Crosscheck and completion (`./assets/crosscheck-guide.md`)

Use the crosscheck asset for:
- Phase crosscheck
- Plan crosscheck
- Evidence receipt (`evidence.md`)
- `archival-gate` checks before completion

## Anti-drift contract

Long runs drift; re-anchor every step instead of trusting context memory:

- **State authority:** `Get-PlanState` (Step 2) is the only source of progress and next-step selection. Never trust remembered checkbox state.
- **Intent authority:** the plan's intent asset — not remembered context — is the anchor for *why* a step exists. Re-read it before each step and at every crosscheck.
- **Consistency authority:** the `npm run validate-plan` reconcile gate (Step 4) is the only authority on plan/evidence consistency — resolve any divergence by re-running it, not by reasoning from context.
- **One step at a time:** implement, validate, review, and commit exactly one step, then return to Step 2.
- **Retained judgment:** resume/reset of `[~]`, `@human` / `[discovery]` stops, and explicit-file staging stay with the orchestrator.
