---
description: The repository's gate inventory — every gate CI runs, the three hosts a gate can live in, failure behavior, typed exclusions, tiered per-platform runtime budgets, and tracked-input fingerprint authorization. Load before editing CI workflows or suite gate scripts and metadata.
globs:
  - .github/workflows/**
  - scripts/validate.ps1
  - scripts/skalary/Run-UnitTests.ps1
  - scripts/skalary/{Get-SuiteInputFingerprint,Measure-SuiteRuntime}.ps1
  - scripts/skalary/Test-ReviewConsumerInstall.ps1
  - tools/suite-budget.psd1
  - tools/suite-runtime.json
  - tools/suite-tier.psd1
---

# CI Gates

`test:CiGates.InventoryMatchesWorkflow` reads the inventory below and the three hosts it names, and fails when a gate exists on one side only. The table is therefore the contract, not a description of one: a gate added to a workflow without a row here is as red as a row here with no invocation. The `validate.ps1` side is read from that script's syntax tree — a path surviving in a comment is not an invocation, and an assignment whose call site was deleted is not a gate.

## Gate inventory

`Invocation` is a regex matched against the host named in `Runs in`. `Enforcement` is `blocking` when the gate's exit code is the job's verdict, `support` for a step that is not a gate, and `advisory`/`excluded` only with a typed `exclusion:` id from the table below it. `Enforcement` says how the verdict is reported, not *when* it can stop a change: it is a per-step property, so a post-merge gate is `blocking` in exactly the same sense as a pre-merge one. The vocabulary has no column for the triggering event, so the three container rows state their event scope in `Proves` — they run on `push` to `main` and can never gate a pull request, and a reader who took `blocking` to mean merge-blocking would have that backwards.

| Gate | Proves | Runs in | Invocation | Enforcement |
|---|---|---|---|---|
| `gate:script-analyzer` | `scripts/skalary` carries no `Error`-severity analyzer finding; `Warning` findings are counted and printed, not enforced (`exclusion:analyzer-warnings-not-blocking`) | `.github/workflows/registry-ci.yml` | `Invoke-ScriptAnalyzer` | blocking |
| `gate:review-schema-capability` | this runner implements every JSON Schema keyword the review-run contract validates with, and says so in one bounded status object | `.github/workflows/registry-ci.yml` | `scripts/skalary/Test-ReviewSchemaCapability\.ps1` | blocking |
| `gate:structural-evals` | deterministic Tier-1 plugin evals pass, including exact once-only execution of every id in `tools/structural-eval-required.json` | `.github/workflows/registry-ci.yml` | `npm run eval` | blocking |
| `support:suite-budget-clock` | the budget spans the whole `npm test` command rather than the Pester leg | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1[^\r\n]*-StartBudgetClock` | support |
| `gate:plan-validation` | every plan at or above `drafted` satisfies its own contract | `.github/workflows/registry-ci.yml` | `scripts/skalary/Validate-Plan\.ps1` | blocking |
| `gate:repository-validation` | every payload file parses, and the gates below run | `.github/workflows/registry-ci.yml` | `scripts/validate\.ps1[^\r\n]*-FullRepository` | blocking |
| `gate:plugin-retirement-history` | published plugin retirement records are never changed or removed; the event supplies one explicit Git baseline | `.github/workflows/registry-ci.yml` | `scripts/skalary/Invoke-PluginRetirementHistoryGate\.ps1` | blocking |
| `gate:unit-suite` | the complete Fast Pester tier passes; runtime and measurement freshness are logged as advisory observations | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1[^\r\n]*-Tier Fast[^\r\n]*-FullRepository` | blocking |
| `gate:slow-suite` | every process-heavy deterministic integration test in the manifest-owned Slow tier passes through the same cannot-test, required-evidence, and environment-leak checks; runtime is advisory | `.github/workflows/registry-ci.yml` | `Run-UnitTests\.ps1[^\r\n]*-Tier Slow` | blocking |
| `gate:review-consumer-install` | isolated CR and DR installs execute the complete review-run CLI exit and artifact matrix without repository fallbacks | `.github/workflows/registry-ci.yml` | `Test-ReviewConsumerInstall\.ps1` | blocking |
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

`Run-UnitTests.ps1` is the single runtime reporting path, which is why CI invokes it rather than `Invoke-Pester` (D2). Runtime ceilings and measurement freshness are advisory: they remain visible in logs but never turn passing tests red. This temporary policy prevents repeated ten-minute measurement/fix loops during plan finalization; the testing infrastructure will be redesigned separately. The budget in `tools/suite-budget.psd1` remains stated per platform for comparable observations.

`scripts/validate.ps1` is deliberately full-scope only and refuses an omitted
`-FullRepository` switch. Package scripts and CI carry that switch explicitly; phase Fast guidance
forbids the command. This keeps "run validation" from silently expanding a focused phase check into
the repository-wide parser, integrity, drift, model, plan, and architecture sweep.

Plan `31a3ef` activates D13's reserved split after merged review-run coverage pushed Windows past the
recorded ceiling. `tools/suite-tier.psd1` is the sole Slow membership owner; complete Fast is its derived
complement, so new test files cannot disappear and start in Fast by default. Ordinary phase feedback
is a caller-selected subset of that complement and reports against a 60-second advisory ceiling. Omitting scope fails;
the complete complement requires `-FullRepository`. The dedicated review-consumer matrix remains
outside both tiers because it already has its own blocking runner. Both tiers use `Run-UnitTests.ps1`;
only complete Fast consumes the `npm test` budget clock, while Slow is a separate blocking step in both
matrix legs with its own NUnit report and manifest-owned runtime observation. `All` is diagnostic and unbudgeted.

| Property | Contract |
|---|---|
| Measured quantity | the whole `npm test` command, not the `test:unit` leg — the `pretest` hook starts a clock file, and this script is last in the chain and reads it |
| Tier ownership | `tools/suite-tier.psd1` owns Slow and dedicated files; complete Fast is every other discovered `*.Tests.ps1` file. Focused Fast accepts explicit `-TestPath` values; a Slow-owned file additionally requires `-TestName` or stable `-EvidenceTestId` filtering so its complete process-heavy file never runs accidentally |
| Focused feedback | focused Fast is the default mode, requires explicit test paths, and warns above `FastFocusedHardCeilingSeconds` (60s). Optional Pester full-name filters narrow within a file. Full Fast requires `-FullRepository` |
| Focused evidence output | `-EvidenceTestId` plus `-EvidenceResultPath` is a focused-Fast-only extension of the same runner, not another host. It binds exact leading `test:<id>` tokens, writes `skalary/evidence-test-results@1` with selected/executed counts and per-ID outcomes, and leaves every non-pass red. It cannot combine with `-TestName` or `-FullRepository`. Focused test inputs and evidence outputs are lexically repository-confined and every existing path component must be a regular non-link path; a missing output validates its nearest existing parent before creation and revalidates immediately before writing. |
| Slow enforcement | a separate blocking test step in each Linux/Windows matrix leg, through the same runner; no `continue-on-error`, separate NUnit evidence, and advisory `SlowHardCeilingSeconds` reporting |
| Unclocked run | reports a *lower bound* and says so; over budget on a subset is still over budget, under budget is not a verdict |
| Ceiling metadata | Historical `HardCeilingSeconds` and `BoundCeilingSeconds` values remain tracked for comparable reporting; they are not pass/fail thresholds |
| Historical escape hatch | Existing raise metadata and justification remain provenance only; no runtime observation blocks or requires a ceiling change |
| Job timeout | per matrix leg, above the Fast ceiling plus the manifest-declared Slow/setup scheduling allowances — a job killed before every gate speaks reports cancellation instead of verdicts |
| Input identity | `Get-SuiteInputFingerprint.ps1` hashes the protocol tag plus each ordinal tracked regular path and its exact bytes with unsigned 64-bit big-endian length frames. The producer is included. Only `tools/suite-{profile,runtime}.json` and `testResults.xml` are excluded generated outputs. |
| Ordinary freshness | The current platform's runtime row is checked against the current fingerprint and protocol. A stale/missing row emits `StaleMeasurement` as a warning and does not affect the test verdict. |
| Measurement freshness | `Measure-SuiteRuntime.ps1` computes the fingerprint before launching the selected Fast or Slow command, gives that child tree a process-only token containing the protocol, fingerprint, random nonce, measurement parent PID, and HMAC under a process-local random key, and recomputes after success. Fast `pretest` validates the token, atomically claims its nonce once, and binds that nonce into the repo-scoped budget clock; the final Fast runner consumes that clock and requires the same nonce. Re-running `pretest` with the token hits the claim tombstone and fails, so clock recreation cannot replay it. Closed fields, HMAC, fingerprint, and live ancestry still protect an explicitly requested measurement; invalid authorization exits `11`. Elapsed time remains advisory. |
| Row publication | Successful measurement emits/writes a `suite-runtime-row@2` candidate carrying the fingerprint. Publication retires rows for older fingerprints, so they cannot masquerade as cross-platform evidence; later same-fingerprint imports compose the platform set. Import rejects failed, wrong-command, wrong-schema, or wrong-fingerprint rows. Generated row writes do not change the fingerprint. |
| Measurement receipt | Rows record non-empty OS/PowerShell/Pester/processor identity, HEAD commit, source, exact tracked-input fingerprint, and protocol. Failed runs are emitted but never recorded. Ordered dictionaries are canonicalized by keys, never through `PSObject.Properties` metadata. |

`tests/autopilot/EpicAutopilot.Tests.ps1` is Slow-owned because it creates many Git repositories
and child PowerShell processes. Stable `test:EpicAutopilot.*` evidence IDs remain admissible through
focused Fast selection, which executes only the named case and emits nonzero selected/executed counts.

`MeasurementRecord` remains the preferred observation source. Omitting it logs `BudgetNotDefined`
without changing a passing test verdict.

The isolated review-consumer matrix is a separate blocking gate rather than part of the ordinary
suite: it starts many child PowerShell processes to prove installed CLI exits and would consume about
half of the Windows unit-suite ceiling by itself. Splitting the host keeps that evidence mandatory on
both legs without making every local `npm test` pay the integration cost.
The gate host's `-TestPath` parameter is fixture-only executable evidence for its pass/fail exit
contract. The workflow is structurally forbidden from supplying it, so CI always runs the default
`ReviewConsumerInstall.Tests.ps1` matrix.

Exit codes `5`, `6`, and `10` are reserved: runtime overruns, missing advisory budget metadata, and stale measurements are warnings. Blocking diagnosis remains `1` tests failed, `2` Pester absent, `3` nothing discovered, `4` a test file never loaded, `7` leaked environment, `8` skipped required evidence, `9` invalid tier manifest, `11` invalid explicit measurement authorization, and `12` missing focused scope.
Environment-leak diagnostics identify each variable and only its transition category (`added`,
`removed`, or `changed`); snapshot values are never emitted because they may contain credentials.

## Constraints

- **No `continue-on-error` on a gate, and no gate failure that a later statement can mask.** `registry-ci.yml` permits none. The container workflow permits it only where the failure means *less* comparison rather than a weaker check: the optional event-base checkout, and the base-commit import that feeds it. Both degrade into a closed `base-unreachable`/`base-context-absent` reason, which forces relevance and a blocking candidate-only measurement — failing the job there would convert a comparison gap into an outage. The candidate checkout and all three runner gate invocations remain blocking. Each multi-statement runner step throws on a non-zero runner exit before producing any bounded output. `test:Ci.SeededFailureIsRed` executes the registry workflow's own unit-test command against a seeded failing tree and asserts its stricter last-statement shape.
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
