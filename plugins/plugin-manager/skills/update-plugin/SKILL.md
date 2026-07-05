---
name: update-plugin
description: 'Update an installed skalary plugin to the latest source version.'
argument-hint: 'Plugin name (optionally: repository or ref)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Update Plugin

> Agent mode. Refreshes an installed plugin's payload under `.github/`.

> **Interaction rule:** every multiple-choice prompt uses `vscode_askQuestions` with `options`.

## Step 1: Resolve the plugin

Determine `<name>` from the user's argument; if missing, run `/list-plugins -Installed` first or ask. Default the source to `jIRI-san/skalary@main`; the user may override the repository or ref.

## Step 2: Update

Run the bundled updater **directly** (not via `pwsh -File`) with `-RepoRoot .`:

```
.github/skills/update-plugin/scripts/Update-Plugin.ps1 -Name <name> -RepoRoot . -Repository jIRI-san/skalary -Ref main
```

- Update installs the resolved source snapshot transactionally and rolls back on any failure.
- Locally-modified installed files are preserved unless the user confirms `-Force` after being told which files differ.

## Step 3: Confirm

Report the version change (old to new) from the script output and list any files skipped as modified.
