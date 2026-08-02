## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] Measure-SuiteProfile could overwrite the committed cost model with an all-zero profile from a subtree run; fixed by refusing the default output path for a partial scope and refusing to write when zero samples were recorded.
- [1.2] [src:code-review] [sev:Med] Regenerating the coverage baseline bypassed the removal-with-a-reason rule; Get-TestInventory now refuses to drop or shrink a recorded name unless it is already enumerated in removals.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Synthetic fixture dropped .github, making the install-rollback assertion vacuous; restored .github to the payload allowlist and added a non-empty guard.
- [2.1] [src:code-review] [sev:High] Per-fixture commits diverged, so Install-Plugin's registry-parity check silently stopped running; fixture commit timestamps pinned so every fixture shares one SHA.
- [2.1] [src:code-review] [sev:Med] SuiteFixture cases shared one mutable fixture and pinned .github absence as an invariant; each case now builds its own fixture and the allowlist assertion checks tracked files.
- [2.1] [src:code-review] [sev:Low] New-SkalaryFixtureRepo leaked its temp root when a git step failed mid-build; wrapped in try/catch cleanup.

## CR Capture
Phase: 5

- [5.1] [src:code-review] [sev:Med] Published exit-code contract was false: Invoke-Pester -CI sets Run.Exit, so Pester exited with the failure count before the script could, making the PesterNotInstalled sentinel 2 indistinguishable from a two-failure run and leaving exit 1 dead. Replaced -CI with an explicit PesterConfiguration (TestResult.Enabled kept, Run.Exit off) and added an assertion that a failing run exits 1 and never collides with the sentinel.
- [5.2] [src:code-review] [sev:High] Zero-discovery guard left the other half open: a test file that throws during discovery contributes to neither TotalCount nor FailedCount, so a suite with an unparseable file exited 0 with that file never run - including this file, which would have taken the REQ-5 gate down with it. Added a FailedContainersCount guard (exit 4, TestFilesNotDiscoverable, names the files), folded FailedBlocksCount into the failed-run branch, and landed test:RunUnitTests.UndiscoverableTestFileFails proven red against the pre-fix script.

## CR Capture
Phase: 6

- [6.1] [src:code-review] [sev:Med] Get-PlanStageOrder published dr-round but Resolve-PlanStage rejected it, so a caller-supplied floor failed with the plan-blaming RISK-6 error; Test-PlanStageAtLeast now ranks -Minimum against the family list and says the floor is the caller's bug.
