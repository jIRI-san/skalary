---
name: autopilot
description: Autonomous execution mode orchestration for /ci
user-invocable: false
disable-model-invocation: true
---

# Autopilot (Autonomous Execution)

## Overview

This skill is read by `/ci` after the user selects an autonomous runtime and execution extent. It
handles first-run `.autopilot.json` bootstrap and launches the already-selected runtime/mode through
`.github/skills/autopilot/scripts/launch.ps1`.

The launcher is the sole reader of `.autopilot.host.json`. The skill and the autopilot agent never read, create, or modify `.autopilot.host.json` or `.autopilot.host.json.example`.

## When invoked by /ci

1. Confirm plan slug from `/ci` context.
2. Accept the runtime and launcher mode selected by `/ci`; do not ask for either again.
3. Run first-run config bootstrap (next section).
4. For container or sandbox, ask only for the starting branch.
5. Run the launcher command for the selected runtime and mode.
6. Preserve the launcher exit status. Report completion only for `0`, an actionable operator stop for
   `42`, an exhausted rebundle for `43`, and the exact failure for every other nonzero status.

## First-run config bootstrap

1. Check repo root for `.autopilot.json`.
2. If file exists, continue.
3. If file is missing:
  - Set `runtime` from the value already selected in `/ci`; do not interview for it again.
  - Interview for: `copilotAuth`, `gitProvider`, `gitAuth`, `model`, `context`, `reasoningEffort`, `git.name`, `git.email`, `timeout`, `maxIterationsPerStep`, `build`, `test`.
   - Optionally interview for `offlinePackages` when the plan targets the container/sandbox runtime and restores from a private package stream.
   - Start from `.github/skills/autopilot/.autopilot.json.example`.
   - Write `.autopilot.json` at repo root.
4. Structurally validate `.autopilot.json` (no JSON-Schema validation):
  - Required fields exist: `runtime`, `copilotAuth`, `gitProvider`, `gitAuth`, `model`, `context`, `reasoningEffort`, `git`, `timeout`, `maxIterationsPerStep`, `build`, `test`.
   - Types: string fields are strings; `timeout` and `maxIterationsPerStep` are numbers; `git` is an object with string `name` and `email`.
   - If `offlinePackages` is present: it is an object with boolean `enabled`; optional `ecosystems` is an array of `dotnet`/`npm`; optional `maxRebundles` is a number ≥ 1.
5. If validation fails, stop with a loud actionable error. Do not invoke launcher.

## Runtime handoff

`/ci` is the sole owner of runtime and execution-extent selection. This skill receives:

- runtime: `host`, `container`, or `sandbox`
- launcher mode: `next-phase` or `whole-plan`

Refuse any other value. Do not derive launcher mode from plan text: `Mode` is operator-selected before
handoff, so it remains authoritative when container or sandbox starts from another branch.

An existing `.autopilot.json.runtime` is the default for direct launcher use, not a second decision for
the current `/ci` handoff; the explicit `-Runtime` value remains authoritative and should be surfaced
when it differs. Validate a repository-derived branch against the launcher's restricted ref grammar,
then invoke `launch.ps1` through a PowerShell argument splat or `ProcessStartInfo.ArgumentList`. Never
construct a shell command string from the branch.

For container and sandbox only, ask:

**Start from which branch? (Current / main)**

- Current branch: pass `-Branch <current-branch>`
- main: pass `-Branch main`

Host mode does not ask branch follow-up.

## Custom host command

Host mode may use `.autopilot.host.json`, but only the launcher reads it.

Security warning:

- Host command runs headlessly with no approval prompt.
- Only point `command` to a trusted binary.
- Invalid host config fails loud before phase execution.
- If host config file is absent, launcher defaults to `copilot`.
- This file is host-only; container and sandbox never read it.

## Offline package bundling

When `offlinePackages.enabled` is true and the runtime is container/sandbox, the host pre-builds a package feed (`prepare-packages.ps1`) and mounts it read-only; the runtime copies it to a writable cache and restores offline. Host mode ignores `offlinePackages` (warn-and-ignore).

Exit-code round-trip (distinct from the `42` @human stop):

- **Exit 43 — offline rebundle request.** The sealed runtime hit a package not in the feed. The agent commits the **manifest only** (never the lockfile), pushes the work branch, and exits `43`.
- The **host owns the loop**: on `43`, `launch.ps1` calls `prepare-packages.ps1 -Branch <work-branch>` (regenerate + commit + push the lockfile), then relaunches the same runtime — the re-prep completes before the relaunch clones. Capped by `maxRebundles` (default 3); on cap it surfaces the failure.
- **Exit 42 — @human stop.** Unchanged; halts for human review, no rebundle.
- **Exit 3 — invalid runtime close state.** Canonical admission, checklist, or receipt validation failed; adapters preserve recoverable work and stop instead of advancing.

## Launcher invocations

`next-phase` still delegates admission, implementation, and phase-close checks to the same autopilot
agent. The launcher stops only after that one phase succeeds; a later invocation resumes from the
existing checklist without another checkpoint format.

`whole-plan` uses the same admitted-phase and phase-close loop but continues to the next incomplete
phase after each successful gate. Operator and evidence stops end the run without discarding completed
checklist progress, so a later whole-plan launch resumes rather than repeating closed work.

Use the installed launcher path and the delivered signature:

- Host:
  - `.github/skills/autopilot/scripts/launch.ps1 -PlanSlug <slug> -Mode <launcher-mode> -Runtime host`
- Container:
  - `.github/skills/autopilot/scripts/launch.ps1 -PlanSlug <slug> -Mode <launcher-mode> -Runtime container -Branch <chosen-branch>`
- Sandbox:
  - `.github/skills/autopilot/scripts/launch.ps1 -PlanSlug <slug> -Mode <launcher-mode> -Runtime sandbox -Branch <chosen-branch>`

The launcher is blocking. After it returns, report its terminal outcome and exit `/ci`; never print
success-shaped "started" wording for an interrupted or failed run.
Every runtime adapter delegates admission and close-state interpretation to the installed
`.github/skills/autopilot/scripts/Get-PhaseExecutionState.ps1` contract; adapters must not replace it
with local checkbox or receipt-existence predicates.
