---
description: The repository's gate inventory — every gate CI runs, the three hosts a gate can live in, what each does when it fails, and the typed exclusions for the gates that deliberately do not run. Also the per-platform runtime budget contract. Load before editing CI workflows, scripts/validate.ps1, scripts/skalary/Run-UnitTests.ps1 or tools/suite-budget.psd1.
globs:
  - .github/workflows/**
  - scripts/validate.ps1
  - scripts/skalary/Run-UnitTests.ps1
  - tools/suite-budget.psd1
---

# CI Gates

`test:CiGates.InventoryMatchesWorkflow` reads the inventory below and the three hosts it names, and fails when a gate exists on one side only. The table is therefore the contract, not a description of one: a gate added to a workflow without a row here is as red as a row here with no invocation. The `validate.ps1` side is read from that script's syntax tree — a path surviving in a comment is not an invocation, and an assignment whose call site was deleted is not a gate.

## Gate inventory

`Invocation` is a regex matched against the host named in `Runs in`. `Enforcement` is `blocking` when the gate's exit code is the job's verdict, `support` for a step that is not a gate, and `advisory`/`excluded` only with a typed `exclusion:` id from the table below it. `Enforcement` says how the verdict is reported, not *when* it can stop a change: it is a per-step property, so a post-merge gate is `blocking` in exactly the same sense as a pre-merge one. The vocabulary has no column for the triggering event, so the three container rows state their event scope in `Proves` — they run on `push` to `main` and can never gate a pull request, and a reader who took `blocking` to mean merge-blocking would have that backwards.

| Gate | Proves | Runs in | Invocation | Enforcement |
|---|---|---|---|---|
| `gate:script-analyzer` | `scripts/skalary` carries no `Error`-severity analyzer finding; `Warning` findings are counted and printed, not enforced (`exclusion:analyzer-warnings-not-blocking`) | `.github/workflows/registry-ci.yml` | `Invoke-ScriptAnalyzer` | blocking |
| `support:suite-budget-clock` | the budget spans the whole `npm test` command rather than the Pester leg | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1[^\r\n]*-StartBudgetClock` | support |
| `gate:plan-validation` | every plan at or above `drafted` satisfies its own contract | `.github/workflows/registry-ci.yml` | `scripts/skalary/Validate-Plan\.ps1` | blocking |
| `gate:repository-validation` | every payload file parses, and the gates below run | `.github/workflows/registry-ci.yml` | `scripts/validate\.ps1` | blocking |
| `gate:plugin-retirement-history` | published plugin retirement records are never changed or removed; the event supplies one explicit Git baseline | `.github/workflows/registry-ci.yml` | `scripts/skalary/Invoke-PluginRetirementHistoryGate\.ps1` | blocking |
| `gate:unit-suite` | the Pester suite passes and the run is inside its platform's ceiling | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1(?![^\r\n]*-StartBudgetClock)` | blocking |
| `gate:registry-validation` | `registry.json` matches the plugin sources it claims to describe | `.github/workflows/registry-ci.yml` | `scripts/skalary/Test-Registry\.ps1` | blocking |
| `gate:dogfood-drift` | the repo's own installed copies match `plugins/` | `.github/workflows/registry-ci.yml` | `scripts/skalary/Sync-Dogfood\.ps1` | blocking |
| `gate:generated-output-drift` | `registry.json` and `README.md` are what the generator produces now | `.github/workflows/registry-ci.yml` | `scripts/skalary/Build-Registry\.ps1` | blocking |
| `gate:container-relevance` | on `push` to `main` only, after merge: every unusable comparison base forces image relevance and every relevant image input reaches the image job | `.github/workflows/autopilot-container-ci.yml` | `Invoke-ContainerToolchainGate\.ps1[^\r\n]*-Mode Detect` | blocking |
| `gate:container-image` | on `push` to `main` only, after merge: the candidate payload builds and its bounded smoke contract passes; comparable base work remains advisory | `.github/workflows/autopilot-container-ci.yml` | `Invoke-ContainerToolchainGate\.ps1[^\r\n]*-Mode Measure` | blocking |
| `gate:container-result` | on `push` to `main` only, after merge: detector/image conclusions satisfy only the closed irrelevant/skipped or relevant/success truth table | `.github/workflows/autopilot-container-ci.yml` | `Invoke-ContainerToolchainGate\.ps1[^\r\n]*-Mode VerifyResult` | blocking |
| `gate:plugin-script-bundles` | bundled plugin scripts match `scripts/skalary` | `scripts/validate.ps1` | `scripts/skalary/Sync-PluginScripts\.ps1` | blocking |
| `gate:marketplace-drift` | `.github/plugin/marketplace.json` matches `plugins/` | `scripts/validate.ps1` | `scripts/skalary/Build-Marketplace\.ps1` | blocking |
| `gate:model-allowlist` | every agent declares a model from `tools/model-allowlist.psd1` | `scripts/validate.ps1` | `scripts/skalary/Test-ModelAllowlist\.ps1` | blocking |
| `gate:skill-size` | no `SKILL.md` exceeds the size cap | `scripts/validate.ps1` | `scripts/skalary/Test-SkillSize\.ps1` | blocking |
| `gate:plan-draft-validation` | every plan passes `Test-Plan` at `Draft` stage | `scripts/validate.ps1` | `scripts/skalary/Test-Plan\.ps1` | blocking |
| `gate:arch-doc-freshness` | the architecture human doc is not stale | `scripts/validate.ps1` | `scripts/skalary/Test-ArchDocFreshness\.ps1` | blocking |
| `gate:architecture-contract-integrity` | every architecture contract matches the closed schema and every locked contract matches its canonical content digest | `scripts/validate.ps1` | `scripts/skalary/Test-ArchitectureContractIntegrity\.ps1` | blocking |
| `gate:llm-eval` | the waza LLM eval tier | — | — | excluded · `exclusion:llm-eval-tier` |

### Exclusions

| Exclusion | Decided by | Why |
|---|---|---|
| `exclusion:analyzer-warnings-not-blocking` | plan `768d7b` step 9.2, narrowed 2026-08-06 | The step no longer merely reports: it separates severities and throws on any `Error`, so the gate can go red (`test:Ci.LintStepCanFail`). What remains excluded is the **warning** tier. Measured 2026-08-05: 472 findings over `scripts/skalary`, all `Warning`, 0 `Error` — 344 `PSUseConsistentWhitespace` and 115 `PSUseConsistentIndentation`. Enforcing those is a repo-wide formatting change and its own plan; the count is recorded so the debt is a number rather than an impression |
| `exclusion:llm-eval-tier` | plan `005` REQ-12, RISK-3 | The LLM tier needs a model token and returns a judged verdict, not a deterministic one. `npm run eval:llm` stays operator-invoked; the structural eval tier runs inside `gate:unit-suite` as ordinary Pester files under `tests/evals/` |

## Three hosts, one reason

A gate runs from `registry-ci.yml` when its failure is worth its own red step, from `autopilot-container-ci.yml` when it belongs to the conditional Docker trust boundary, and from `validate.ps1` when it is one of a set whose verdicts are collected and reported together. `validate.ps1` accumulates its errors and reports them in one list rather than exiting at the first, so a run tells the reader everything that is wrong; workflows do the opposite, because a step that failed and a step that never ran must stay distinguishable (RISK-10).

That is why `registry-ci.yml` gives every gate its own named step and never chains two into one script, and why the drift gates carry their enforcing command rather than only their generator: `Build-Registry.ps1` alone rewrites the catalog and reports success — `git diff --exit-code` is the gate. Same shape for `Sync-Dogfood.ps1 -WhatIf`: a sync that writes cannot also detect drift.

`autopilot-container-ci.yml` is deliberately split into detector, image, and final jobs. Universal inventory rules recognize every `Invoke-ContainerToolchainGate.ps1 -Mode ...` call; registry-specific rules continue to recognize ordinary repository scripts, npm, analyzer, and drift commands only in `registry-ci.yml`; container-specific rules require `Detect`, `Measure`, and `VerifyResult` each in exactly one job and in no other. `-Mode Initialize` is excluded because it writes a placeholder receipt and asserts nothing — it is setup, and it deliberately appears in two jobs. Stating ownership in both directions matters: a rule that only checked "the image job runs Measure" would stay green with Measure *also* running in the five-minute detector job.

### The container gate is post-merge, because a pull request cannot gate itself

On `pull_request`, GitHub reads the workflow definition from the pull request's own head. The file that describes the trust boundary is therefore written by the same author as the code it is supposed to contain: a candidate can delete the boundary, or the entire job, and the required check still reports success, because a required check's identity is a name and not a behaviour. An earlier revision of this gate tried to close that by executing the runner from a base-SHA checkout in a directory called `control/`. It does not close it — the candidate's own YAML decides whether that checkout step runs at all, so the "trusted control plane" was a convention the untrusted party was asked to observe.

GitHub does have a mechanism where the definition is not candidate-controlled — organization-level required workflows, whose definition lives outside the repository. This repository has none configured, so it is not available to rely on. What remains true is that a `push` to `main` runs the definition at the merged commit, which a human has already reviewed and accepted. So this gate triggers on `push` to `main` only. Its verdict is about merged `main`, and the design does not claim it blocks a pull request; the claim it *can* support is that a regression in the image is visible on `main`, attributably, within one run.

Two consequences are recorded rather than hidden. Merged code is measured after it is merged, so a bad merge is caught rather than prevented — human review of the Dockerfile diff is the only pre-merge control. And `concurrency` does not cancel in progress, with a group keyed on `github.sha` rather than the ref: every merged commit gets its own verdict, because cancelling commit A's run when commit B lands leaves A merged and unmeasured — and a ref-keyed group would do the same thing more quietly, since GitHub keeps only one *pending* run per group and would drop the middle of three commits that land during one image job. A red run is announced by a `notify` job that opens one repository issue per failing commit; that job carries `issues: write` and is the sole exception to every other job holding `contents: read`, which it earns by holding no checkout and running no gate code. The response procedure lives in the architecture note's "The gate is red on `main`" section.

### Workflow assertions read a parse, not a split

`tests/CiWorkflow.psm1` parses a strict block-YAML subset (mappings, sequences, block scalars, flow scalars) and throws on anchors, aliases, flow collections, multiple documents, tabs, and duplicate keys. Step boundaries used to come from splitting on `- name:`, which cannot distinguish a step from that same text inside a `run:` block scalar — and it silently gave the last step of a job a body that ran into the next job. Every step and job body still carries the raw committed text, minus comment lines, so assertions describe what is actually in the file; only the boundaries and the structure come from the parse. `test:Ci.WorkflowYamlParserIsStrict` proves the decoy case and that the repository's own workflows stay inside the subset.

## The budget contract

`Run-UnitTests.ps1` is the only place the runtime ceiling is checked, which is why CI invokes it rather than `Invoke-Pester` (D2). The budget in `tools/suite-budget.psd1` is stated per platform, because the same suite measured 108.998s on `ubuntu-latest` and 223.142s on `windows-latest` (D13, D15).

| Property | Contract |
|---|---|
| Measured quantity | the whole `npm test` command, not the `test:unit` leg — the `pretest` hook starts a clock file, and this script is last in the chain and reads it |
| Unclocked run | reports a *lower bound* and says so; over budget on a subset is still over budget, under budget is not a verdict |
| Ceiling direction | `HardCeilingSeconds` may only fall. `BoundCeilingSeconds` is what any value is checked against |
| Escape hatch | one raise, to at most `AbsoluteCapSeconds`, with a justification in the plan's `assets/decisions.md`; a platform that still misses splits into tiers instead |
| Job timeout | per matrix leg, above that platform's ceiling — a job killed before the gate speaks reports a cancelled run, not an over-budget one |

Exit codes are the diagnosis, so they stay distinct: `1` tests failed, `2` Pester absent, `3` nothing discovered, `4` a test file never loaded, `5` over budget, `6` no budget for this platform. `2`–`4` are the REQ-5 contract — a gate that reports success having asserted nothing forges evidence, since this script is also the `test:` evidence executor.

## Constraints

- **No `continue-on-error` on a gate, and no gate failure that a later statement can mask.** `registry-ci.yml` permits none. The container workflow permits it only where the failure means *less* comparison rather than a weaker check: the optional event-base checkout, and the base-commit import that feeds it. Both degrade into a closed `base-unreachable`/`base-context-absent` reason, which forces relevance and a blocking candidate-only measurement — failing the job there would convert a comparison gap into an outage. The candidate checkout and all three runner gate invocations remain blocking. Each multi-statement runner step throws on a non-zero runner exit before producing any bounded output. `test:Ci.SeededFailureIsRed` executes the registry workflow's own unit-test command against a seeded failing tree and asserts its stricter last-statement shape.
- **No `Invoke-Pester` in the workflow.** It would be a second, unbudgeted way to run the suite that reports success having skipped the checks in `Run-UnitTests.ps1`.
- **Every gate step declares `shell: pwsh`.** The default shell differs by platform, so an undeclared one runs the two legs through different interpreters.
- **Actions pinned by SHA, modules by exact NuGet range, with `-AuthenticodeCheck` where the platform honours it.** Dropping `-SkipPublisherCheck` restores a check only if one still runs; PSResourceGet verifies nothing unless asked (RISK-8).
- **Ordering in generated catalogs is ordinal, never culture-aware.** `cs-CZ` sorts `ch` after `c`, so a culture-aware sort makes `gate:generated-output-drift` fail for everyone whose locale differs from the last person to run the generator.
- **`validate.ps1` enumerates payload roots by allowlist, canonicalised, refusing reparse points.** `-Recurse` without `-Force` hides dot-prefixed entries on Linux only, so the two legs passed over different file sets; `-Force` alone reaches `.git` and `node_modules` (REQ-8, RISK-5).
