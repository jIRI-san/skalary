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
| `.github/skills/design-notes/SKILL.md` | Skill (`design-notes`) | Design-notes toolkit — `init`/`bootstrap` scaffolds `docs/design-notes/` from bundled templates; `create <name>` adds a note; `update` syncs notes from the session. Dispatches by argument; the tested Tier-2 artifact |
| `.github/prompts/design-notes.prompt.md` | Prompt (`/design-notes`) | Thin shortcut over the `design-notes` skill; routes the argument to the skill's Init/Create/Update workflow |
| `.github/prompts/cdn.prompt.md` | Prompt (`/cdn`) | Thin shortcut over the `design-notes` skill's Create workflow (creates a new design note from a name argument) |
| `.github/prompts/udn.prompt.md` | Prompt (`/udn`) | Thin shortcut over the `design-notes` skill's Update workflow (updates design notes from the current chat session) |
| `.github/skills/design-notes/assets/templates/design-notes-index.template.md` | Template asset | Generic `.design-notes.md` index copied to `docs/design-notes/.design-notes.md` by the skill's Init workflow |
| `.github/skills/design-notes/assets/templates/design-note-writing-style.template.md` | Template asset | Writing-style guide copied to `docs/design-notes/project/design-note-writing-style.design.md` by the skill's Init workflow |
| `.github/prompts/cr.prompt.md` | Prompt (`/cr`) | Code review entry point |
| `.github/prompts/dr.prompt.md` | Prompt (`/dr`) | Design review entry point |
| `.github/skills/cr/SKILL.md` + `.github/skills/dr/SKILL.md` | Skills (`cr`, `dr`) | Own the review orchestration and are CLI-usable on their own; the agents are thin shims that read the skill by path and keep their `handoffs:` buttons, and the prompts are shortcuts to the skills |
| `.github/skills/{cr,dr}/assets/dispatch-guide.md` | Shared asset | Declared-model preflight, size-scaled concern selection, batching contract, and 28-invocation budget. Byte-identical across both installed copies by construction |
| `.github/skills/cr/assets/model-preferences.md` | CR policy asset | Single editable CR role mapping: primary `GPT-5.6 Sol`, secondary `Claude Opus 5`, backup `Claude Sonnet 4.6`, all at high reasoning/default context. `post-phase` selects primary only; `plan-finalization` and standalone `/cr` select primary + secondary |
| `.github/skills/cep/SKILL.md` | Skill (`cep`) | Create Epic Plan — decomposes a high-level goal into independently executable child plans wired by `<!-- epic: <id> -->` and `depends-on` |
| `.github/skills/si/SKILL.md` + `.github/prompts/si.prompt.md` | Skill (`si`) + Prompt (`/si`) | Self-improvement — harvests the review ledger, `learnings.md`, and queued `/pfb` feedback into proposed edits to this repo's own skills/agents, behind `Test-SiWriteScope.ps1` and a draft PR. See [self-improvement.design.md](../architecture/self-improvement.design.md) |
| `.github/agents/dr.agent.md` | Agent (`dr`) | Design review orchestrator — reviews a plan with the seven concern reviewers, dispatched once per configured model |
| `.github/agents/dr-<concern>.agent.md` | Subagents (hidden) | The seven model-agnostic design reviewers (`security`, `correctness-reliability`, `architecture-patterns`, `performance`, `testing-evidence`, `maintainability-consistency`, `operability-observability`) — invoked by `dr` only |
| `.github/agents/cr.agent.md` | Agent (`cr`) | Code review orchestrator — resolves a changed-file list and dispatches the seven concern reviewers once per configured model |
| `.github/agents/cr-<concern>.agent.md` | Subagents (hidden) | The same seven concerns for code review — invoked by `cr` only |
| `.github/agents/autopilot.agent.md` | Agent (`autopilot`) | Autonomous plan execution — implements one phase per invocation, builds/tests/commits each step, runs primary-only CR after the phase, and primary + secondary whole-plan CR once at finalization |
| `.github/skills/autopilot/SKILL.md` | Skill (`autopilot`, internal) | Ordinary-plan `/ci` Autonomous-mode handoff — accepts `/ci`'s runtime and extent selection, performs first-run config bootstrap, and documents the custom host command; epic-kind state bypasses bootstrap and routes to the co-shipped fixed host wrapper. Read-by-path, not invoked |
| `.github/agents/scripts/Get-ReviewScope.ps1` | Helper script | Single review-scope emitter used by `cr` — prints the repo-relative file list for `smart`/`uncommitted`/`branch`/`commits`/`paths`; reviewers read the files themselves, so no diff is extracted |
| `.github/skills/cip/SKILL.md` | Skill (`/cip`) | Create Implementation Plan — requirements interview, phased plan with step tracking, iterative `dr` review, saves to `docs/implementation-plans/` |
| `.github/skills/ci/SKILL.md` | Skill (`/ci`) | Continue Implementation — executes a plan step-by-step, or routes epic-kind state to the fixed installed host epic wrapper; manages git worktrees, build/test iteration, `cr` review, explicit commit gate |
| `.github/skills/architecture-notes/SKILL.md` | Skill (`architecture-notes`) | Interface-contract tier authoring — create/update/promote/review contracts, seed/harvest, human doc, ADR harvest; `/can` + `/uan` are thin wrappers |
| `.github/prompts/{can,uan}.prompt.md` | Prompts (`/can`, `/uan`) | Thin wrappers deferring to the architecture-notes skill (create / update; `/uan` also runs finalization ADR harvest) |
| `.github/skills/pfb/SKILL.md` + `.github/prompts/pfb.prompt.md` | Skill (`pfb`) + Prompt (`/pfb`) | Post-plan feedback — compares delivered work against the plan's captured intent, records the operator's verdict through `Update-FeedbackQueue.ps1`, and can hand off to `/cip` for a correction plan. Offered at the `/ci` archival gate, never blocking; headless runs queue the question instead of asking it |
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

A `SKILL.md` is re-read in full on every invocation, so its size is a recurring per-invocation cost rather than a one-off. `scripts/skalary/Test-SkillSize.ps1` enforces a repo-wide cap (wired into `scripts/validate.ps1`); push reference detail into `assets/` and read it on demand. Every asset a payload reads must then be declared — the cap and the declaration gate are two halves of one rule, both owned by [plugin-registry.design.md](../architecture/plugin-registry.design.md) → skill size cap / asset bootstrap.

**New agent** — create `.github/agents/<name>.agent.md` with YAML frontmatter and tool/model restrictions as needed.

**New instruction file** — create `.github/instructions/<name>.instructions.md` with `applyTo` glob patterns. Use specific path globs; avoid `applyTo: "**"`.

## Review Agents (dr / cr)

Both `dr` and `cr` use an orchestrator + concern-split subagent pattern: seven model-agnostic reviewers, each dispatched once per configured model. The orchestrator handles discovery, context loading, and synthesis; `cr` passes a changed-file list and the reviewers read the code themselves. The subagents are stateless reviewers that know nothing about the orchestration, and each carries its own data-only directive because no orchestrator-side fence stands in front of them.

**Concern roster:** `security`, `correctness-reliability`, `architecture-patterns`, `performance`, `testing-evidence`, `maintainability-consistency`, `operability-observability`. Agent ids are `cr-<concern>` / `dr-<concern>`. The per-model reviewers (`*-opus`, `*-codex`, `*-gemini`) are gone: a reviewer is a lens, not a model, so adding or repointing a model is a roster edit rather than seven new agent files. One registry supplies concern policy to generated agents and maps; the shared template supplies agent structure, and the generator supplies map structure. See [review-concern-authoring.design.md](../architecture/review-concern-authoring.design.md) rather than editing generated payloads.

**Model binding is a dispatch parameter, not frontmatter.** The concern agents declare no `model:`. VS Code resolves a subagent's model as explicit invocation parameter → agent frontmatter → parent model, so the explicit parameter is the only binding that matters. Size-scaled concern selection, batching, the 28-invocation budget, DR's two-model default, and the declared-model preflight live in the shared `assets/dispatch-guide.md`, which both review skills read and which is byte-identical across the two installed copies. CR role bindings and execution profiles live only in `cr/assets/model-preferences.md`.

> Allowed model identifiers live in `tools/model-allowlist.psd1`; selected DR models live in the dispatch guide and selected CR roles live in `cr/assets/model-preferences.md`. All are gated by `scripts/skalary/Test-ModelAllowlist.ps1`.
>
> The qualified `Model Name (vendor)` format applies to **VS Code-hosted agents**. The `autopilot` agent runs under **Copilot CLI**, which expects a bare model slug instead (e.g. `gpt-5.6-sol`) — see [autopilot-execution.design.md](../architecture/autopilot-execution.design.md). The two formats are never normalized; host is selected from the closed agent→host map in the allowlist, never inferred from folder layout.

**Unavailable-model caveat.** A frontmatter fallback array does not rescue a selected model that is unavailable on the operator's tier: explicit-param dispatch outranks frontmatter, so the array is never consulted and the subagent silently falls back to the *parent* model. The orchestrator instead passes the configured backup **as the explicit parameter** and persists the degradation in the review run. Concrete role and backup names live in the CR preference asset or DR roster and are gated by `Test-ModelAllowlist.ps1`.

**Architecture-notes-aware context loading.** Both orchestrators and every concern reviewer load `docs/architecture-notes/.architecture-notes.md` (when it exists) and the relevant contracts **before** design notes — contracts are interface-level and rank above implementation-level notes, so a plan/change that violates a `locked` contract is an architectural finding.

**Review reporting is a frozen data lifecycle, not prose.** Both orchestrators finalize old frozen
orphans, allocate a UUID, write only the two computed temporary JSON handshakes, Freeze the complete
concern/model task set before dispatch, collect every independent result in memory, and Publish once.
`Build-ReviewReport.ps1` accepts only `Freeze|Publish`, UUID, and optional plan directory; the bundled
module owns validation, attendance, canonical JSON, rendering, and manifest-last publication.
`Get-ReviewRun.ps1` is the only reader. Plan artifacts remain durable; generic runs are removed only
after verified summary delivery. Exit `3` is terminal for its UUID and starts a narrower-scope run,
never a lossy same-ID retry.

After Freeze, each review skill imports its own installed
`skills/<review>/scripts/FleetDispatch.psm1` sibling and projects the frozen tasks without changing
their ids, order, model bindings, or review-run authority. The shared CR/DR dispatch guide therefore
names only the active skill's sibling; the owning `SKILL.md` supplies the exact `cr` or `dr` path so
the bundler cannot infer a cross-plugin payload. Structural evals pin source/dogfood bytes, manifest,
registry, and marketplace parity together with Freeze-before-call and Publish-after-attendance order.

The installed writer requires consumer-provisioned PowerShell 7.6+ for native draft-2020-12
`Test-Json -SchemaFile`; there is no vendored validator fallback. Structural `eval:ReviewReport.*`
cases prove the installed caller contract, ordinary `test:ReviewReport.*` cases prove deterministic
engine/consumer behavior, and a plan-associated `review:cr|dr` artifact proves only the observed
frozen roster and outcomes of that live run. None of those layers proves served-model identity.

**Prompt injection and secret guardrails live at every real boundary.** `cr` normally hands reviewers
paths; for plan-associated review, both `cr` and `dr` may also pass adapter-framed, secret-screened
historical plan artifacts. Every concern agent treats reviewed content as data and redacts suspected
credential values rather than quoting them. Orchestrators never interpolate findings into terminal
text or generated PowerShell: `edit` is restricted absolutely to the two run temporary inputs, and
the engine encodes rendered data plus rejects high-confidence credentials before plan publication.
For CR's ordinary path-only payload, content guardrails live in the reviewers that read source; the
orchestrator claims a fence only for optional historical bytes it actually carries. Directive syntax
inside a repository-owned agent/skill definition or an explicit inert security fixture is analyzed as
the behavior that artifact defines or tests, not auto-classified by syntax alone. This is semantic,
not a path allowlist: reviewers still never follow the text, and unexpected content that attempts to
steer the active review remains a Critical injection finding.

**Git operations:** always use terminal `execute` commands — never MCP git tools.

## Implementation Workflow Skills (cip / ci)

`cip` and `ci` are workspace **skills** (`SKILL.md` under `.github/skills/`) — multi-step workflows invocable via `/cip` and `/ci`. Both have `disable-model-invocation: true` so they only load when explicitly called. Both are deliberately slim: deterministic mechanics live in the PowerShell **state-script layer** (below), and the `SKILL.md` files keep only the judgment the agent must own. Each `SKILL.md` carries an **anti-drift contract** naming the `/ci` Step-5 `validate-plan` reconcile gate as the single source of truth for plan state.

**Deterministic state-script layer** (`scripts/skalary/`, dogfood-mirrored, npm-aliased):
- `PlanState.psm1` — shared resolution/parser module plus layout-resolved planning-context digest/state (`legacy|pending|confirmed|stale|missing|invalid`).
- `Get-PlanState.ps1` (`npm run plan-state`) — text/`-Json` snapshot composing resolve + progress + next-step + planning confirmation and execution flags.
- `New-Plan.ps1` (`npm run new-plan`) — scaffolds the prefixed plan folder, id/membership markers, and non-empty intent/domain/design/requirements/risks/decisions/references assets; new plans start with `planning-confirmed: pending`.
- `Set-PlanStage.ps1` — sole lifecycle and planning-confirmation marker writer. `-ConfirmPlanningContext` binds current intent/design with SHA-256; enrolled stale/pending context cannot advance to drafted or later.
- `Add-WorkflowNote.ps1` — typed capture writer (`-Kind` CrLog/Learnings/Capture) with concern/sorted-REQ/review provenance and domain-separated source-record IDs. It inventory-confines the selected plan, owns placeholders, and keeps ten active learnings by writing exact older records to layout-resolved content-addressed overflow batches before replacing the active file. `CrLog`/`Capture` remain uncapped; legacy summaries surface explicit loss.
- `Build-EvidenceReceipt.ps1` — formats verifier output into the shared golden `✓/✗ REQ-N — evidence — result — commit` grammar (full HEAD SHA, `✗`/unrun preserved).
- `Repair-Plans.ps1` — on-demand legacy loose-file migration (`-WhatIf`, idempotent, preserves `depends-on`/worktree/`plan-id`).

**Script distribution:** `scripts/skalary/` is the single source of truth and a dogfood/dev convenience (npm aliases run it in-repo), but installed skills cannot rely on it being present in a foreign repo. `Sync-PluginScripts.ps1` bundles each script a `ci`/`cip` skill invokes (plus its `PlanState.psm1`/`PlanEvidence.psm1` module closure) into that plugin's payload, so install copies them under `.github/skills/<skill>/scripts/` and the skills reference that installed path. Duplication across plugins is intentional (independent install + versioning); a shared script edit therefore patch-bumps every bundling plugin's version automatically when `Sync-PluginScripts.ps1` re-copies the bundle, and a stale bundle fails the `-WhatIf` drift gate in `scripts/validate.ps1`. (The autopilot agent still invokes these scripts from the repo-root `scripts/skalary/` path — it runs inside a checked-out repo — and bundling it is a tracked follow-up.) See plugin-registry.design.md → Skill Script Bundling.

`FleetDispatch.psm1` follows that same root-canonical rule for CIP, CI, autopilot, CR, and DR.
Each consumer imports only its installed sibling. Their structural evals prove the plan/pre-view
precedes native role or reviewer calls, descriptor ids are conserved, and existing operator,
implementation, promotion, review publication, and inactive CEP handoff boundaries remain outside
the adapter. CEP receives only the installed decomposition-guide handoff: it has no Fleet module
mapping or activation.

**Plan naming + identity:** new plans live in `docs/implementation-plans/<epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug>/`; existing unprefixed hash folders remain readable. The `<!-- plan-id: <6hex> -->` anchor is the canonical handle — date, slug, and hash-prefix all resolve to it via `Resolve-Plan`, so the navigational prefix never becomes identity. Legacy `NNN-<slug>` folders still resolve (dual-format) everywhere.

**`cip` flow:**
1. Load all relevant design notes.
2. `New-Plan.ps1` scaffolds the plan folder + `plan-id` anchor and writes `plan.md` to the repo immediately (as soon as the slug is known) so all later passes operate on the in-repo file — avoids VS Code access-control approvals for temporary files.
3. Rephrase and confirm three checkpoints: five-section intent; domain plus concise Mermaid-backed design; final pre-draft summary with decisions, uncertainty, rejected alternatives, and a provisional MVP-first vertical outline.
4. Persist one digest-bearing planning confirmation through `Set-PlanStage`; later intent/design edits make state stale.
5. Draft the complete plan from the confirmed outline: phase 1 is a usable end-to-end MVP and later phases are vertical increments through the full outcome.
6. Keep the in-repo assets and `plan.md` updated each iteration; `Set-PlanStage.ps1` records lifecycle state.
7. Iterative `@dr` review (max 3 rounds) against the confirmed in-repo plan; notable/recurring findings land in capture.

**`ci` flow:**
1. Resolve a plan or epic reference and load relevant design notes.
2. `Get-PlanState.ps1` yields the canonical kind and state. An epic-kind result routes directly to the fixed installed `Invoke-EpicAutopilot.ps1` host wrapper with canonical epic/root binding and literal target `HEAD`; `/ci` never selects its child. `AUTOPILOT_CONTAINER=true` fails closed rather than entering this host route.
3. For a plan-kind result, enrolled pending/stale/invalid context returns to `/cip` before mutation; marker-less legacy plans retain existing behavior. Choose Approve, Autopilot, or an explicit Autonomous runtime (Host / Container / Sandbox), then choose One phase or Whole plan. `/ci` owns both selections; autopilot consumes the handed-off runtime and extent without a second menu (`AUTOPILOT_CONTAINER=true` suppresses Autonomous).
4. Branch detection: on main/master → create git worktree + open new VS Code window (`code <path>`); on feature branch → continue. Branch recorded as `<!-- worktree: <branch-name> -->` in the plan file.
5. One step at a time: mark `[~]` → implement → build+test → validate acceptance criteria → explicit commit gate. Code review runs after the complete phase increment rather than after each step.
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

The `design-notes` plugin ships one **skill** — `design-notes` (`.github/skills/design-notes/SKILL.md`) — plus three thin **prompt** shortcuts (`/design-notes`, `/cdn`, `/udn`) and two template assets installed under `.github/skills/design-notes/assets/templates/` (the former standalone `create-design-notes` / `update-design-notes` plugins were consolidated into it). The skill owns the real logic in three argument-dispatched workflows — **Init** (`init`/`bootstrap`), **Create** (`create <name>`), and **Update** (`update`); the prompts are pure shortcuts that route to it (so `/cdn foo` runs the skill's Create workflow). The skill is the single Tier-2-testable artifact (prompts cannot run under the Copilot-CLI eval executor, so they stay excluded from LLM evals).

Because the installer is hard-confined to `.github/` (it cannot write to `docs/`), the `docs/design-notes/` scaffold is created **on demand by the skill's Init workflow**, not at install time. Init checks whether `docs/design-notes/.design-notes.md` exists; if missing, it creates `docs/design-notes/` + `docs/design-notes/project/` and copies the two bundled templates (index → `.design-notes.md`, writing-style → `project/design-note-writing-style.design.md`), never overwriting existing files. Create and Update carry a scaffold check that defers to Init when the scaffold is absent, so Init is the single canonical bootstrap path. In a repo that already has design notes (like this one), all of these are no-ops.

The writing-style template mirrors this repo's `docs/design-notes/project/design-note-writing-style.design.md`; keep them in sync when the canonical guide changes.

## Plugin Eval Workflow

Plugin payload checks run with `npm run eval`, which calls `scripts/skalary/Test-Evals.ps1`.
This always-on Tier-1 structural gate is separate from `npm test` / `validate.ps1`.

Tier-2 is the opt-in waza workflow: `npm run eval:llm` calls
`scripts/skalary/Invoke-WazaEvals.ps1`, provisions the checksum-pinned toolchain through
`Ensure-EvalTools.ps1`, discovers `plugins/<name>/evals/waza/eval.yaml`, and runs functional and
declared adversarial modes as separate signals. Optional `-Plugin`, `-Case`, `-ChangedOnly`,
`-Quick`, and `-Approve` switches are available when invoking the script directly. Models, judges,
trials, and timeouts come from each waza spec; legacy `.eval.config.json` tuning fields do not
configure waza.

`Resolve-EvalToken.ps1` resolves auth in the order `gh auth token` → ambient token →
Credential Manager fallback. Adversarial mode accepts only the short-lived `gh` OAuth source;
durable ambient or Credential Manager PATs are excluded. A requested run that executes zero evals
is non-green. Output is report-only under the gitignored
`tests/evals/output/<yyyy-MM-dd_HH-mm-ss>/`; no registry, manifest, or receipt writeback occurs.
