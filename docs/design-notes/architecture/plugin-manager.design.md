---
description: Plugin-manager skills, dual install surfaces, direct invocation, read-only approval, and bootstrap.
globs:
  - plugins/plugin-manager/**
  - scripts/skalary/{Set-ScriptApproval,Build-Marketplace}.ps1
  - schemas/marketplace/marketplace.schema.json
  - .github/plugin/**
---

# Plugin Manager

The four skills are thin orchestration over existing install/remove/update/find/get/approval scripts.

| Skill | Contract |
|---|---|
| `install-plugin` | Install (default `jIRI-san/skalary@main`), then offer opt-in read-only approval. |
| `uninstall-plugin` | Remove approvals before payload; retain self/dependent guard. |
| `list-plugins` | Read-only available, installed, and search views. |
| `update-plugin` | Explicit version update that replaces receipt-owned paths. |

Skills invoke installed scripts directly as
`.github/skills/<skill>/scripts/<Script>.ps1 -RepoRoot .`, never through `pwsh -File`. VS Code
auto-approval prefix-matches each subcommand, so a wrapper would match `pwsh`, not the approved script;
`-RepoRoot .` anchors resolution in the consumer. Predefined choices remain host-equivalent ordered
lists with context and 1–10 effort/complexity.

## Install surfaces

The same `plugin.json` sources independently feed skalary's root `registry.json` (committed `.github/`
project install) and Copilot CLI's generated `.github/plugin/marketplace.json`
(`~/.copilot/installed-plugins/`, installed as `<name>@skalary`). Marketplace entries use
`source: plugins/<name>` and `strict: false` because the shared manifest includes skalary fields.
See [plugin-registry.design.md](plugin-registry.design.md) for catalog generation, drift, dogfood,
receipt, confinement, and `-RegistryPath` behavior.

## Read-only approval

`Set-ScriptApproval.ps1` comment-safely merges/removes plain installed-path keys in
`.vscode/settings.json`.

| Guard | Rule |
|---|---|
| Eligibility | Only `Get`/`Find`/`Test`/`Validate`; mutating verbs and bootstrap never qualify. |
| Sensitive names | `credential`, `secret`, `token`, `password`, or `passphrase` always deny. |
| Confinement | Registry-declared `.github/` script must exist; chained unapproved subcommands still prompt. |
| JSONC | Preserve comments/trailing commas; keep object-valued exact rules atomic on one line. |

`-All` batches active eligible scripts; `-Remove` drops one plugin's keys before uninstall. Approval is
always opt-in and previews entries. Historical-context readers qualify as ordinary `Get-` scripts;
module dependencies need no separate keys. Rewrites remove obsolete earlier key shapes.

`bootstrap.ps1` downloads flat skalary scripts plus `registry.json`, installs `plugin-manager` from the
pinned ref without executing payload, and optionally applies non-interactive `-AutoApprove`.
Manifest-declared bundles explicitly enumerate every generated closure file; drift and completion order
are owned by [plugin-registry.design.md](plugin-registry.design.md).
