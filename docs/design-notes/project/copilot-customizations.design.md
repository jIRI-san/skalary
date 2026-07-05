---
description: Copilot customization setup for this repo — file inventory, design note loading strategy, and how to add new customizations. Load when working on .github/copilot-instructions.md, prompts, agents, skills, or instructions files.
globs:
  - .github/**
---

# Copilot Customizations

Customization artifacts are **workspace-local** and centered in `.github/`. The plugin eval harness is the intentional adjacent exception (`scripts/skalary/Test-Evals.ps1`, `plugins/*/evals/**`). No user-level files are created or modified.

## File Inventory

| File | Type | Purpose |
|---|---|---|
| `.github/copilot-instructions.md` | Workspace Instructions | Always-on project context; one `<instruction>` loads `.design-notes.md` as the design-note discovery layer, and a second loads the architecture-notes tier index (`.architecture-notes.md`) — the documented two-index divergence |
| `.github/prompts/design-notes.prompt.md` | Prompt (`/design-notes`) | `/design-notes init` (or `bootstrap`) scaffolds `docs/design-notes/` from the bundled templates; canonical bootstrap path |
| `.github/prompts/cdn.prompt.md` | Prompt (`/cdn`) | Creates a new design note file from a name argument; defers to `/design-notes init` when the scaffold is missing |
| `.github/prompts/udn.prompt.md` | Prompt (`/udn`) | Updates design notes from the current chat session; defers to `/design-notes init` when the scaffold is missing |
| `.github/prompts/design-notes/templates/design-notes-index.template.md` | Template asset | Generic `.design-notes.md` index copied to `docs/design-notes/.design-notes.md` by `/design-notes init` |
| `.github/prompts/design-notes/templates/design-note-writing-style.template.md` | Template asset | Writing-style guide copied to `docs/design-notes/project/design-note-writing-style.design.md` by `/design-notes init` |
| `.github/prompts/cr.prompt.md` | Prompt (`/cr`) | Code review entry point |
| `.github/prompts/dr.prompt.md` | Prompt (`/dr`) | Design review entry point |
| `.github/agents/dr.agent.md` | Agent (`dr`) | Design review orchestrator — reviews a plan using three specialist models |
| `.github/agents/dr-opus.agent.md` | Subagent (hidden) | Design reviewer (Claude Opus) — invoked by `dr` only |
| `.github/agents/dr-codex.agent.md` | Subagent (hidden) | Design reviewer (GPT Codex) — invoked by `dr` only |
| `.github/agents/dr-gemini.agent.md` | Subagent (hidden) | Design reviewer (Gemini) — invoked by `dr` only |
| `.github/agents/cr.agent.md` | Agent (`cr`) | Code review orchestrator — reviews git changes using three specialist models |
| `.github/agents/cr-opus.agent.md` | Subagent (hidden) | Code reviewer (Claude Opus) — invoked by `cr` only |
| `.github/agents/cr-codex.agent.md` | Subagent (hidden) | Code reviewer (GPT Codex) — invoked by `cr` only |
| `.github/agents/cr-gemini.agent.md` | Subagent (hidden) | Code reviewer (Gemini) — invoked by `cr` only |
| `.github/agents/autopilot.agent.md` | Agent (`autopilot`) | Autonomous plan execution — implements one phase per invocation, builds, tests, commits |
| `.github/skills/autopilot/SKILL.md` | Skill (`autopilot`, internal) | `/ci` Autonomous-mode handoff — first-run config bootstrap, Host/Container/Sandbox sub-menu, custom host command; read-by-path, not invoked. Co-ships with the autopilot scripts/schemas/devcontainer under `.github/skills/autopilot/**` |
| `.github/agents/scripts/get-diff-*.ps1` | Helper scripts | Git diff helpers used by `cr` for discovery (branch, commits, files, paths, smart default, uncommitted) |
| `.github/skills/cip/SKILL.md` | Skill (`/cip`) | Create Implementation Plan — requirements interview, phased plan with step tracking, iterative `dr` review, saves to `docs/implementation-plans/` |
| `.github/skills/ci/SKILL.md` | Skill (`/ci`) | Continue Implementation — executes a plan step-by-step, manages git worktrees, build/test iteration, `cr` review, explicit commit gate |
| `.github/skills/architecture-notes/SKILL.md` | Skill (`architecture-notes`) | Interface-contract tier authoring — create/update/promote/review contracts, seed/harvest, human doc, ADR harvest; `/can` + `/uan` are thin wrappers |
| `.github/prompts/{can,uan}.prompt.md` | Prompts (`/can`, `/uan`) | Thin wrappers deferring to the architecture-notes skill (create / update; `/uan` also runs finalization ADR harvest) |
| `.github/skills/architecture-tests/SKILL.md` + scripts | Skill (`architecture-tests`) + runner | Freshness-bound receipts, taxonomy × maturity gate, human-only lock gate, adapters/providers; see [architecture-tests.design.md](../architecture/architecture-tests.design.md) |
| `scripts/skalary/Test-Evals.ps1` + `plugins/*/evals/**` | Eval harness | Two-tier plugin eval runner (`npm run eval`) for structural + opt-in LLM evals |

## Design Note Loading Strategy

`copilot-instructions.md` contains a **single** `<instruction>` entry pointing to `docs/design-notes/.design-notes.md`. That root file is the discovery layer — it lists all available design notes with their scopes. The agent reads the index first, then loads relevant design notes based on the task.

This approach:
- Keeps `copilot-instructions.md` stable when design notes are added or renamed
- Eliminates duplication between the instructions file and the index
- Makes `.design-notes.md` the single source of truth for what context to load

**Two-index divergence (intentional).** `copilot-instructions.md` also loads a **second** always-on index, `docs/architecture-notes/.architecture-notes.md` — the interface-level contract + active-ADR tier that sits **above** design notes (see [architecture-notes.design.md](../architecture/architecture-notes.design.md)). This is a deliberate divergence from the single-index rule above: always-on architecture context materially improves reasoning over complex codebases, and the per-run token cost is an accepted tradeoff (bounded by the terse arch-note format + ADR lifecycle retirement, not by note count). The divergence is owned here rather than left as silent drift. The arch tier is scaffolded on demand; its instruction is a no-op until the tier exists.

## Adding a New Customization

**New design note** — use `/cdn <name>` or follow the steps in `docs/design-notes/.design-notes.md`. No change to `copilot-instructions.md` required.

**New prompt** — create `.github/prompts/<name>.prompt.md` with YAML frontmatter (`name`, `description`, `agent: agent`). The `agent` key selects which agent runs the prompt; use `agent: agent` for the default agent, or a custom agent name (e.g. `agent: cr`) to route the prompt to it.

**New skill** — create `.github/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `user-invocable`, `disable-model-invocation`). Add bundled assets under `assets/`. Use skills for multi-step workflows; use prompts for single focused tasks.

**New agent** — create `.github/agents/<name>.agent.md` with YAML frontmatter and tool/model restrictions as needed.

**New instruction file** — create `.github/instructions/<name>.instructions.md` with `applyTo` glob patterns. Use specific path globs; avoid `applyTo: "**"`.

## Review Agents (dr / cr)

Both `dr` and `cr` use an orchestrator + three specialist subagent pattern. The orchestrator handles discovery, context loading, batching, injection guarding, and synthesis. The subagents are stateless reviewers that know nothing about the orchestration.

**Model assignments:**

| Role | Emphasis |
|---|---|
| `*-opus` | Architecture, patterns, design consistency |
| `*-codex` | Logic correctness, error handling, edge cases |
| `*-gemini` | Security (OWASP), performance, resource management |

All three subagents perform a **comprehensive review** across every important dimension — correctness, security, performance, consistency, dead/commented-out code, duplication (flagged when the same logic appears 3+ times), code style, and adherence to project patterns. The emphasis column above reflects where each model tends to shine, not a hard boundary.

> The concrete model identifier lives in the `model:` field of each `*.agent.md` file. If an identifier doesn't match your Copilot subscription, update it there. Format: `"Model Name (copilot)"`.
>
> This qualified `Model Name (vendor)` format applies to **VS Code-hosted agents** (dr/cr and their subagents). The `autopilot` agent runs under **Copilot CLI**, which expects a bare model slug instead (e.g. `gpt-5.3-codex`) — see [autopilot-execution.design.md](../architecture/autopilot-execution.design.md). Do not normalize the two to a single format.

**Batching threshold:** > 15 changed files triggers batch mode for `cr`; > 200 lines triggers batch mode for `dr`. Batches are split by subsystem (mapped from design note globs) to keep related files together and avoid false findings from split context.

**Architecture-notes-aware context loading.** Both orchestrators and all six specialists load `docs/architecture-notes/.architecture-notes.md` (when it exists) and the relevant contracts **before** design notes — contracts are interface-level and rank above implementation-level notes, so a plan/change that violates a `locked` contract is an architectural finding.

**Severity consensus rule:** if all three models independently flag the same issue, severity is elevated one level.

**Prompt injection guardrails:** all reviewed content (plan text, diffs) is wrapped in `<<<UNTRUSTED_INPUT_START>>>` / `<<<UNTRUSTED_INPUT_END>>>` markers with quad-tick fencing before being passed to any subagent. Subagents are explicitly instructed to treat content inside those markers as data only and to flag directive-looking content as a Critical finding.

**Git operations:** always use terminal `execute` commands — never MCP git tools.

## Implementation Workflow Skills (cip / ci)

`cip` and `ci` are workspace **skills** (`SKILL.md` under `.github/skills/`) — multi-step workflows invocable via `/cip` and `/ci`. Both have `disable-model-invocation: true` so they only load when explicitly called. Both are deliberately slim: deterministic mechanics live in the PowerShell **state-script layer** (below), and the `SKILL.md` files keep only the judgment the agent must own. Each `SKILL.md` carries an **anti-drift contract** naming the `/ci` Step-5 `validate-plan` reconcile gate as the single source of truth for plan state.

**Deterministic state-script layer** (`scripts/skalary/`, dogfood-mirrored, npm-aliased):
- `PlanState.psm1` — shared module: `Get-PlanMetadata` (explicit `-RepoRoot`), `Resolve-Plan` (resolves a plan by 6-hex id / ≥4-char hash prefix / legacy number / slug / date → canonical id), `New-PlanId` (6 crypto-random hex with active+archived collision scan), `Get-PlanProgress`, `Get-NextStep`, `Get-PlanHeaderMarkers`.
- `Get-PlanState.ps1` (`npm run plan-state`) — text/`-Json` snapshot composing resolve + progress + next-step + flags (`@human`/`[discovery]`/blocked/uncommitted). Replaces the hand-walked "find next step" prose in `ci`.
- `New-Plan.ps1` (`npm run new-plan`) — scaffolds `<yyyy-mm-dd>-<6hex>-<slug>/plan.md` from `plan-template.md`, injecting the `<!-- plan-id: <6hex> -->` anchor (idempotently) with slug sanitization + path confinement.
- `Set-PlanStage.ps1` — idempotent `<!-- cip-stage: ... -->` writer (DR rounds, etc.).
- `Add-WorkflowNote.ps1` — typed capture writer (`-Kind` CrLog/Learnings/Capture → `cr-log.md`/`learnings.md`/`capture.md`); emits schema tokens from typed params, sanitizes only the free-text body, owns init/append + the `No entries for this phase.` placeholder fail-loud contract. The 10-entry fold-to-overflow cap is Learnings-only (`CrLog`/`Capture` uncapped).
- `Build-EvidenceReceipt.ps1` — formats verifier output into the shared golden `✓/✗ REQ-N — evidence — result — commit` grammar (full HEAD SHA, `✗`/unrun preserved).
- `Repair-Plans.ps1` — on-demand legacy loose-file migration (`-WhatIf`, idempotent, preserves `depends-on`/worktree/`plan-id`).

**Script distribution:** `scripts/skalary/` is the single source of truth and a dogfood/dev convenience (npm aliases run it in-repo), but installed skills cannot rely on it being present in a foreign repo. `Sync-PluginScripts.ps1` bundles each script a `ci`/`cip` skill invokes (plus its `PlanState.psm1`/`PlanEvidence.psm1` module closure) into that plugin's payload, so install copies them under `.github/skills/<skill>/scripts/` and the skills reference that installed path. Duplication across plugins is intentional (independent install + versioning); a shared script edit therefore patch-bumps every bundling plugin's version automatically when `Sync-PluginScripts.ps1` re-copies the bundle, and a stale bundle fails the `-WhatIf` drift gate in `scripts/validate.ps1`. (The autopilot agent still invokes these scripts from the repo-root `scripts/skalary/` path — it runs inside a checked-out repo — and bundling it is a tracked follow-up.) See plugin-registry.design.md → Skill Script Bundling.

**Plan naming + identity:** plans live in `docs/implementation-plans/<yyyy-mm-dd>-<6hex>-<slug>/`. The `<!-- plan-id: <6hex> -->` anchor is the canonical handle — date, slug, and hash-prefix all resolve to it via `Resolve-Plan`, so collisions on the old `NNN` counter are gone. Legacy `NNN-<slug>` folders still resolve (dual-format) everywhere.

**`cip` flow:**
1. Load all relevant design notes.
2. `New-Plan.ps1` scaffolds the plan folder + `plan-id` anchor and writes `plan.md` to the repo immediately (as soon as the slug is known) so all later passes operate on the in-repo file — avoids VS Code access-control approvals for temporary files.
3. Thorough requirements interview across all dimensions (goals, API surface, error handling, testing, observability, security, performance, migration), refining the repo `plan.md` in place.
4. Draft plan: Decisions log + Requirements table + Risks table + Phases with `[ ]`/`[x]`/`[~]` step markers.
5. Keep the in-repo `plan.md` updated each iteration; plan mode hands off to agent mode early to persist (never plan-only-in-session-memory). `Set-PlanStage.ps1` records the stage anchor.
6. Iterative `@dr` review (max 3 rounds) against the in-repo plan file; notable/recurring findings captured via `Add-WorkflowNote -Kind Capture` → `capture.md`.

**`ci` flow:**
1. Resolve plan via `Resolve-Plan` (date/slug/hash); load relevant design notes.
2. `Get-PlanState.ps1` yields the progress snapshot **and** the next incomplete candidate step with `@human`/`[discovery]`/blocked-by-after/uncommitted flags — collapsing the former hand-walked "read plan / find next step" steps. It returns the first non-`[x]` step in order (flagged if its `[after:]` deps are unmet); it does not skip ahead to later unblocked work. The agent still owns resume/reset of `[~]`, `@human` stops, `[discovery]` judgment, and resolving a blocked-by-after candidate.
3. Choose execution mode (Approve / Autopilot / Autonomous) — Autonomous reads `.github/skills/autopilot/SKILL.md` by path for the Host/Container/Sandbox sub-menu + first-run config bootstrap (`AUTOPILOT_CONTAINER=true` suppresses Autonomous).
4. Branch detection: on main/master → create git worktree + open new VS Code window (`code <path>`); on feature branch → continue. Branch recorded as `<!-- worktree: <branch-name> -->` in the plan file.
5. One step at a time: mark `[~]` → implement → build+test → validate acceptance criteria → `@cr` review → explicit commit gate.
6. Commit: `feat(<scope>): <step title> [plan-<plan-id> step X.Y]` (canonical id, dual-format); plan file updated in same commit.
7. On all steps `[x]`: plan-level crosscheck (receipt via `Build-EvidenceReceipt`) → mark plan `[DONE]` in title → move folder to `docs/implementation-plans/archived/`.
8. Validation is script-only: orchestrators delegate to `npm run validate-plan` / `scripts/skalary/Test-Plan.ps1` / `scripts/validate.ps1` and never embed ad-hoc validation logic.
9. `cr` smart default scope is changed files including committed branch deltas plus uncommitted changes.
10. Workflow-memory loop from plan 007 is active: mid-run findings/lessons are captured via `Add-WorkflowNote` to per-plan `cr-log.md` / `learnings.md` / `capture.md`, initialized each phase with explicit empty-state placeholders.
11. Pre-review `ledger-consult` is part of drafting/crosscheck guidance; readers load only relevant files from `docs/review-ledger/` and exclude `.archive/`.
12. Harvest guidance in `/ci` is a marked mirror of canonical `autopilot.agent.md` finalization behavior (append phase always first, prune + `/udn` only on escalation branch); the harvest distillation source is `capture.md`.

**Plan file format** (designed to be scannable by a human reviewer — no prose implementation instructions):
```markdown
# <plan-id>: Plan Title
<!-- plan-id: <6hex> -->

## Decisions
- Key decision made during planning

## Requirements
| ID | Requirement | Acceptance Criteria | Phases/Steps |

## Phase 1: Name
<!-- worktree: <branch-name> -->
- [ ] 1.1 Step title (REQ-1)
- [~] 1.2 Step title (in progress)
- [x] 1.3 Step title (done)
```

See [autopilot-skill.design.md](../architecture/autopilot-skill.design.md) for the autopilot skill (`/ci` Autonomous handoff, first-run bootstrap, custom host command) and [autopilot-execution.design.md](../architecture/autopilot-execution.design.md) for the host/container/sandbox execution infrastructure that backs the `ci` skill's autopilot modes.

## Design-Notes Bootstrap (`design-notes` plugin)

The `design-notes` plugin ships three prompts — `/design-notes` (init/bootstrap), `/cdn`, `/udn` — plus two template assets installed under `.github/prompts/design-notes/templates/` (the former standalone `create-design-notes` / `update-design-notes` plugins were consolidated into it).

Because the installer is hard-confined to `.github/` (it cannot write to `docs/`), the `docs/design-notes/` scaffold is created **on demand by `/design-notes init`**, not at install time. `/design-notes init` (alias `bootstrap`) checks whether `docs/design-notes/.design-notes.md` exists; if missing, it creates `docs/design-notes/` + `docs/design-notes/project/` and copies the two bundled templates (index → `.design-notes.md`, writing-style → `project/design-note-writing-style.design.md`), never overwriting existing files. `/cdn` and `/udn` carry a Step 0 that defers to `/design-notes init` when the scaffold is absent, so `/design-notes init` is the single canonical bootstrap path. In a repo that already has design notes (like this one), all of these are no-ops.

The writing-style template mirrors this repo's `docs/design-notes/project/design-note-writing-style.design.md`; keep them in sync when the canonical guide changes.

## Plugin Eval Workflow

Plugin payload checks are run with `npm run eval`, which calls `scripts/skalary/Test-Evals.ps1`. Structural checks always run; LLM checks require `-IncludeLlm` and are intentionally out of the CI gate (`npm test`/`validate.ps1`).

Tier-2 (`-IncludeLlm`) reads a gitignored `.eval.config.json`. On the first run, a missing config is **bootstrapped** from the committed `.eval.config.json.example`; the scaffolded copy keeps the `<slug>` placeholder, so that run skips (stays green) with a note to fill in `judgeModel` (and optional `credentialTarget`) and re-run. Auth follows the autopilot pattern: set `credentialTarget` to a Windows Credential Manager target holding a dedicated eval PAT (e.g. `copilot-eval`, kept separate from `copilot-autopilot`), or leave it unset to use ambient `copilot` auth. Missing config/auth/credential is always a skip, never a failure.

Each run writes a timestamped folder under `tests/evals/output/<yyyy-MM-dd_HH-mm-ss>/` (gitignored) holding `report.json`, a human-readable `report.md`, and any Tier-2 transcripts. Override the parent with `-OutputRoot`.
