---
description: The internal autopilot SKILL.md — /ci Autonomous-mode handoff, first-run .autopilot.json bootstrap, mode sub-menu, and the launcher contract. Load when editing the autopilot skill, the /ci execution-mode menu, or the custom host-command flow.
globs:
  - plugins/autopilot/skills/**
  - plugins/continue-implementation/skills/**
  - .autopilot.json
  - .autopilot.host.json
---

# Autopilot Skill

The `autopilot` plugin ships two same-named customizations distinguished by type: the **agent** (`agents/autopilot.agent.md`, the per-phase executor invoked by `launch.ps1`) and the **skill** (`skills/autopilot/SKILL.md`, the in-editor mode-selection + bootstrap entry point). They never collide because VS Code keys customizations by type.

## Architecture

| Concern | Owner | Notes |
|---|---|---|
| Runtime and execution-extent selection | `/ci` | Presents the runtime menu, then explicit One phase / Whole plan |
| Autonomous handoff | skill | Accepts the selected runtime/mode; asks only for container/sandbox start branch |
| First-run `.autopilot.json` bootstrap | skill | Uses handed-off runtime, interviews remaining config, writes and validates |
| Per-phase code execution | agent | Loaded by Copilot CLI inside the launcher loop; owns the per-step Designer + Validator -> Implementor -> Judge fleet after environment admission |
| Headless launch + dispatch | `launch.ps1` | Validates config, dispatches to mode orchestrator |
| Epic child launch | `Invoke-EpicAutopilot.ps1` | Delivered but not yet routed from `/ci`; atomically selects/resumes and launches one child, then stops at its raw launcher result |
| `.autopilot.host.json` read | `launch-host.ps1` only | Sole reader — neither skill nor agent touches it |

## Key Patterns

**Read-by-path, not skill-invocation.** The skill sets `user-invocable: false` + `disable-model-invocation: true` (no `context: fork`). `/ci` does not *invoke* it as a skill — it **reads `.github/skills/autopilot/SKILL.md` by path** and follows the steps inline. There is no `/autopilot` slash command.

**Launcher signature is reproduced verbatim** from the install path, only re-pathed:

```text
.github/skills/autopilot/scripts/launch.ps1 -PlanSlug <slug> -Mode whole-plan|next-phase -Runtime host|container|sandbox [-Branch <branch>]
```

Container and Sandbox carry the "Start from which branch? (Current / main)" follow-up via `-Branch`.
Host uses its own `feature/<slug>` worktree and omits the follow-up. `/ci` passes an explicit,
operator-selected mode; plan `scope` is recommendation input only, and missing/invalid scope defaults
the recommendation to One phase rather than silently broadening unattended execution. Because mode is
not derived from branch content, selecting a different starting branch cannot change the approved
extent. **The plan path is not a config field** — `launch.ps1`/`launch-host.ps1` derive
`docs/implementation-plans/<PlanSlug>/plan.md` from `-PlanSlug`, so `.autopilot.json` never carries a
(stale) plan path.

Launcher-mode selection follows the one-phase autonomy contract in
[plan-workflow.design.md](plan-workflow.design.md); this skill owns only the user-facing mode
selection and invocation arguments. `next-phase` returns after one successful phase close, while
`whole-plan` repeats the same admitted-phase and close flow and advances only after the current gate
passes. Either mode preserves checklist progress when an operator or evidence stop interrupts the run.
Launcher invocation uses bound arguments, validates repository-derived branches against a restricted
ref grammar, preserves the blocking process exit status, and reports the terminal outcome rather than
success-shaped "started" wording. Container target selection and zero-exit close probing also read the
durable `plan-finalization` review gate: Wrap/operator-decision stops at exit 42 without launching or
same-session-resuming the agent, while an explicit pre-existing Reopen makes the gate `allow`. A
`close-pending` handoff remains valid for unfinished validation/archive work but carries no operator
authority.

**Epic child launch is staged, not wired into `/ci`.** The installed
`.github/skills/autopilot/scripts/Invoke-EpicAutopilot.ps1` helper atomically selects or resumes the
exact `NextChild`, transitions `selected` to `running`, then invokes the installed per-plan launcher
once in a separate PowerShell process. Its launcher arguments are fixed to the selected folder,
`whole-plan`, `container`, the normalized caller target branch, and the admitted target commit as
`-ExpectedStartCommit` plus the persisted run id; the epic wrapper exposes no mode/runtime override.
Selection requires clean HEAD at the resolved target. The first container fetches that target once,
creates directly from its verified object, and rejects an existing work branch; only a later exit-43
retry inside that launcher invocation may resume the branch. A repeated host call uses the run-derived
container name to refuse active work or reconcile proven inactive work to `invocation-failed` without
relaunch. Persisted/replayed launcher codes use the portable 0..255 process-exit domain; launch failures
return structured `invocation-failed` receipts. The skill names the installed helper so
plugin bundling carries its canonical
`Get-PlanState`, `EpicAutopilot`, and `AtomicStore` closure, while retaining the ordinary plan
handoff until merge-gate and repeat behavior lands.

**First-run bootstrap is in-editor only.** The skill checks for repo-root `.autopilot.json`; if absent
it takes `runtime` from `/ci`, interviews for the remaining auth/build/test/model/context/effort/timeout
fields, writes from `.autopilot.json.example`, then **structurally validates** required fields/types —
mirroring `launch.ps1`'s hand-rolled checks. Existing `runtime` is the direct-launch default; an explicit
`-Runtime` remains the current invocation authority and any mismatch is surfaced. PowerShell 7.6+ can
validate draft 2020-12 through `Test-Json -SchemaFile`, but autopilot deliberately retains its
hand-rolled config checks because the launcher supports PowerShell 7.0 and must fail consistently before
dispatch on every supported host. Headless `launch.ps1` never interviews; it fails loud if the file is
missing.

**Offline package bundling.** For container/sandbox plans that restore from a private package stream, the bootstrap may also interview for `offlinePackages` (boolean `enabled`; optional `ecosystems` array of `dotnet`/`npm`; optional `maxRebundles` ≥ 1). When enabled, the launcher pre-builds a feed and the host owns a rebundle loop: the sealed runtime exits `43` on a missing package (manifest-only commit), the launcher regenerates + pushes the lockfile and relaunches, capped by `maxRebundles`. This is host-owned and transparent to `/ci`, which just hands off. Mechanics live in [autopilot-execution.design.md](autopilot-execution.design.md); the `42` @human stop is unchanged.

## Design Decisions

**Skill ships in `autopilot`, not `ci`.** It co-locates with the scripts it drives (reverses an earlier `ci`-ownership decision). `ci` keeps its existing `autopilot` dependency. This makes `autopilot` a single self-contained plugin — agent + skill + scripts + schemas + devcontainer + config templates all install under `.github/skills/autopilot/**` (agent stays at `.github/agents/`).

**`/ci` owns autonomous selection.** Its menu exposes Host / Container / Sandbox directly, then asks
One phase / Whole plan. The autopilot skill owns bootstrap and invocation only, preventing duplicate
runtime prompts. `AUTOPILOT_CONTAINER=true` suppresses all autonomous choices in `/ci` because execution
is already inside an autonomous container.

**Static Host label.** `/ci` shows a fixed "Host autopilot" label, and neither workflow skill reads
`.autopilot.host.json` — preserving the "launcher is sole reader" invariant and the agent/skill no-read
rule (agent Absolute Rule #10).

## Custom Host Command

`launch-host.ps1` may run a custom Copilot CLI executable (e.g. a corporate wrapper injecting MCP servers) instead of vanilla `copilot`. Configured via operator-provisioned, gitignored `.autopilot.host.json` at the repo root, validated by `schemas/autopilot.host.schema.json` (draft 2020-12). `Resolve-HostCommand` (in `host-command.ps1`, dot-sourced by `launch-host.ps1` only) reads it once, resolves `command` to an absolute path, classifies type (`exe`/`bat`/`cmd`/`ps1` by extension), and returns `@{ Path; Type; ExtraArgs }`.

Security layers (defense in depth — the host launcher runs **headlessly with no approval prompt**):

| Layer | Control |
|---|---|
| Default | Absent config → `copilot`, type classified by the resolved shim's extension (npm shims are `*.cmd`), no extra args |
| Fail-loud | Present-but-invalid (malformed JSON, empty `command`, shell metachar) → throw before any phase starts; never silent-fallback |
| No-shell | Direct-`.exe` branch uses `ProcessStartInfo.ArgumentList`; `.bat`/`.cmd`→`cmd.exe /c` and `.ps1`→`powershell.exe -File` use denylist-backed per-token quoting |
| Operator toggle | `AUTOPILOT_DISABLE_HOST=true` → skill omits Host **and** `launch.ps1` refuses `-Runtime host` |
| Trust model | Host = trusted env; gitignore keeps the file host-local and out of PRs/clones; agent/skill forbidden to read or write it |

The residual local-persistence risk (an untrusted build/test script planting `.autopilot.host.json` for the next headless launch) is **accepted and documented** — see RISK-5 in the plan and the schema `description`.
