---
name: install-plugin
description: 'Install a skalary plugin (and its dependencies) into this repo''s .github/, then optionally auto-approve its read-only scripts.'
argument-hint: 'Plugin name (optionally: repository, ref, or local source path)'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Install Plugin

> Agent mode. Copies plugin payload into `.github/` and can edit `.vscode/settings.json`.

> **Interaction rule:** every multiple-choice prompt uses `vscode_askQuestions` with `options`.

## Step 1: Resolve the plugin and source

1. Determine the plugin `<name>` from the user's argument. If it is missing, ask for it (run `/list-plugins` first to browse).
2. Default the source to `jIRI-san/skalary@main`. The user may override with a repository (`<owner>/<repo>`), a `<ref>`, or a local `-Source` path.

## Step 2: Install

Run the bundled installer **directly** (do not wrap with `pwsh -File` — direct invocation keeps terminal auto-approval working) and always pass `-RepoRoot .` so the consuming repo is targeted:

```
.github/skills/install-plugin/scripts/Install-Plugin.ps1 -Name <name> -RepoRoot . -Repository jIRI-san/skalary -Ref main
```

- For a local checkout, pass `-Source <path>` instead of `-Repository`/`-Ref`.
- Install resolves dependencies in topological order and applies transactionally; on any failure it rolls back and writes no receipt. Surface the script's output verbatim.

## Step 3: Offer read-only auto-approval

1. List the newly-installed plugin's **read-only** scripts (verbs `Get`/`Find`/`Test`/`Validate`) and, for each, its skill and a one-line description of its function.
2. Ask with `vscode_askQuestions` (options **Yes** / **No**): "Auto-approve these read-only scripts in `.vscode/settings.json` so they run without a prompt each time?"
3. On **Yes**, run:

```
.github/skills/install-plugin/scripts/Set-ScriptApproval.ps1 -Name <name> -RepoRoot .
```

   Only read-only scripts are ever approved — install/uninstall/update/remove stay gated behind a per-run prompt. Report the post-write diff the script prints.

## Step 4: Confirm

Confirm the receipt exists at `.github/.skalary/receipts/<name>.json` and print any next steps (for example, the new skills the plugin provides).
