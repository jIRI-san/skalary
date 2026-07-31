---
name: ci
description: 'Continue Implementation — execute a plan from docs/implementation-plans/, track step state, implement one step at a time, validate with build/test, review with @cr, and commit progress.'
argument-hint: 'Optional plan reference (hash prefix, legacy number, slug, or date)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Continue Implementation

> This skill requires agent mode. It edits files, runs commands, and commits.

> **Interaction rule:** every multiple-choice prompt uses `vscode_askQuestions` with `options`.

## Step 1: Select plan and load context

1. Resolve the target plan via `Resolve-Plan` (accepts a hash prefix, legacy number, slug, or date); exclude `archived/`. Read the resolved `plan.md` — in the current layout it carries only the header markers, the asset index, and the phases/steps.
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

   Never read the whole `assets/` tree "for context". Legacy plans keep these files at the plan-folder root; resolve the path with `Resolve-PlanAssetPath` (in `PlanState.psm1`) rather than assuming either location.

   **Intent is the one non-optional read.** The plan's intent asset states the operator's goal, desired outcome, success signals, non-goals, and definition of done. Read it before implementing any step and re-anchor against it at every phase crosscheck — requirements say what to build, intent says what the operator is trying to achieve, and only intent can tell you a technically-green step missed the point. If the intent asset is missing, or **any** of its five sections is still a `TBD` placeholder, the plan did not clear the `/cip` `intent` gate: surface that to the user instead of guessing the intent yourself.
3. Read `docs/design-notes/.design-notes.md` and load relevant design notes for the current step.
4. If legacy loose plan files exist, migrate them deterministically with `.github/skills/ci/scripts/Repair-Plans.ps1` — do not hand-migrate.
5. Run dependency preflight as a hard gate when the selected plan declares `depends-on: <id>`:

```powershell
pwsh -NoProfile -File .github/skills/ci/scripts/Test-DependencyPlan006.ps1 -RepoRoot . -PlanPath <selected-plan-path>
```

If it exits non-zero, stop immediately.

## Step 2: Plan state and next step (always)

Surface deterministic state before any work:

```powershell
pwsh -NoProfile -File .github/skills/ci/scripts/Get-PlanState.ps1 <plan-reference> -RepoRoot .
```

`Get-PlanState` reports progress (done/total, current phase, last completed) and the next incomplete candidate step — flagged with `@human` / `[discovery]` / `blocked-by-after`. It picks the first non-`[x]` step in order and marks it `blocked-by-after` if its `[after:]` deps are unmet; it does **not** skip ahead to later unblocked work, so on a `blocked-by-after` flag resolve the dependency (or pick eligible work) yourself. Add only the judgment it cannot make:

- **Resume / reset `[~]`:** resume a `[~]` step from uncommitted changes when the tree is dirty; otherwise reset it to `[ ]` and restart it clean.
- **Mark active `[~]`:** mark the step you are about to execute as `[~]` first.
- **Honor stops:** on a `@human` or `[discovery]` flag, stop and hand off to the user — never auto-execute.

## Step 3: Determine execution mode and branch/worktree

1. **Read the plan's declared execution mode.** Parse the plan header for `<!-- execution-mode: manual | host-autopilot | container-autopilot | sandbox-autopilot -->` and `<!-- scope: step | phase | plan -->`. This marker is a *runtime* selector, not a pacing hint — `*-autopilot` means the plan is meant to run autonomously, not interactively with approvals.

2. **Always present the full mode menu.** Use `vscode_askQuestions` and list **every** mode below on every run, regardless of which configs exist. Mark the plan-declared mode as recommended. Never hide a mode because its config is missing — if the user picks an autonomous mode without config, the autopilot skill runs first-run bootstrap (Step 3.4).

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

4. **Autonomous handoff.** When the user picks Host / Container / Sandbox autopilot, read `.github/skills/autopilot/SKILL.md` by path and follow its steps: first-run `.autopilot.json` bootstrap (if config missing), then invoke the launcher for the chosen runtime. The chosen runtime pre-selects the autopilot sub-menu. After launch, print the handoff line and exit the `/ci` flow.

   - **Offline package rebundle (container/sandbox + `offlinePackages.enabled`).** The host launcher owns a rebundle loop on top of the normal `42` @human stop. If the sealed runtime needs a package missing from the feed it commits the **manifest only** and exits `43`; `launch.ps1` regenerates + pushes the lockfile (`prepare-packages.ps1 -Branch`), then relaunches the same runtime — capped by `maxRebundles`. This is host-owned; `/ci` just hands off and the loop is transparent. Exit `42` (@human) is unchanged.

5. **In-session execution (Interactive / Autopilot).** Validate or create the expected branch/worktree naming, then continue to Step 4. Autopilot skips per-step approval prompts; Interactive pauses at each step.

6. Record `<!-- worktree: <branch> -->` in the current phase when first running in that worktree.

## Step 4: Implement (`./assets/execution-guide.md`)

Before implementing a step, run the validation reconcile gate:

```powershell
npm run validate-plan
```

If it reports blocking failures, fix them before starting execution. This gate — not in-context memory — is the authority on whether the plan is internally consistent. Do not add inline validation logic in this orchestrator; all plan validation delegates to `.github/skills/ci/scripts/Test-Plan.ps1` via `npm run validate-plan` or `scripts/validate.ps1`.

Use the execution asset for the implement/build/test/code-review/commit loop.

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
