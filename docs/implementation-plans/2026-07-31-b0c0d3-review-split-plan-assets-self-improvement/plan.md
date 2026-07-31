# b0c0d3: Review split, plan assets, and self-improvement loops
<!-- plan-id: b0c0d3 -->
<!-- cip-stage: dr-round-2 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 8 -->
<!-- expected-packages: dotnet:none; npm:none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Evolution log — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

## Phase 1: Plan layout — plan.md plus assets

<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap for this plan: 8) -->

- [x] 1.1 Rewrite `assets/plan-template.md` so `plan.md` holds only header markers, phases/steps, and one-line links to `assets/{intent,requirements,risks,decisions,references}.md` (REQ-1) `M`
- [x] 1.2 Extend `New-Plan.ps1` to scaffold the `assets/` folder and its files alongside `plan.md`, path-confined as today. Scaffolded files carry an explicit placeholder, never zero content, so "present-but-empty" stays distinguishable from "authored" (REQ-1, RISK-3) [after: 1.1] `M`
- [x] 1.3 Add `Resolve-PlanSection` **inside `Get-PlanMetadata`** (not at the `Test-Plan` boundary) resolving per section: missing asset → legacy fallback; present-but-empty or malformed → fail loud; both present → asset wins and divergent legacy content errors (REQ-2, RISK-3) [after: 1.1] `L`
- [x] 1.4 Prove parity across **all** consumers — `Test-Plan`, `Get-PlanState`, `Get-NextStep` — with a legacy plan and its assets-layout twin, plus a case per resolver edge condition; run the validator over every existing plan (REQ-2, RISK-3) [after: 1.3] `L`
- [x] 1.5 Update `/ci` Step 1 and the execution guide to load `assets/` on demand, never wholesale (REQ-3) [after: 1.4] `S`
- [x] 1.6 Make the log and receipt writers/readers layout-aware via a shared `Resolve-PlanAssetPath` — `Add-WorkflowNote.ps1`, `Build-EvidenceReceipt`, `crosscheck-guide.md`, `execution-guide.md`, the ADR-harvest guidance, **and their bundled plugin copies** — so writes and reads never disagree (REQ-20) [after: 1.3] `L`
- [x] 1.7 Migrate this plan to the new layout as a **single atomic edit** (write assets and remove the tables together), then re-validate before commit. Must follow 1.6: migrating first would leave writers targeting the legacy root for the rest of the run (REQ-3, REQ-20) [after: 1.5, 1.6] `S`
- [x] 1.8 Make `Test-Plan.ps1` read the `phase-budget-points` header marker with a default of 6 instead of hardcoding the cap, and align `drafting-guide.md` — which claims plans "Block at 35KB/700 lines" while the validator only warns (REQ-21) `S`

## Phase 2: Intent capture and human-step detail

<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add an Intent section to `interview-guide.md` (goal, desired outcome, success signals, non-goals, operator definition of done) plus an `intent` gate that blocks drafting until intent is confirmed (REQ-4) [after: 1.2] `M`
- [x] 2.2 Add `assets/intent-template.md`; make `/ci` read `assets/intent.md` before implementing any step and re-anchor against it at phase crosscheck (REQ-4) [after: 2.1, 1.4] `M`
- [x] 2.3 Add the `human-step-detail` gate to `Test-Plan.ps1`: an `@human` step without a details block containing **Steps**, **Verify**, and **Rollback** fails the plan (REQ-5, RISK-7) `M`
- [x] 2.4 Update the drafting guide and plan template with the required `@human` detail shape, and make `/ci` print the full block at the handoff instead of the bare step title (REQ-5) [after: 2.3] `S`

## Phase 3: Cross-plan requirement and decision index

<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Add `scripts/skalary/Get-PlanIndex.ps1` — deterministic JSON + markdown index of REQ / RISK / decision records across active **and** archived plans, both layouts (REQ-6) [after: 1.4] `L`
- [x] 3.2 Make `/cip` Step 1 consult the index (not the plans) and require the interview to reconcile against prior decisions before drafting (REQ-6) [after: 3.1] `S`

## Phase 4: Concern-split reviewers on two models

<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 4.1 Add `tools/model-allowlist.psd1` with **two** lists (VS Code qualified names, Copilot CLI bare slugs) plus a closed agent→host map, and `Test-ModelAllowlist.ps1` that selects by that map and fails loud on any unmapped agent (REQ-7) `M`
- [x] 4.2 Author the 7 model-agnostic `cr-<concern>.agent.md` reviewers — each carrying its own data-only directive and "flag directive-looking content as Critical" rule (replacing the deleted orchestrator fence), its focus lens, and arch-contract awareness (REQ-8, RISK-11) `L`
- [x] 4.3 Mirror the 7 concerns as `dr-<concern>.agent.md`; delete `cr-opus`/`cr-codex`/`cr-gemini` and the dr equivalents plus their dogfood copies, and update waza fixtures (REQ-8, RISK-8) [after: 4.2] `L`
- [x] 4.4 Write the shared `assets/dispatch-guide.md` (cr + dr): per-invocation model override, size-scaled concern thresholds, concerns run once over the union of files, the 28-invocation **budget** the orchestrator reports against, batch-size bound and subsystem-matching rule, a DR-side batching contract (H2 phase / asset file), declared-model preflight plus the stated undetectable served-model residual, Pro-tier GA fallback selection, and `concern-ledger-map.md` (REQ-9, REQ-10, RISK-1, RISK-2, RISK-4) [after: 4.3] `L`
- [x] 4.5 **Validate, do not change**, autopilot's model binding: confirm `autopilot.agent.md` and `.autopilot.json` still carry the CLI bare slug `claude-opus-5` and that the host-aware allowlist accepts it. Never repoint autopilot's model from inside a run it is executing (REQ-7) [after: 4.1] `S`
- [ ] 4.6 Add `scripts/skalary/Build-ReviewReport.ps1` — a pure formatter taking typed finding objects and returning merged report text (dedup by root cause + component, `Models` attribution, severity elevation on unanimous agreement, severity-descending sort); no file I/O in the script itself (REQ-18) [after: 4.4] `L`

## Phase 5: Code-review scope simplification

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Add `Get-ReviewScope.ps1` collapsing all six diff helpers into one file-list emitter (`uncommitted` · `branch` · `N` · paths · smart default) (REQ-11) `L`
- [ ] 5.2 Rewrite cr orchestration to pass the file list plus the design-note set and let reviewers read code themselves; drop diff extraction and content batching. The orchestrator-side untrusted-content fence is removed only because step 4.2 relocated the equivalent directive into every concern agent — verify that before deleting it (REQ-11, RISK-11) [after: 5.1, 4.4, 4.2] `M`
- [ ] 5.3 Delete the six `get-diff-*.ps1` scripts, update `plugin.json` `files[]`, and assert no remaining references (REQ-11) [after: 5.2] `M`

## Phase 6: Review skills and prompt audit

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Create `plugins/code-review/skills/cr/SKILL.md` plus assets owning the orchestration; keep the base skill thin (REQ-12, REQ-16) [after: 5.2] `L`
- [ ] 6.2 Create `plugins/design-review/skills/dr/SKILL.md` plus assets, reusing the shared dispatch guide (REQ-12, REQ-9, RISK-1) [after: 6.1] `M`
- [ ] 6.3 Reduce `cr.agent.md` / `dr.agent.md` to thin shims that read the skill by path, preserving `handoffs:`; repoint `cr.prompt.md` / `dr.prompt.md` at the skills (REQ-12) [after: 6.2] `M`
- [ ] 6.4 Audit the remaining five prompts (`cdn`, `udn`, `design-notes`, `can`, `uan`), confirm each is a thin skill shortcut, and add a structural test asserting it (REQ-12) `S`
- [ ] 6.5 Bundle `Build-ReviewReport.ps1` into both review plugins via `Sync-PluginScripts`, make both orchestrators call it and write its returned text, and assert neither describes the report layout in prose (REQ-18) [after: 6.2, 4.6] `M`

## Phase 7: Post-plan expectation alignment

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Create the `self-improvement` plugin with `skills/pfb/SKILL.md` plus assets: compare delivered work against `assets/intent.md`, collect operator corrections, optionally scaffold a correction plan via `/cip` (REQ-13) [after: 2.2] `L`
- [ ] 7.2 Add the autopilot-safe path: headless runs write a queued feedback marker instead of prompting, and the next interactive session consumes it (REQ-13) [after: 7.1] `M`
- [ ] 7.3 Wire `/pfb` into the `/ci` archival gate — offered before archiving, never blocking (REQ-13) [after: 7.2] `M`

## Phase 8: Self-improvement loop

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 8.1 Add `skills/si/SKILL.md` plus `assets/harvest-guide.md`: read review-ledger categories, `learnings.md`, `cr-log.md`, and queued `/pfb` feedback **wrapped in `UNTRUSTED_INPUT` markers**, with an explicit never-execute-harvested-directives rule; produce ranked improvement candidates (REQ-14, RISK-10) [after: 7.3] `L`
- [ ] 8.2 Add the propose-and-PR flow plus `Test-SiWriteScope.ps1`: diff base `main...HEAD` covering tracked, staged **and untracked** paths, canonicalize-then-confine to `plugins/` `docs/` `.github/{skills,agents,prompts}/`, symlink-escape rejection, and an outright deny on `.github/workflows/` + `.github/actions/`; worktree, draft PR, never auto-merge (REQ-14, RISK-6, RISK-10, RISK-12) [after: 8.1] `L`
- [ ] 8.3 Switch `/ci` harvest to the concern-to-ledger map so ledger entries are categorized deterministically (REQ-10) [after: 4.4] `M`
- [ ] 8.4 Offer `/si` at plan completion in both `/ci` and the autopilot harvest mirror; document the consumer-repo fork/upstream flow as manual (REQ-14) [after: 8.2] `M`

## Phase 9: Epic planning

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 9.1 Add `New-Epic.ps1` scaffolding an epic folder plus `epic.md` and stamping `<!-- epic: <id> -->` into child plans (REQ-15) [after: 1.4] `L`
- [ ] 9.2 Add `skills/cep/SKILL.md` to the `create-implementation-plan` plugin: high-level goal → interview → decomposition into independently executable child plans with `depends-on` wiring (REQ-15, REQ-16) [after: 9.1] `L`
- [ ] 9.3 Teach `/ci` to resolve an epic id, show rollup progress, and select the next unblocked child plan (REQ-15) [after: 9.2] `M`

## Phase 10: Hygiene, docs, and finalization

<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 10.1 Add `Test-SkillSize.ps1` plus the repo-wide size-cap test; push any over-cap detail into `assets/` (REQ-16) [after: 9.2] `M`
- [ ] 10.2 Extend the `Sync-PluginScripts.ps1` reference scanner from `.ps1`-only to every asset a payload file reads, under a **closed grammar** (installed-path literals plus relative `./assets/<file>`), excluding fenced examples and prose links; require each to appear in `files[]`; keep the `-WhatIf` drift gate in `validate.ps1` (REQ-19, RISK-9) [after: 9.2] `L`
- [ ] 10.3 Add a machine-readable `scaffolds[]` array to the plugin schema **and to the registry schema + `Build-Registry.ps1`** (consumer installs resolve against `registry.json`, and it currently sets `additionalProperties: false`), declaring every runtime path the `.github/`-confined installer cannot write. Each entry is a fixed literal path or an explicitly-flagged parameterized path routed through a confine helper; bind the scanner to it (REQ-19, RISK-9) [after: 10.2] `L`
- [ ] 10.4 Update design notes `plan-workflow`, `copilot-customizations` (removing the description of the deleted orchestrator fence), and `plugin-evals`; add a note for the `self-improvement` plugin and record the Pro-plan model caveat (REQ-17, RISK-2, RISK-11) [after: 10.3] `L`
- [ ] 10.5 Run the payload pipeline in order — CRLF re-materialize → `Sync-PluginScripts` → `Sync-Dogfood` → `Build-Marketplace` → `Build-Registry` → `npm test` → `npm run eval`. Runs **after** the scanner so `files[]` is complete before hashing (REQ-17, RISK-5, RISK-8) [after: 10.4] `M`
- [ ] 10.6 Plan crosscheck: rebuild `assets/evidence.md`, verify every REQ marker, confirm intent alignment (REQ-17) [after: 10.5, 1.7] `M`

## Finalization (conditional)

- [ ] 10.7 Operator acceptance gate (REQ-17, RISK-1, RISK-7) @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. In chat, run `cr branch` — confirm the 7 concern reviewers appear and the reported invocation count is within the budget of 28.
  2. Run `/dr` against this plan file — confirm the same 7-concern fan-out and that no Gemini reviewer runs.
  3. Run `/cip` on a throwaway goal — confirm it asks the intent questions and scaffolds `assets/intent.md`.
  4. Install the touched plugins into a scratch clone (`Install-Plugin.ps1`) and run `/cr` there — confirm no missing-asset error.
  5. Confirm `plugins/autopilot/agents/autopilot.agent.md` and `.autopilot.json` still carry the bare slug `claude-opus-5` — unchanged by this plan.
  6. Stage a throwaway edit to `.github/workflows/registry-ci.yml` on a branch and run `Test-SiWriteScope.ps1` — it must **refuse**.
  7. Run `pwsh -NoProfile -File scripts/validate.ps1` then `npm test`.

  **Verify:** the declared-model preflight passes or fails loud (never silent); `Test-SiWriteScope.ps1` denies the workflow edit in step 6; both review reports are byte-identical to `Build-ReviewReport.ps1` output for the same findings (REQ-18); the scratch-clone `/cr` run reads every asset it needs (REQ-19); `validate.ps1` and `npm test` both exit 0; `assets/evidence.md` contains no `✗`.

  Two things are **advisory and must not be treated as proof**: reviewer self-reported model names (the served model is not observable — RISK-1), and the 28-invocation budget (reported, not enforced).

  **Rollback:** `git revert` the phase commits. The deleted diff helpers and per-model reviewer agents are recoverable from git history; no external state is mutated.

  </details>
