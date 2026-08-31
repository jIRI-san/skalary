# Whole-tree test profile evidence

Collected: 2026-08-31

## Purpose

This evidence explains where the repository test runtime is spent. It is a
separate observation from the subsession totals in
[subsession-execution-statistics.md](subsession-execution-statistics.md): the
profile ran after orchestration and is not included in that document's 14h 13m
42.27s aggregate.

## Profile identity and method

| Property | Observed value |
| --- | --- |
| Source commit | `f6b8ec5bf27cf0c2407f106ade67cd4fe935d2d0` |
| Generated at | 2026-08-31 18:56:33 +02:00 |
| Host | Microsoft Windows 10.0.26200 |
| PowerShell | 7.6.5 |
| Pester | 5.7.1 |
| Logical processors | 16 |
| Scope | Every discovered `tests/**/*.Tests.ps1` file |
| Files | 114 |
| Tests | 1,251 |
| Execution shape | One instrumented Pester process over the complete tree |

The profiler collected Pester container and individual-test durations and
wrapped the plugin-registry operations already supported by
`Measure-SuiteProfile.ps1`. Tier attribution was reconstructed from
`tools/suite-tier.psd1`: its 28 explicit Slow files and one Dedicated file are
authoritative, and Fast is their derived complement.

This is a wall-clock profile, not CPU sampling. It identifies expensive test
containers, test cases, and selected wrapped operations. It cannot allocate
every second inside uninstrumented Git, PowerShell, Bash, filesystem, hashing,
or JSON calls.

## Run result

| Measure | Time or count |
| --- | ---: |
| Wall clock | 4,585.698s (76m 25.70s) |
| Pester duration | 4,584.726s (76m 24.73s) |
| Discovery | 4.379s |
| Test execution | 4,568.317s |
| Framework overhead | 12.029s |
| Passed | 1,226 |
| Failed | 4 |
| Skipped | 21 |
| Not run | 0 |

Discovery was 0.10% of wall time. Test execution was 99.62%. The delay is
therefore work performed by tests and their child tools, not test discovery or
Pester startup.

The individual-test durations sum to 4,486.2s. The remaining approximately
82.1s of the test-execution field belongs to setup/teardown and other
container-level work that Pester does not assign to one `It` block.

## Tier attribution

| Tier | Files | Tests | Container time | Share of Pester duration |
| --- | ---: | ---: | ---: | ---: |
| Fast | 85 | 884 | 2,437.59s (40m 37.59s) | 53.17% |
| Slow | 28 | 365 | 2,061.73s (34m 21.73s) | 44.97% |
| Dedicated | 1 | 2 | 85.41s (1m 25.41s) | 1.86% |

The derived Fast tier is the largest runtime contributor. Several files in it
exercise real repositories, subprocesses, transactional stores, or
maximum-boundary data. Classification alone does not reduce complete-suite
time, but these results show that "Fast" does not currently imply unit-scale
execution on Windows.

The observed Slow time exceeded its tracked 1,800-second advisory ceiling by
261.73s (4m 21.73s). Runtime observations are advisory under the current gate
contract and did not create the four failures below.

## Runtime concentration

### By file

| Set | Time | Share of Pester duration |
| --- | ---: | ---: |
| Slowest 5 files | 1,894.77s | 41.33% |
| Slowest 10 files | 2,794.77s | 60.96% |
| Slowest 20 files | 3,741.47s | 81.61% |
| Slowest 30 files | 4,170.97s | 90.98% |
| Slowest 40 files | 4,342.13s | 94.71% |
| Remaining 74 files | 242.60s | 5.29% |

### By individual test

Percentages use the 4,568.317-second test-execution field.

| Minimum duration | Test count | Combined time | Share of test execution |
| --- | ---: | ---: | ---: |
| 60s | 13 | 1,364.42s | 29.87% |
| 30s | 39 | 2,428.00s | 53.15% |
| 10s | 108 | 3,552.56s | 77.77% |
| 5s | 167 | 3,963.86s | 86.77% |
| 1s | 330 | 4,344.16s | 95.09% |

Only 39 of 1,251 tests account for more than half of execution time. A focused
optimization can therefore materially reduce the suite without rewriting most
tests.

## Slowest files

The table includes the slowest 40 files, which account for 94.71% of Pester
duration.

| Rank | Tier | File | Tests | Result | Time |
| ---: | --- | --- | ---: | --- | ---: |
| 1 | Slow | `tests/skalary/Skalary.Tests.ps1` | 19 | Passed | 637.283s |
| 2 | Fast | `tests/skalary/VerticalLoop.Tests.ps1` | 7 | Passed | 368.169s |
| 3 | Fast | `tests/skalary/LearningHarvest.Tests.ps1` | 7 | Passed | 342.915s |
| 4 | Fast | `tests/skalary/Add-WorkflowNote.Tests.ps1` | 20 | Passed | 313.296s |
| 5 | Slow | `tests/skalary/ConsumerInstall.Tests.ps1` | 6 | Passed | 233.104s |
| 6 | Fast | `tests/skalary/SiProposalCompletion.Tests.ps1` | 7 | Passed | 229.334s |
| 7 | Slow | `tests/skalary/PhaseReceiptMigration.Tests.ps1` | 13 | Passed | 224.972s |
| 8 | Fast | `tests/skalary/ReviewCycleGate.Tests.ps1` | 15 | Passed | 159.177s |
| 9 | Fast | `tests/skalary/Migrate-PlanFolderPrefixes.Tests.ps1` | 5 | Passed | 148.757s |
| 10 | Fast | `tests/skalary/SiProposalSync.Tests.ps1` | 3 | Passed | 137.760s |
| 11 | Slow | `tests/autopilot/EpicAutopilot.Tests.ps1` | 17 | Failed | 117.891s |
| 12 | Fast | `tests/skalary/PlanArtifactContext.Tests.ps1` | 16 | Passed | 110.958s |
| 13 | Slow | `tests/skalary/SuiteBudget.Tests.ps1` | 10 | Passed | 109.865s |
| 14 | Fast | `tests/autopilot/CompletionResume.Tests.ps1` | 19 | Passed | 99.704s |
| 15 | Fast | `tests/skalary/SiState.Tests.ps1` | 34 | Passed | 94.420s |
| 16 | Slow | `tests/skalary/RunUnitTests.Tests.ps1` | 13 | Passed | 89.636s |
| 17 | Dedicated | `tests/skalary/ReviewConsumerInstall.Tests.ps1` | 2 | Passed | 85.405s |
| 18 | Slow | `tests/skalary/SuiteFixture.Tests.ps1` | 6 | Passed | 85.230s |
| 19 | Fast | `tests/skalary/SiHarvest.Tests.ps1` | 15 | Passed | 81.195s |
| 20 | Slow | `tests/skalary/SuiteOrdering.Tests.ps1` | 2 | Passed | 72.399s |
| 21 | Slow | `tests/skalary/EvidenceTruth.Tests.ps1` | 7 | Passed | 72.287s |
| 22 | Fast | `tests/skalary/LearningLoop.Tests.ps1` | 3 | Passed | 58.680s |
| 23 | Slow | `tests/skalary/PlanAssets.Tests.ps1` | 26 | Passed | 56.524s |
| 24 | Slow | `tests/skalary/ReviewRunManifest.Tests.ps1` | 15 | Passed | 43.197s |
| 25 | Slow | `tests/skalary/AutopilotContainerGate.Tests.ps1` | 20 | Passed | 41.310s |
| 26 | Slow | `tests/skalary/PluginRetirement.Tests.ps1` | 24 | Passed | 39.113s |
| 27 | Fast | `tests/skalary/SiDue.Tests.ps1` | 3 | Passed | 35.860s |
| 28 | Slow | `tests/skalary/Add-LedgerEntry.Tests.ps1` | 17 | Passed | 29.095s |
| 29 | Slow | `tests/skalary/ReviewRunBudget.Tests.ps1` | 1 | Passed | 28.290s |
| 30 | Slow | `tests/skalary/ReviewReportDiscovery.Tests.ps1` | 3 | Passed | 25.139s |
| 31 | Slow | `tests/skalary/AssetBootstrap.Tests.ps1` | 31 | Passed | 23.911s |
| 32 | Slow | `tests/skalary/ReviewReportCorpus.Tests.ps1` | 9 | Passed | 20.295s |
| 33 | Fast | `tests/skalary/PluginScriptBundle.Tests.ps1` | 11 | Passed | 19.209s |
| 34 | Fast | `tests/skalary/Remove-LedgerEntry.Tests.ps1` | 5 | Passed | 18.588s |
| 35 | Fast | `tests/skalary/ReviewStandards.Tests.ps1` | 2 | Passed | 16.767s |
| 36 | Slow | `tests/skalary/ReviewRunArtifacts.Tests.ps1` | 20 | Passed | 15.779s |
| 37 | Slow | `tests/skalary/SiWriteScope.Tests.ps1` | 17 | Passed | 15.029s |
| 38 | Slow | `tests/skalary/ReviewRunPublish.Tests.ps1` | 10 | Passed | 14.826s |
| 39 | Slow | `tests/skalary/ArchitectureTestRetirement.Tests.ps1` | 7 | Passed | 13.402s |
| 40 | Fast | `tests/skalary/ReviewConcerns.Tests.ps1` | 10 | Passed | 13.359s |

## Slowest individual tests

| Rank | Time | Test | File |
| ---: | ---: | --- | --- |
| 1 | 250.586s | `keeps modified files during remove unless -Force is used` | `Skalary.Tests.ps1` |
| 2 | 167.469s | `test:VerticalLoop.AutopilotNextPhase` | `VerticalLoop.Tests.ps1` |
| 3 | 122.294s | `test:LearningHarvest.ActiveReceiptCapacityBoundary` | `LearningHarvest.Tests.ps1` |
| 4 | 111.764s | `test:LearningHarvest.MultiPhaseBatchAndProvenance` | `LearningHarvest.Tests.ps1` |
| 5 | 111.616s | `test:ConsumerInstall.FirstUseScaffoldLifecycle` | `ConsumerInstall.Tests.ps1` |
| 6 | 85.746s | `test:Capture.AtomicBoundaryMigrationMatrix` crash recovery | `Add-WorkflowNote.Tests.ps1` |
| 7 | 81.473s | `test:SiScope.ExpectedHeadMergeEnforced` | `SiProposalCompletion.Tests.ps1` |
| 8 | 76.217s | `test:SiState.PrFailureReconciliation` | `SiProposalCompletion.Tests.ps1` |
| 9 | 74.920s | `test:VerticalLoop.ConsumerInstall` | `VerticalLoop.Tests.ps1` |
| 10 | 74.740s | `test:EpicAutopilot.AbruptEvidenceRecovery` | `EpicAutopilot.Tests.ps1` |
| 11 | 71.817s | `installs transitive dependencies and writes receipts per plugin` | `Skalary.Tests.ps1` |
| 12 | 70.072s | `test:AutopilotCompletionResume.LongRunningFinalValidation` | `CompletionResume.Tests.ps1` |
| 13 | 65.710s | `test:PhaseReceiptMigration.Success` | `PhaseReceiptMigration.Tests.ps1` |
| 14 | 58.457s | `test:ConsumerInstall.RuntimeReferenceClosure` | `ConsumerInstall.Tests.ps1` |
| 15 | 53.338s | `test:SiScope.TrustedBasePassesAllowedProposal` | `SiProposalSync.Tests.ps1` |
| 16 | 53.240s | `test:LearningHarvest.FinalSweepReceiptReplay` | `LearningHarvest.Tests.ps1` |
| 17 | 53.155s | `test:PlanFolderPrefix.MigrationResume` | `Migrate-PlanFolderPrefixes.Tests.ps1` |
| 18 | 51.760s | `test:ReviewCycleGate` generated and installed parity | `ReviewCycleGate.Tests.ps1` |
| 19 | 46.422s | `test:SuiteBudget.OverBudgetRunFails` | `SuiteBudget.Tests.ps1` |
| 20 | 45.060s | `test:SiScope.StaleRemoteHeadRefused` | `SiProposalSync.Tests.ps1` |
| 21 | 44.878s | `test:LearningLoop.MaximumBoundRuntime` | `LearningLoop.Tests.ps1` |
| 22 | 44.759s | `test:ReviewReport.ConsumerInstallInvocation` CR | `ReviewConsumerInstall.Tests.ps1` |
| 23 | 41.776s | `allows phase-one harvest after legacy phase-zero planning capture` | `VerticalLoop.Tests.ps1` |
| 24 | 40.986s | `test:VerticalLoop.PhaseAdmission` | `VerticalLoop.Tests.ps1` |
| 25 | 40.532s | `test:ReviewReport.ConsumerInstallInvocation` DR | `ReviewConsumerInstall.Tests.ps1` |
| 26 | 40.449s | `marks update as degraded when modified files are skipped` | `Skalary.Tests.ps1` |
| 27 | 39.266s | `test:PlanArtifactContext.ConsumerInstall` | `PlanArtifactContext.Tests.ps1` |
| 28 | 39.209s | `test:SiScope.ProtectedTrustAnchorsAllRefused` | `SiProposalSync.Tests.ps1` |
| 29 | 36.514s | `fails closed for uncommitted source, missing refs, ambiguous identity, and conflicting v2` | `PhaseReceiptMigration.Tests.ps1` |
| 30 | 36.110s | `test:SuiteOrdering.RandomisedOrderGivesIdenticalResults` | `SuiteOrdering.Tests.ps1` |
| 31 | 35.615s | `test:EvidenceTruth.CleanReviewReceiptVetoes` | `EvidenceTruth.Tests.ps1` |
| 32 | 35.154s | `blocks removing a plugin while installed dependents still require it` | `Skalary.Tests.ps1` |
| 33 | 34.705s | `test:SuiteFixture.CommitIsDeterministic` | `SuiteFixture.Tests.ps1` |
| 34 | 33.617s | `test:SuiteFixture.CarriesTagsForVersionResolution` | `SuiteFixture.Tests.ps1` |
| 35 | 32.496s | `test:PluginRetirement.ReaderRemovalAndResultContract` | `Skalary.Tests.ps1` |
| 36 | 32.146s | `rejects incomplete or self-moving mappings before moving any folder` | `Migrate-PlanFolderPrefixes.Tests.ps1` |
| 37 | 32.070s | `aborts on registry hash mismatch and rolls back all staged changes` | `Skalary.Tests.ps1` |
| 38 | 31.308s | `test:Capture.AtomicBoundaryMigrationMatrix` timeout/conflict status | `Add-WorkflowNote.Tests.ps1` |
| 39 | 30.556s | `accepts only bounded finalized review pairs with exact receipt bindings` | `PlanArtifactContext.Tests.ps1` |
| 40 | 29.162s | `test:PlanFolderPrefix.MigrationWhatIf` | `Migrate-PlanFolderPrefixes.Tests.ps1` |

## Instrumented plugin operations

These wrappers cover only `Skalary.Tests.ps1`. They explain 571.364s of its
637.283s container time.

| Operation | Calls | Total | Mean |
| --- | ---: | ---: | ---: |
| `Remove-Plugin` | 3 | 240.700s | 80.233s |
| `Install-Plugin` | 12 | 114.520s | 9.543s |
| `New-RepoClone` | 31 | 105.754s | 3.411s |
| `Build-Registry` | 10 | 68.727s | 6.873s |
| `Test-Registry` | 6 | 22.312s | 3.719s |
| `Update-Plugin` | 2 | 18.490s | 9.245s |
| `Get-Plugin` | 4 | 0.634s | 0.158s |
| `Find-Plugin` | 2 | 0.227s | 0.113s |

### Historical directional comparison

The repository's committed 2026-08-15 profile used Ubuntu, Pester 5.6.1, 75
files, and 781 tests. The current profile used Windows, Pester 5.7.1, 114
files, and 1,251 tests. It is not a controlled before/after benchmark.

The wrapped operation call counts are nevertheless identical in both profiles,
which makes the change in their aggregate cost useful directional evidence:

| Operation | Calls | 2026-08-15 Ubuntu | 2026-08-31 Windows | Multiplier |
| --- | ---: | ---: | ---: | ---: |
| `New-RepoClone` | 31 | 3.533s | 105.754s | 29.94x |
| `Install-Plugin` | 12 | 17.016s | 114.520s | 6.73x |
| `Build-Registry` | 10 | 9.888s | 68.727s | 6.95x |
| `Test-Registry` | 6 | 9.807s | 22.312s | 2.28x |
| `Remove-Plugin` | 3 | 34.625s | 240.700s | 6.95x |
| `Update-Plugin` | 2 | 3.284s | 18.490s | 5.63x |
| All wrapped operations | 70 | 78.343s | 571.364s | 7.29x |

`Skalary.Tests.ps1` itself increased from 79.701s to 637.283s, almost exactly
8.00x. The complete suite grew by 39 files and 470 tests, so its overall
16.63x wall-clock difference must not be attributed to platform alone.

## What consumes the time

### 1. Transaction-journal write amplification during plugin removal

`Remove-Plugin` is the clearest single hotspot: 240.700s across three calls.
The modified-file preservation test alone takes 250.586s.

`Invoke-PluginRemovalPrimitive` creates a recovery journal, then persists the
complete and growing JSON document after each file backup and again after each
file deletion. The `create-implementation-plan` fixture has 38 direct files.
Repeatedly serializing and replacing the whole journal while its entry set
grows makes one removal perform approximately quadratic journal-byte work in
the number of plugin files, in addition to hashing, copying, and deleting each
file. Windows filesystem and endpoint-scanning costs amplify those writes.

The first optimization target is to reduce journal persistence amplification
without weakening the crash-recovery contract: persist bounded batches or
compact phase checkpoints, and retain an explicit interruption case at each
durable boundary.

### 2. Real Git repositories and command-process churn

Many cases create actual working repositories, bare remotes, trusted clones,
branches, commits, pushes, detached states, and ref mutations. The narrow
`New-RepoClone` wrapper measured 31 calls at 105.754s, but it does not include
the many direct `git` invocations in SI completion, receipt migration,
vertical-loop, migration, artifact, and autopilot fixtures.

Examples:

- `SiProposalCompletion.Tests.ps1` spends 229.334s constructing and reconciling
  working, remote, and trusted-clone state.
- `PhaseReceiptMigration.Tests.ps1` spends 224.972s exercising committed blob,
  tree, path-history, and replacement provenance.
- `CompletionResume.Tests.ps1` spends 70.072s in one case that repeatedly
  creates Git state and invokes Bash close probes.
- `EpicAutopilot.AbruptEvidenceRecovery` spends 74.740s across five
  staged/unstaged, LF/CRLF, and prefixed-folder fixture variants.

An immutable committed repository template copied to private per-case roots can
remove repeated initialization and setup. Tests still need separate mutable
working trees; sharing a live repository would invalidate isolation.

### 3. Fresh PowerShell processes inside test matrices

Receipt, evidence, migration, runner, install, and parity tests repeatedly call
`pwsh -NoProfile`. Every call pays process creation, module import, script
parse, and sometimes nested Pester startup. The cost is multiplied by loops
over tiers, outcomes, mutations, installed copies, or failure modes.

Examples include:

- `ReviewCycleGate` parity invokes equivalent behavior through generated and
  installed surfaces.
- `EvidenceTruth.CleanReviewReceiptVetoes` applies each malformed aggregate at
  multiple evidence entry points.
- `RunUnitTests.Tests.ps1` starts child runners because nested in-process Pester
  would share outer module state.
- `SuiteBudget.Tests.ps1` starts complete child runner sandboxes repeatedly to
  prove advisory budget and freshness exits.

Keep one out-of-process case for each executable contract, but expose imported
functions or narrow process seams for the remaining data matrix. This preserves
CLI evidence while avoiding a new interpreter for every row.

### 4. Maximum-boundary fixture construction

Several tests deliberately build the largest accepted input and then the
plus-one rejection:

- Learning harvest builds the 64-receipt active boundary and a 10,000-line
  ledger.
- Workflow-note recovery builds overflow batches and replays every
  overflow-first and active-replace interruption point.
- Review-run budgets construct maximum envelopes and a 256 MiB boundary.
- Ledger tests build record ceilings to prove bounded behavior.

The contracts are valid, but rebuilding the same immutable maximum fixture in
multiple `It` blocks pays the full filesystem and serialization cost each
time. Build immutable templates once per file and copy or restore only the
small mutable layer. Keep the accepted-boundary and plus-one assertions
separate so a fixture shortcut cannot hide the limit.

### 5. Deliberate wall-clock waiting

`Add-WorkflowNote.Tests.ps1` starts a lock holder with
`Start-Sleep -Seconds 30`. The corresponding timeout/conflict test took
31.308s. A synchronization marker plus an injectable one-second test timeout
would prove the same status transition while removing about 29 seconds of
intentional waiting. Production timeout defaults must remain unchanged.

### 6. Full foreign-consumer installation lifecycles

Consumer tests install manifests into isolated repositories, hash inventories,
run owner scaffolds, execute behavior smokes, and verify distribution drift:

- `ConsumerInstall.Tests.ps1`: 233.104s.
- Dedicated CR/DR consumer installation: 85.405s.
- `VerticalLoop.ConsumerInstall`: 74.920s.
- `PlanArtifactContext.ConsumerInstall`: 39.266s.

These are valuable integration proofs. Their repeated common installation
prefix can be shared within a file if each case restores a private mutable
copy. At least one complete install-from-empty case per independently versioned
consumer must remain.

### 7. The suite tests its own runners

`SuiteBudget`, `RunUnitTests`, `SuiteFixture`, and `SuiteOrdering` intentionally
invoke child runners, regenerate fixtures, or execute probes in multiple
orders. Together they consume 357.130s. The cost is structural: they prove
isolation, cannot-test exits, environment-leak detection, budget reporting, and
ordering independence by running the infrastructure rather than mocking it.

These tests should remain Slow. Development feedback should select one stable
evidence ID rather than running each complete file. Runtime reduction requires
fewer nested full-runner invocations, not only a tier change.

## Optimization order supported by the evidence

1. **Batch plugin-removal journal persistence.** This addresses the clearest
   algorithmic hotspot and up to 240.700s of directly measured operation time.
2. **Reuse immutable Git fixture templates.** Apply the existing
   `SuiteFixture.psm1` private-copy pattern to SI, migration, and autopilot
   fixture families.
3. **Separate CLI proof from data matrices.** Retain one subprocess contract
   case and run the remaining cases through imported functions or an injectable
   process seam.
4. **Replace fixed sleeps with injectable test timeouts and synchronization.**
   The directly visible first saving is approximately 29 seconds.
5. **Construct maximum-boundary templates once per file.** Restore private
   mutable state instead of rebuilding 64-receipt and 10,000-record inputs.
6. **Share foreign-install prefixes safely.** Preserve independent consumer
   and from-empty coverage while avoiding repeated identical installation work.
7. **Use focused evidence IDs during development.** This does not reduce the
   required complete-suite cost, but avoids paying entire process-heavy files
   for one changed behavior.

Re-profile after each optimization. The profile shows where time is spent; it
does not prove that a proposed shortcut preserves crash recovery, confinement,
receipt truth, process isolation, or installed-consumer behavior.

## Failed-test disclosure

The combined profile ended with four failures in
`tests/autopilot/EpicAutopilot.Tests.ps1`:

| Test | Observed failure |
| --- | --- |
| `test:EpicAutopilot.HostLoop` | `Target HEAD does not name a local branch.` |
| `test:EpicAutopilot.FinalCrosscheck` | Expected LF capture bytes but observed CRLF bytes. |
| `test:EpicAutopilot.A5ad22WrappedBaseline` | Expected and actual retained-tree hashes differed. |
| `test:EpicAutopilot.ResumeState` | Branch-shape precondition failed before the expected invalid-outcome diagnostic. |

The profile ran from a detached `HEAD` and ran the complete tree in one Pester
process rather than normal Fast, Slow, and Dedicated isolation. Those
conditions can expose checkout assumptions or shared-state/order leakage. The
four failures are disclosed rather than classified as product regressions.
They consumed only about 7.4 seconds before failing, so they do not explain the
76-minute runtime. Because a failed assertion can stop a case early, the
117.891-second `EpicAutopilot.Tests.ps1` duration is a lower bound for an
all-passing combined run.

## Interpretation limits

1. This is one Windows observation, not a statistical distribution.
2. File and test times are wall-clock durations and include child-process wait
   time; they are not CPU utilization measurements.
3. Only the eight plugin operations above were instrumented. Direct Git,
   PowerShell, Bash, filesystem, hashing, and JSON work is attributed through
   containing tests rather than operation totals.
4. The historical Ubuntu profile used a smaller and older tree, so its
   whole-suite multiplier is context, not regression proof.
5. The combined-process run differs from normal tier isolation and had four
   disclosed failures.
6. No optimization was implemented as part of this profiling exercise.
