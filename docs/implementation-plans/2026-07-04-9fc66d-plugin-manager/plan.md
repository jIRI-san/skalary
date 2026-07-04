# 9fc66d: Plugin Manager Plugin
<!-- plan-id: 9fc66d -->
<!-- cip-stage: dr-round-2 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: phase -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: dotnet:none; npm:none -->

## Decisions
<!-- Key decisions made during planning — one bullet per decision -->
- **Dual install system.** Two parallel catalogs are maintained from the same `plugins/*/plugin.json` sources: skalary's `registry.json` (PowerShell script install into a repo's committed `.github/`, used by VS Code Copilot) and a generated Copilot CLI `marketplace.json` under `.github/plugin/` (native `copilot plugin install`, user-scoped). The plugin-manager skills wrap **only** the skalary PowerShell scripts.
- **Four separate user-invocable skills** — `install-plugin`, `uninstall-plugin`, `list-plugins`, `update-plugin` — one per situation, each with `user-invocable: true`, `disable-model-invocation: true`, `context: fork` frontmatter (mirrors the `ci` skill).
- **Skills invoke existing scripts, not new logic.** Each SKILL.md calls the bundled `scripts/skalary` scripts (`Install-Plugin.ps1`, `Remove-Plugin.ps1`, `Update-Plugin.ps1`, `Find-Plugin.ps1`, `Get-Plugin.ps1`) by their **installed** path `.github/skills/<skill>/scripts/<Script>.ps1` and always pass `-RepoRoot .` so `Resolve-RepoRoot` anchors on the consuming repo, not the bundle folder.
- **Registry-path fallback.** In a bootstrapped repo only `scripts/skalary/registry.json` exists (no root `registry.json`), and `Resolve-RepoRoot` always resolves to the git root so it cannot reach it. `Find-Plugin.ps1`, `Get-Plugin.ps1`, and the uninstall dependent check gain a `-RegistryPath` parameter (falling back to `scripts/skalary/registry.json`) so "available" listing and the dependent guard work in a bootstrapped repo.
- **`_Common.ps1` closure fix (foundation).** The bundled scripts dot-source `_Common.ps1` (a `.ps1`). `Sync-PluginScripts.ps1` currently only follows `.psm1` module imports, so `_Common.ps1` would not be co-bundled and installed skills would break at runtime. The bundler's `Get-ModuleClosure` BFS is widened from `\.psm1` to `\.psm?1` so discovered `.ps1` (e.g. `_Common.ps1`) are enqueued and their own closures walked; the plan confirms no wrapped script invokes a sibling `.ps1` via the `&` call operator (which a dot-source-only match would miss). Because `Sync-PluginScripts.ps1` never edits `files[]`, every co-bundled script (`_Common.ps1` + any read-only script) is enumerated **explicitly** in `plugin.json` `files[]`, and an eval asserts its presence in `registry.json` and the installed `.github/` tree — not just the source bundle.
- **Source defaults to `jIRI-san/skalary@main`**, overridable via skill arguments passed through to the scripts' `-Repository`/`-Ref`.
- **Bootstrap auto-installs plugin-manager.** After downloading the flat `scripts/skalary` set (now including `Set-ScriptApproval.ps1`) + `registry.json`, `bootstrap.ps1` runs `Install-Plugin.ps1 -Name plugin-manager`, which **clones the remote sources at the pinned `-Ref`** (it does not install from the flat files bootstrap downloaded) and copies payload files only. Bootstrap prints the install plan first, then offers auto-approval for `plugin-manager`'s **read-only** scripts only.
- **Copilot CLI compatibility is de-risked first.** Before building the schema/generator, a feasibility spike proves `copilot plugin install` accepts a representative skalary `plugin.json`/`marketplace.json` and confirms `strict: false` exists and suppresses unknown-field rejection. Because `marketplace.json` points `source = plugins/<name>`, the CLI reads the **same** `plugin.json` that conforms to skalary's `additionalProperties:false` schema; if the CLI rejects the shared file, the plan splits into a Copilot-native `plugin.json`. Conformance is proven by an automated `Marketplace.CopilotFields` test plus a `@human` `copilot plugin install` smoke test.
- **Terminal auto-approval is opt-in, read-only, and per-script.** `chat.tools.terminal.autoApprove` approves a command **regardless of arguments**, so `Set-ScriptApproval.ps1` writes entries **only** for read-only scripts (the `list`/`find`/`get`/`test`/`validate` family) and **never** for `Install`/`Uninstall`/`Update`/`Remove`/`bootstrap` — those keep a per-run human gate so a prompt-injected `-Repository`/`-Ref`/`-Source` cannot trigger a silent remote install. The writer is **JSONC-aware** (preserves comments and trailing commas in `.vscode/settings.json`), writes **regex-escaped, command-line-anchored** patterns (matching the real `pwsh -NoProfile -File <path> …` invocation, not an unescaped bare path that would over-match), preserves unknown keys, is idempotent, confines paths to `.github/`, and emits a post-write diff of exactly which keys changed. The writer uses **regex-escaped, both-end-anchored** (`^…$`) patterns whose argument tail is a shell-metacharacter-free character class (never `.*`, so a chained `; curl … | sh` cannot ride an approval), with deny-list precedence. The `install-plugin` skill asks via `vscode_askQuestions` (listing each approvable script + skill + its function) before writing; `uninstall-plugin` removes the plugin's entries.
- **Non-goal: cross-surface registry.** The skalary skills operate on skalary-managed repos (a root or `scripts/skalary/registry.json`). A repo where `plugin-manager` was installed **only** via native `copilot plugin install` has no skalary registry; `list-plugins`/`uninstall-plugin` surface a friendly "not a skalary-managed repo" message rather than pretending to manage it (RISK-10).

## Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | `plugin-manager` plugin exists as a source bundle and is registered. | `file:plugins/plugin-manager/plugin.json#exists` · `file:plugins/plugin-manager/plugin.json#contains:"license"` · `file:registry.json#contains:"name": "plugin-manager"` · `test:PluginManager.Manifest` | 2.1, 2.3 |
| REQ-2 | Four user-invocable skills (`install-plugin`, `uninstall-plugin`, `list-plugins`, `update-plugin`) each ship a valid `SKILL.md` that invokes the bundled skalary script by installed path with `-RepoRoot .`. | `file:plugins/plugin-manager/skills#dircount>=4` · `file:plugins/plugin-manager/skills/install-plugin/SKILL.md#contains:.github/skills/install-plugin/scripts/Install-Plugin.ps1` · `file:plugins/plugin-manager/skills/install-plugin/SKILL.md#contains:-RepoRoot \.` · `test:PluginManager.Skills` | 2.2, 2.3 |
| REQ-3 | `Sync-PluginScripts.ps1` follows `.ps1` dot-source closures and every co-bundled script is enumerated in `files[]`, so `_Common.ps1` reaches `registry.json` and the installed tree. | `file:scripts/skalary/Sync-PluginScripts.ps1#contains:_Common` · `file:plugins/plugin-manager/plugin.json#contains:_Common.ps1` · `file:plugins/plugin-manager/skills/list-plugins/scripts/_Common.ps1#exists` · `test:SyncPluginScripts.DotSourceClosure` | 1.1, 2.3, 5.1 |
| REQ-4 | `bootstrap.ps1` auto-installs `plugin-manager` after downloading scripts + registry, then prints usage next steps. | `file:scripts/skalary/bootstrap.ps1#contains:Install-Plugin.ps1` · `file:scripts/skalary/bootstrap.ps1#contains:plugin-manager` · `test:Bootstrap.InstallsPluginManager` | 4.1 |
| REQ-5 | skalary is a valid Copilot CLI marketplace: a generated `.github/plugin/marketplace.json` lists every plugin, validated against a schema and drift-gated. | `file:.github/plugin/marketplace.json#exists` · `file:schemas/marketplace.schema.json#exists` · `file:.github/plugin/marketplace.json#contains:plugin-manager` · `test:Marketplace.Generate` · `test:Marketplace.Drift` | 3.2, 3.3 |
| REQ-6 | `plugin.json` and `marketplace.json` are Copilot-CLI-compatible; the shared `plugin.json` is proven accepted by `copilot plugin install`. | `test:Marketplace.CopilotFields` | 3.1, 3.3, 3.4 |
| REQ-7 | Every skill has a structural eval and at least one LLM eval case. | `file:plugins/plugin-manager/evals#dircount>=1` · `file:plugins/plugin-manager/evals/llm#dircount>=4` · `test:PluginManager.StructuralEvals` | 5.1, 5.2 |
| REQ-8 | The uninstall skill guards against removing `plugin-manager` while other plugins depend on it and warns on self-removal (works in a bootstrapped repo via `-RegistryPath`). | `file:plugins/plugin-manager/skills/uninstall-plugin/SKILL.md#contains:dependent` · `test:PluginManager.UninstallGuard` | 1.2, 2.2 |
| REQ-9 | The list skill surfaces both available (registry) and installed (receipts) plugins and accepts an optional search query. | `file:plugins/plugin-manager/skills/list-plugins/SKILL.md#contains:Get-Plugin.ps1` · `file:plugins/plugin-manager/skills/list-plugins/SKILL.md#contains:Find-Plugin.ps1` · `test:PluginManager.ListScope` | 1.2, 2.2 |
| REQ-10 | Design notes document the new subsystem and the changed contracts; `README.md`/`registry.json` stay in sync. | `file:docs/design-notes/architecture/plugin-manager.design.md#exists` · `file:docs/design-notes/architecture/plugin-registry.design.md#contains:marketplace.json` · `review:cr` | 6.1 |
| REQ-11 | `Set-ScriptApproval.ps1` writes/removes per-script `chat.tools.terminal.autoApprove` entries in `.vscode/settings.json` — JSONC-preserving, regex-escaped + command-line-anchored, read-only scripts only, path-confined to `.github/`, idempotent. | `file:scripts/skalary/Set-ScriptApproval.ps1#exists` · `file:scripts/skalary/Set-ScriptApproval.ps1#contains:chat.tools.terminal.autoApprove` · `test:SetScriptApproval.MergeRemove` · `test:SetScriptApproval.Jsonc` · `test:SetScriptApproval.Confinement` | 1.3, 2.3, 5.1 |
| REQ-12 | The `install-plugin` skill offers opt-in auto-approval for read-only scripts (listing each script + skill + its function via `vscode_askQuestions`); `uninstall-plugin` removes the plugin's entries; `bootstrap.ps1` offers it for `plugin-manager`. | `file:plugins/plugin-manager/skills/install-plugin/SKILL.md#contains:Set-ScriptApproval.ps1` · `file:plugins/plugin-manager/skills/install-plugin/SKILL.md#contains:vscode_askQuestions` · `file:plugins/plugin-manager/skills/uninstall-plugin/SKILL.md#contains:Set-ScriptApproval.ps1` · `file:scripts/skalary/bootstrap.ps1#contains:Set-ScriptApproval` · `test:PluginManager.ApprovalPrompt` | 2.2, 4.1 |
| REQ-13 | This repo's `.vscode/settings.json` auto-approves the **read-only** bundled scripts of existing plugins plus `plugin-manager`, and excludes mutating scripts. | `file:.vscode/settings.json#contains:list-plugins/scripts/Get-Plugin` · `test:RepoSettings.PluginScriptsApproved` | 4.2 |

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Bundled skills break at runtime because `_Common.ps1` (dot-sourced `.ps1`) is not co-bundled or not enumerated in `files[]`. | High | High | Extend the bundler's closure follower to `.ps1` dot-sources (REQ-3); enumerate every co-bundled script in `plugin.json` `files[]`; eval asserts `_Common.ps1` present in `registry.json` + installed `.github/` tree, not just the source bundle. | 1.1, 2.1 |
| RISK-2 | Listing / uninstall-guard fail in a bootstrapped repo where `registry.json` is only under `scripts/skalary/`, not the root. | Medium | Medium | Add `-RegistryPath` fallback (→ `scripts/skalary/registry.json`) to `Find-Plugin.ps1`/`Get-Plugin.ps1`/the dependent check; installed listing (receipts) is always local. | 1.2, 2.2 |
| RISK-3 | A freshly downloaded `bootstrap.ps1` auto-installs before the user can review it (supply-chain surface). | Low | Medium | Install from the pinned `-Ref`; print the install plan first; copy files only (no payload execution); user opts in by running bootstrap. | 4.1 |
| RISK-4 | Copilot CLI rejects the shared skalary `plugin.json` (unknown fields under its validation, or missing CLI-required fields), breaking native discovery. | Medium | High | Feasibility spike before building schema/generator confirms `strict:false` exists and the CLI accepts a representative file; if rejected, split into a Copilot-native `plugin.json`; automated conformance test + `@human` smoke test. | 3.1, 3.4 |
| RISK-5 | Scripts mis-resolve `RepoRoot` when a skill runs from a subdirectory, targeting the wrong tree. | Low | Medium | Every SKILL.md mandates `-RepoRoot .`; structural eval asserts the token is present. | 2.2 |
| RISK-6 | The settings writer corrupts `.vscode/settings.json` (drops JSONC comments/trailing commas) or writes an unescaped path regex that over-matches unrelated commands. | Medium | High | JSONC-aware edit preserving comments/trailing commas; regex-escaped, both-end-anchored (`^…$`) patterns with a shell-metacharacter-free argument class (never `.*`); path confinement to `.github/`; idempotent; fixture tests for comment round-trip, over-match, and chained-command non-match. | 1.3, 4.2 |
| RISK-7 | Auto-approving scripts weakens human-in-the-loop terminal safety; approvals ignore arguments. | Medium | High | Read-only scripts only — `Install`/`Uninstall`/`Update`/`Remove`/`bootstrap` are never approved, so no `-Repository`/`-Ref`/`-Source` vector; strictly opt-in; per-script both-end-anchored escaped patterns with deny-list precedence; `uninstall-plugin` removes entries; post-write diff. | 1.3, 2.2 |
| RISK-8 | The generated `.github/plugin/marketplace.json` is an orphan under the dogfood-authoritative `.github/` tree and collides with the `Sync-Dogfood.ps1 -WhatIf` drift gate. | Medium | Medium | `Build-Marketplace.ps1` owns the path; add an explicit Sync-Dogfood ownership/exclusion rule for `.github/plugin/`; marketplace drift and dogfood drift gates are reconciled. | 3.2 |
| RISK-9 | Bootstrap chains download → install → auto-approve, so an unreviewed bootstrap could write terminal approvals that remove HITL from later runs. | Low | Medium | Approval is read-only-only and opt-in (never silent); mutating scripts stay gated; bootstrap prints exactly which read-only scripts it will approve before writing. | 4.1 |
| RISK-10 | A repo where `plugin-manager` arrived only via native `copilot plugin install` has no `registry.json` on any surface, so `list-plugins`/`uninstall-plugin`'s dependent check hit a raw `throw`. | Low | Low | Treat skalary-managed operations as requiring a skalary-managed repo; `-RegistryPath` resolution emits a friendly "not a skalary-managed repo" message instead of a raw throw. | 1.2 |

## Phase 1: Foundations (script-level changes)
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget advisory cap: 6) -->

- [ ] 1.1 Extend `scripts/skalary/Sync-PluginScripts.ps1` so its `Get-ModuleClosure` BFS follows `.ps1` dot-source closures — widen the module-closure regex from `\.psm1` to `\.psm?1` (already `\$`-escaped and BFS-integrated) so discovered `.ps1` (e.g. `_Common.ps1`) are enqueued and their own closures walked; confirm none of the five wrapped scripts invoke a sibling `.ps1` via the `&` call operator (which a dot-source match would miss) (REQ-3, RISK-1) `M`
- [ ] 1.2 Add a `-RegistryPath` parameter (falling back to `scripts/skalary/registry.json`) to `Find-Plugin.ps1`, `Get-Plugin.ps1`, and the uninstall dependent check so "available" listing and the dependent guard work in a bootstrapped repo without a root `registry.json`; when no registry is found on any surface (e.g. a Copilot-CLI-only repo), emit a clear "not a skalary-managed repo" message instead of a raw `throw` (REQ-8, REQ-9, RISK-2, RISK-10) `M`
- [ ] 1.3 Create `scripts/skalary/Set-ScriptApproval.ps1` — JSONC-aware writer (preserves comments + trailing commas), regex-escaped + both-end-anchored (`^…$`) approval patterns whose argument tail is a shell-metacharacter-free character class (never `.*`, so `; curl … | sh` cannot ride an approval), deny-list taking precedence, **read-only allowlist** (`list`/`find`/`get`/`test`/`validate`; never `Install`/`Uninstall`/`Update`/`Remove`/`bootstrap`), `-Remove`/`-All` modes, path confinement to `.github/`, idempotent, emits a post-write diff of changed keys (REQ-11, RISK-6, RISK-7) `M`

## Phase 2: Plugin bundle, skills, registry
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Create `plugins/plugin-manager/plugin.json` with the full required set (`name`, semver `version`, `description`, `author`, `license`, `tags`, `dependencies: []`) + reserved `evals` (`{path, status:"none", lastRun:null}`); `files[]` enumerates the four `SKILL.md` **and every co-bundled script** (`_Common.ps1` + the read-only scripts each skill invokes) (REQ-1) `S`
- [ ] 2.2 Author the four `SKILL.md` files under `plugins/plugin-manager/skills/<skill>/` — each invoking its bundled skalary script by installed path with `-RepoRoot .`, defaulting source to `jIRI-san/skalary@main`; `list-plugins` uses `Get-Plugin.ps1` + `Find-Plugin.ps1` with `-RegistryPath` fallback; `uninstall-plugin` carries the self/dependent guard and removes auto-approve entries via `Set-ScriptApproval.ps1 -Remove`; `install-plugin` asks via `vscode_askQuestions` whether to auto-approve the **read-only** scripts, listing each script + skill + its function, then calls `Set-ScriptApproval.ps1` on yes (REQ-2, REQ-8, REQ-9, REQ-12, RISK-2, RISK-5, RISK-7) [after: 1.2, 1.3] `L`
- [ ] 2.3 Run `Sync-PluginScripts.ps1`, `Build-Registry.ps1`, then `Sync-Dogfood.ps1` (to populate the installed `.github/` tree); verify `_Common.ps1` is in `plugin.json` `files[]`, `registry.json`, and the installed `.github/` tree, and that `plugin-manager` appears in `registry.json` (REQ-1, REQ-2, REQ-3, REQ-11) [after: 1.1, 1.2, 1.3, 2.1, 2.2] `S`

## Phase 3: Copilot CLI marketplace compatibility
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Feasibility spike — prove `copilot plugin install` accepts a representative skalary `plugin.json`/`marketplace.json` and confirm `strict: false` exists and suppresses unknown-field rejection; if the shared file is rejected, decide the Copilot-native `plugin.json` split before building the generator (REQ-6, RISK-4) @human `S`
- [ ] 3.2 Add `schemas/marketplace.schema.json` (mirroring the documented Copilot CLI `marketplace.json` field set) and a `scripts/skalary/Build-Marketplace.ps1` generator that emits `.github/plugin/marketplace.json` from `plugins/*/plugin.json` (source = `plugins/<name>`); add an explicit `Sync-Dogfood.ps1` ownership/exclusion rule for `.github/plugin/` (REQ-5, RISK-8) [after: 3.1] `M`
- [ ] 3.3 Generate `.github/plugin/marketplace.json`; wire generation + `-WhatIf` drift check + schema validation + the automated `Marketplace.CopilotFields` field-conformance test into `scripts/validate.ps1` / `Test-Registry.ps1` (REQ-5, REQ-6) [after: 3.2] `M`
- [ ] 3.4 `@human` `copilot plugin install jIRI-san/skalary:plugins/plugin-manager` smoke test confirming the four skills load (REQ-6, RISK-4) @human [after: 3.3] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. `copilot plugin marketplace add jIRI-san/skalary` then `copilot plugin install plugin-manager@skalary` (or the `OWNER/REPO:PATH` direct form).
  2. In a Copilot CLI session run `/skills list`; confirm the four plugin-manager skills load despite skalary-specific `plugin.json` fields.

  **Rollback:** `copilot plugin uninstall plugin-manager`; `copilot plugin marketplace remove skalary`.

  </details>

## Phase 4: Bootstrap and repo auto-approval
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Update `scripts/skalary/bootstrap.ps1`: add `Set-ScriptApproval.ps1` to `$scriptFiles`; auto-install `plugin-manager` after the download (state that install clones the remote sources at the pinned `-Ref`, not the flat files; print the install plan first; then print usage next steps); offer `Set-ScriptApproval.ps1` for `plugin-manager`'s **read-only** scripts only (prompt or `-AutoApprove` switch) (REQ-4, REQ-12, RISK-3, RISK-9) [after: 2.3] `M`
- [ ] 4.2 Run `Set-ScriptApproval.ps1 -All` on this repo to auto-approve the read-only bundled scripts of every plugin (incl. `plugin-manager`); verify `.vscode/settings.json` stays valid JSONC with prior keys + comments intact and mutating scripts excluded (REQ-13, RISK-6) [after: 2.3] `S`

## Phase 5: Evals
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Complete the four structural evals (`.Tests.ps1`) — frontmatter/required-keys/body/link checks per skill, plus assertions that `_Common.ps1` (and each skill's read-only scripts) are present in `registry.json` and the installed tree (REQ-3, REQ-7, REQ-11) [after: 2.3] `M`
- [ ] 5.2 Complete at least one LLM `.eval.json` per skill (install/uninstall/list/update scenarios with judge rubrics) validated by `Test-Evals.ps1` (REQ-7) [after: 2.2] `M`

## Phase 6: Docs
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Create `docs/design-notes/architecture/plugin-manager.design.md` (skills, dual catalog, read-only auto-approval opt-in flow); update `plugin-registry.design.md` (dual catalog, bootstrap auto-install + clone semantics, `.ps1` closure, `-RegistryPath` fallback, `.github/plugin/` dogfood ownership, `Set-ScriptApproval` contract) and `.design-notes.md` index; sync `README.md`/`registry.json` (REQ-10) [after: 3.3, 4.1, 4.2] `M`

## Finalization (conditional)

- [ ] 7.1 Run `scripts/validate.ps1` (registry + marketplace drift, bundle drift, schema) and `Test-Evals.ps1`; confirm zero drift, green structural evals, and that `.vscode/settings.json` is valid JSONC with mutating scripts excluded (REQ-1, REQ-5, REQ-7, REQ-11, REQ-13) @human `S`
