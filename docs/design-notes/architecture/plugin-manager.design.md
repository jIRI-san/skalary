---
description: Plugin-manager plugin — the four install/uninstall/list/update skills, the dual (skalary + Copilot CLI) install surfaces, and the opt-in read-only terminal auto-approval flow. Load when changing plugin-manager skills, Set-ScriptApproval, bootstrap install, or the marketplace generator.
globs:
  - plugins/plugin-manager/**
  - scripts/skalary/Set-ScriptApproval.ps1
  - scripts/skalary/Build-Marketplace.ps1
  - schemas/marketplace/marketplace.schema.json
  - .github/plugin/**
---

# Plugin Manager

`plugin-manager` is a meta-plugin: four user-invocable skills that wrap the existing `scripts/skalary` plugin scripts. It ships no new install logic — the skills are thin orchestration over `Install-Plugin.ps1`, `Remove-Plugin.ps1`, `Update-Plugin.ps1`, `Find-Plugin.ps1`, `Get-Plugin.ps1`, and `Set-ScriptApproval.ps1`.

| Skill | Wraps | Notes |
|---|---|---|
| `install-plugin` | `Install-Plugin.ps1` + `Set-ScriptApproval.ps1` | Installs (default `jIRI-san/skalary@main`), then offers opt-in read-only approval. |
| `uninstall-plugin` | `Remove-Plugin.ps1` + `Set-ScriptApproval.ps1 -Remove` | Removes approval entries **before** deleting payload; self/dependent guard. |
| `list-plugins` | `Get-Plugin.ps1` + `Find-Plugin.ps1` | Read-only; available + installed + search. |
| `update-plugin` | `Update-Plugin.ps1` | Version bump with modified-file preservation. |

## Direct-invocation contract (non-obvious)

Skills invoke bundled scripts **directly** by installed path — `​.github/skills/<skill>/scripts/<Script>.ps1 -RepoRoot .` — and never via `pwsh -NoProfile -File`. Rationale: VS Code's `chat.tools.terminal.autoApprove` **prefix-matches** each sub-command, so wrapping the script in `pwsh -File …` makes the command prefix `pwsh`, which no approval key matches. Direct invocation makes the command prefix equal the script path, which is what the plain-string approval key matches. `-RepoRoot .` is mandatory so `Resolve-RepoRoot` anchors on the consuming repo, not the bundle folder.

Predefined install/update/remove choices follow the shared host-equivalent contract: the same option
labels and context in VS Code and Copilot CLI, with `effort: <1-10>` and `complexity: <1-10>` on every
option. The CLI renders a numbered list rather than depending on the VS Code picker.

## Dual install surfaces

The same `plugins/*/plugin.json` sources feed two independent catalogs; neither depends on the other.

| Surface | Catalog | Install target | Consumer |
|---|---|---|---|
| skalary | `registry.json` (root) | committed `.github/` via `Install-Plugin.ps1` | VS Code Copilot (project-scoped skills) |
| Copilot CLI | `.github/plugin/marketplace.json` (generated) | `~/.copilot/installed-plugins/` via `copilot plugin install` | Copilot CLI (user-scoped) |

`Build-Marketplace.ps1` generates `marketplace.json` from every `plugins/<name>/plugin.json`, emitting `source: plugins/<name>` and `strict: false`. The `strict:false` is deliberate: Copilot CLI reads the **same shared** `plugin.json` that carries skalary-only fields (`files`/`dependencies`/`status`/`evals`); the 2026-07-05 spike confirmed `copilot plugin install ./plugins/plugin-manager` accepts it and loads all four skills, and `strict:false` keeps marketplace-entry validation relaxed as a safeguard. Direct `copilot plugin install <path>` is deprecated by the CLI, so the marketplace route (`<name>@skalary`) is the supported path.

`.github/plugin/marketplace.json` is **generator-owned**, not a plugin payload. `Sync-Dogfood.ps1` is copy-only (writes exactly each plugin's `files[]`, never prunes), so it leaves the generated catalog untouched — no drift conflict. `validate.ps1` gates it via `Build-Marketplace.ps1 -WhatIf`.

## Read-only terminal auto-approval

`Set-ScriptApproval.ps1` merges/removes `chat.tools.terminal.autoApprove` keys in `.vscode/settings.json`. It is deliberately narrow:

| Guard | Rule |
|---|---|
| Verb allowlist | Only `Get`/`Find`/`Test`/`Validate` scripts (read-only). `Install`/`Uninstall`/`Update`/`Remove`/`Set`/`bootstrap` are never approved, so a prompt-injected `-Repository`/`-Ref`/`-Source` cannot ride an approval into a silent remote install. |
| Review-writer exception | Exactly two anchored, object-valued `matchCommandLine` rules admit the installed CR/DR `Build-ReviewReport.ps1` with only `-Mode Freeze\|Publish`, a lowercase UUID, and optional confined legacy, unprefixed-hash, or prefixed-hash plan directory in fixed order. The broad script-prefix boolean is forbidden; add/remove owns these rules with the plugin. Approval authorizes only that command shape—it does not provision the writer's PowerShell 7.6+ prerequisite. |
| Historical-context exclusion | `Get-PlanArtifactConsumerContext.ps1` and its sibling resolver are never auto-approved. The adapter executes an installed resolver/module closure whose bytes are not cryptographically bound at invocation time; approving the adapter command would therefore transitively approve replaceable sibling code. |
| Sensitive-name deny-list | A script whose name contains `credential`/`secret`/`token`/`password`/`passphrase` is never approved even if its verb is read-only (e.g. `get-credential.ps1`). |
| Key shape | Plain path string (`.github/skills/<skill>/scripts/<Script>.ps1`), matching the existing settings convention. VS Code prefix-matches it per sub-command, so a chained `<script> ; curl … | sh` still prompts (the second sub-command matches no key). |
| Confinement | Keys are resolved from registry `files[]`, confined to `.github/`, and only written for scripts that exist on disk. |
| JSONC safety | The writer preserves comments and trailing commas via a comment-aware brace scan; it never round-trips through `ConvertTo-Json` (which would drop comments). |

`-All` batches every plugin's read-only scripts plus the two closed review-writer exceptions;
`-Remove` drops a plugin's keys (uninstall runs it first, while the files still resolve). Approval is
always opt-in — the `install-plugin` skill asks via `vscode_askQuestions` and lists each approvable
entry before writing. Object-valued entries are stored on one JSONC line so the comment-preserving
add/remove parser can treat one rule atomically.

Dogfood settings are generated through the same writer. All planning/review consumer adapters and
their sibling resolvers remain unapproved despite their `Get-` names. The writer also removes obsolete
plain-path and anchored historical-context entries from earlier versions.

## Bootstrap flow

`bootstrap.ps1` downloads the flat `scripts/skalary` set (now including `Set-ScriptApproval.ps1`) + `registry.json`, then runs `Install-Plugin.ps1 -Name plugin-manager` — which **clones the pinned `-Ref`** and copies payload only (no code execution). It offers read-only approval via an opt-in `-AutoApprove` switch (bootstrap is non-interactive). Net flow: bootstrap → plugin-manager installed → user manages every other plugin through the skills.

## Bundling coupling

The skills bundle their wrapped scripts. `Sync-PluginScripts.ps1` follows `.ps1` dot-source closures (its `Get-ModuleClosure` regex matches `\.psm?1` with a leading `[A-Za-z0-9_]` so `_Common.ps1` is pulled in) but never edits `files[]` — so every co-bundled script (`_Common.ps1` + the wrapped scripts) is enumerated explicitly in `plugin.json`. A stale bundle fails the `Sync-PluginScripts.ps1 -WhatIf` drift gate in `validate.ps1`.

See [plugin-registry.design.md](./plugin-registry.design.md) for the underlying install/receipt/confinement model and the `-RegistryPath` fallback that lets `list`/`uninstall` work in a bootstrapped repo without a root `registry.json`.
