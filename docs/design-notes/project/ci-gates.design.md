---
description: The repository's gate inventory — every gate CI runs, the two hosts a gate can live in, what each does when it fails, and the typed exclusions for the gates that deliberately do not run. Also the per-platform runtime budget and tracked-input fingerprint contract.
globs:
  - .github/workflows/**
  - scripts/validate.ps1
  - scripts/skalary/Run-UnitTests.ps1
  - scripts/skalary/{Get-SuiteInputFingerprint,Measure-SuiteRuntime}.ps1
  - tools/suite-budget.psd1
  - tools/suite-runtime.json
---

# CI Gates

`test:CiGates.InventoryMatchesWorkflow` reads the inventory below and the two hosts it names, and fails when a gate exists on one side only. The table is therefore the contract, not a description of one: a gate added to the workflow without a row here is as red as a row here with no invocation. The `validate.ps1` side is read from that script's syntax tree — a path surviving in a comment is not an invocation, and an assignment whose call site was deleted is not a gate.

## Gate inventory

`Invocation` is a regex matched against the host named in `Runs in`. `Enforcement` is `blocking` when the gate's exit code is the job's verdict, `support` for a step that is not a gate, and `advisory`/`excluded` only with a typed `exclusion:` id from the table below it.

| Gate | Proves | Runs in | Invocation | Enforcement |
|---|---|---|---|---|
| `gate:script-analyzer` | `scripts/skalary` carries no `Error`-severity analyzer finding; `Warning` findings are counted and printed, not enforced (`exclusion:analyzer-warnings-not-blocking`) | `.github/workflows/registry-ci.yml` | `Invoke-ScriptAnalyzer` | blocking |
| `support:suite-budget-clock` | the budget spans the whole `npm test` command rather than the Pester leg | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1[^\r\n]*-StartBudgetClock` | support |
| `gate:plan-validation` | every plan at or above `drafted` satisfies its own contract | `.github/workflows/registry-ci.yml` | `scripts/skalary/Validate-Plan\.ps1` | blocking |
| `gate:repository-validation` | every payload file parses, and the six gates below run | `.github/workflows/registry-ci.yml` | `scripts/validate\.ps1` | blocking |
| `gate:unit-suite` | the Pester suite passes and the run is inside its platform's ceiling | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1(?![^\r\n]*-StartBudgetClock)` | blocking |
| `gate:registry-validation` | `registry.json` matches the plugin sources it claims to describe | `.github/workflows/registry-ci.yml` | `scripts/skalary/Test-Registry\.ps1` | blocking |
| `gate:dogfood-drift` | the repo's own installed copies match `plugins/` | `.github/workflows/registry-ci.yml` | `scripts/skalary/Sync-Dogfood\.ps1` | blocking |
| `gate:generated-output-drift` | `registry.json` and `README.md` are what the generator produces now | `.github/workflows/registry-ci.yml` | `scripts/skalary/Build-Registry\.ps1` | blocking |
| `gate:plugin-script-bundles` | bundled plugin scripts match `scripts/skalary` | `scripts/validate.ps1` | `scripts/skalary/Sync-PluginScripts\.ps1` | blocking |
| `gate:marketplace-drift` | `.github/plugin/marketplace.json` matches `plugins/` | `scripts/validate.ps1` | `scripts/skalary/Build-Marketplace\.ps1` | blocking |
| `gate:model-allowlist` | every agent declares a model from `tools/model-allowlist.psd1` | `scripts/validate.ps1` | `scripts/skalary/Test-ModelAllowlist\.ps1` | blocking |
| `gate:skill-size` | no `SKILL.md` exceeds the size cap | `scripts/validate.ps1` | `scripts/skalary/Test-SkillSize\.ps1` | blocking |
| `gate:plan-draft-validation` | every plan passes `Test-Plan` at `Draft` stage | `scripts/validate.ps1` | `scripts/skalary/Test-Plan\.ps1` | blocking |
| `gate:arch-doc-freshness` | the architecture human doc is not stale | `scripts/validate.ps1` | `scripts/skalary/Test-ArchDocFreshness\.ps1` | blocking |
| `gate:llm-eval` | the waza LLM eval tier | — | — | excluded · `exclusion:llm-eval-tier` |
| `gate:architecture-tests` | `arch:` receipts against architecture contracts | — | — | excluded · `exclusion:arch-tier-not-seeded` |

### Exclusions

| Exclusion | Decided by | Why |
|---|---|---|
| `exclusion:analyzer-warnings-not-blocking` | plan `768d7b` step 9.2, narrowed 2026-08-06 | The step no longer merely reports: it separates severities and throws on any `Error`, so the gate can go red (`test:Ci.LintStepCanFail`). What remains excluded is the **warning** tier. Measured 2026-08-05: 472 findings over `scripts/skalary`, all `Warning`, 0 `Error` — 344 `PSUseConsistentWhitespace` and 115 `PSUseConsistentIndentation`. Enforcing those is a repo-wide formatting change and its own plan; the count is recorded so the debt is a number rather than an impression |
| `exclusion:llm-eval-tier` | plan `005` REQ-12, RISK-3 | The LLM tier needs a model token and returns a judged verdict, not a deterministic one. `npm run eval:llm` stays operator-invoked. Offline waza-shape guards under `tests/evals/` run inside `gate:unit-suite`; plugin Tier-1 evals under `plugins/*/evals/*.Tests.ps1` remain the separate `npm run eval` path and are not a `validate.ps1` gate. |
| `exclusion:arch-tier-not-seeded` | plan `768d7b` decision D11 | `docs/architecture-notes/receipts/` and `arch-test-config.json` do not exist, so an `arch:` gate would assert against an unminted tier. `gate:arch-doc-freshness` covers the part of that tier which does exist |

## Two hosts, one reason

A gate runs from `registry-ci.yml` when its failure is worth its own red step, and from `validate.ps1` when it is one of a set whose verdicts are collected and reported together. `validate.ps1` accumulates its errors and reports them in one list rather than exiting at the first, so a run tells the reader everything that is wrong; the workflow does the opposite, because a step that failed and a step that never ran must stay distinguishable (RISK-10).

That is why `registry-ci.yml` gives every gate its own named step and never chains two into one script, and why the drift gates carry their enforcing command rather than only their generator: `Build-Registry.ps1` alone rewrites the catalog and reports success — `git diff --exit-code` is the gate. Same shape for `Sync-Dogfood.ps1 -WhatIf`: a sync that writes cannot also detect drift.

## The budget contract

`Run-UnitTests.ps1` is the only place the runtime ceiling is checked, which is why CI invokes it rather than `Invoke-Pester` (D2). The budget in `tools/suite-budget.psd1` is stated per platform, because the same suite measured 108.998s on `ubuntu-latest` and 223.142s on `windows-latest` (D13, D15).

| Property | Contract |
|---|---|
| Measured quantity | the whole `npm test` command, not the `test:unit` leg — the `pretest` hook starts a clock file, and this script is last in the chain and reads it |
| Unclocked run | reports a *lower bound* and says so; over budget on a subset is still over budget, under budget is not a verdict |
| Ceiling direction | `HardCeilingSeconds` may only fall. `BoundCeilingSeconds` is what any value is checked against |
| Escape hatch | one raise, to at most `AbsoluteCapSeconds`, with a justification in the plan's `assets/decisions.md`; a platform that still misses splits into tiers instead |
| Job timeout | per matrix leg, above that platform's ceiling — a job killed before the gate speaks reports a cancelled run, not an over-budget one |
| Input identity | `Get-SuiteInputFingerprint.ps1` hashes the protocol tag plus each ordinal tracked regular path and its exact bytes with unsigned 64-bit big-endian length frames. The producer is included. Only `tools/suite-{profile,runtime}.json` and `testResults.xml` are excluded generated outputs. |
| Ordinary freshness | The current platform's runtime row must carry the current fingerprint and protocol. A stale/missing row exits `8`; another platform is checked by its own runner and refreshed before final approval. |
| Measurement freshness | `Measure-SuiteRuntime.ps1` computes the fingerprint before launching `npm test`, gives that child tree a process-only token containing the protocol, fingerprint, random nonce, measurement parent PID, and HMAC under a process-local random key, and recomputes after success. `pretest` validates the token, atomically claims its nonce once, and binds that nonce into the repo-scoped budget clock; the final runner consumes that clock and requires the same nonce. Re-running `pretest` with the token hits the claim tombstone and fails, so clock recreation cannot replay it. The gate also validates closed fields, HMAC, fingerprint, and live ancestry; invalid authorization exits `9`. A valid token permits stale or absent rows only for that measured run and never bypasses the elapsed-time ceiling. |
| Row publication | Successful measurement emits/writes a `suite-runtime-row@2` candidate carrying the fingerprint. Publication retires rows for older fingerprints, so they cannot masquerade as cross-platform evidence; later same-fingerprint imports compose the platform set. Import rejects failed, wrong-command, wrong-schema, or wrong-fingerprint rows. Generated row writes do not change the fingerprint. |

Exit codes are the diagnosis, so they stay distinct: `1` tests failed, `2` Pester absent,
`3` nothing discovered, `4` a test file never loaded, `5` over budget, `6` no budget for this
platform, `7` leaked environment, `8` stale measurement, and `9` invalid measurement
authorization. `2`–`4` are the REQ-5 contract — a gate that reports success having asserted
nothing forges evidence, since this script is also the `test:` evidence executor.

`MeasurementRecord` is mandatory. Omitting or emptying it exits `6`; a budget cannot disable
tracked-input freshness while retaining the runtime ceiling.

## Constraints

- **No `continue-on-error`, and no gate that is not the last statement in its step.** A gate followed by anything else reports that thing's exit code; `test:Ci.SeededFailureIsRed` executes the workflow's own unit-test command against a seeded failing tree and then asserts both properties textually.
- **No `Invoke-Pester` in the workflow.** It would be a second, unbudgeted way to run the suite that reports success having skipped the checks in `Run-UnitTests.ps1`.
- **Every gate step declares `shell: pwsh`.** The default shell differs by platform, so an undeclared one runs the two legs through different interpreters.
- **Actions pinned by SHA, modules by exact NuGet range, with `-AuthenticodeCheck` where the platform honours it.** Dropping `-SkipPublisherCheck` restores a check only if one still runs; PSResourceGet verifies nothing unless asked (RISK-8).
- **Ordering in generated catalogs is ordinal, never culture-aware.** `cs-CZ` sorts `ch` after `c`, so a culture-aware sort makes `gate:generated-output-drift` fail for everyone whose locale differs from the last person to run the generator.
- **`validate.ps1` enumerates payload roots by allowlist, canonicalised, refusing reparse points.** `-Recurse` without `-Force` hides dot-prefixed entries on Linux only, so the two legs passed over different file sets; `-Force` alone reaches `.git` and `node_modules` (REQ-8, RISK-5).
- **Cross-surface proofs compose existing gates.** `test:LearningLoop.PayloadOwnershipAndDrift`
  runs in the existing unit suite and cross-checks SI ownership, generated bundles, dogfood,
  manifests, versions, scaffolds, marketplace, and registry. Its companion plugin structural eval
  runs through `npm run eval`. Neither introduces a new workflow or `validate.ps1` gate; when a plan
  names the structural eval as `test:` evidence, that plan crosscheck executes the named Pester case
  and treats its result as blocking evidence.
