---
name: skalary-config
description: "Discover Skalary configuration surfaces, their authorities, and safe read-only state. Use to inspect effective settings, validation availability, current diffs, or a mutation preview."
argument-hint: "Optional: show|validate|diff|preview plus a category"
user-invocable: true
disable-model-invocation: true
context: fork
---

# Skalary configuration

Read [the configuration catalog](./assets/catalog.md) to identify the accepted category. The catalog is
descriptive; it does not authorize paths or define executable behavior.

Run the installed read-only command directly, with one category:

```powershell
.github/skills/skalary-config/scripts/Read-SkalaryConfig.ps1 -Action show -Category autopilot -RepoRoot .
```

Available actions are `show`, `validate`, `diff`, and `preview`. `preview` does not create or edit a
file; it reports a category-scoped, secret-redacted empty proposal and digest for the later Apply flow.
Pass a previous `-ExpectedDigest` to detect source changes before continuing.

Accepted categories are `autopilot`, `models-reviews`, `local-review-standards`,
`terminal-approvals`, `evals`, `design-architecture`, `plugin-distribution`, and
`repository-toolchain`. Unsupported surfaces are not guessed.

Do not provide credential values, arbitrary paths, or generated paths. Credential state is
availability-only; generated registry, marketplace, README, dogfood, receipts, plans, and workflows
are not configuration write targets.
