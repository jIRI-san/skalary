---
name: uninstall-plugin
description: 'Uninstall a skalary plugin from this repo, cleaning up its auto-approve entries and guarding against removing a plugin others depend on.'
argument-hint: 'Plugin name'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Uninstall Plugin

> Agent mode. Removes plugin payload from `.github/` and can edit `.vscode/settings.json`.

> **Interaction rule:** every multiple-choice prompt uses `vscode_askQuestions` with `options`.

## Step 1: Resolve the plugin

1. Determine `<name>` from the user's argument; if missing, ask (run `/list-plugins -Installed` first to browse installed plugins).
2. **Self-removal guard:** if `<name>` is `plugin-manager`, warn that removing it also removes the `install-plugin` / `uninstall-plugin` / `list-plugins` / `update-plugin` skills themselves. Confirm with `vscode_askQuestions` (**Proceed** / **Cancel**) before continuing.

## Step 2: Remove auto-approve entries first

Run this **before** removing the payload, while the plugin's scripts still exist on disk so they can be resolved:

```
.github/skills/uninstall-plugin/scripts/Set-ScriptApproval.ps1 -Name <name> -RepoRoot . -Remove
```

This drops the plugin's read-only keys from `.vscode/settings.json` (a no-op if there are none).

## Step 3: Uninstall

```
.github/skills/uninstall-plugin/scripts/Remove-Plugin.ps1 -Name <name> -RepoRoot .
```

- The remover **refuses** if another installed plugin depends on `<name>`; it lists the dependent plugin(s). Surface that message and stop — only pass `-Force` if the user explicitly confirms after seeing the dependents.
- Locally-modified installed files are preserved unless the user confirms `-Force`.

## Step 4: Confirm

Confirm the receipt `.github/.skalary/receipts/<name>.json` is gone and report exactly what was removed (and any files skipped as modified).
