## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] Measure-SuiteProfile could overwrite the committed cost model with an all-zero profile from a subtree run; fixed by refusing the default output path for a partial scope and refusing to write when zero samples were recorded.
- [1.2] [src:code-review] [sev:Med] Regenerating the coverage baseline bypassed the removal-with-a-reason rule; Get-TestInventory now refuses to drop or shrink a recorded name unless it is already enumerated in removals.
- [1.3] [src:code-review] [sev:High] Per-platform ceilings made the justification lookup load-bearing, and it could never run: Get-PlanDecisionsText passed -Raw with -TotalCount (mutually exclusive parameter sets), so any real 4.2 raise failed on a binding error indistinguishable from a missing justification, and the once-per-plan raise assertion after it was unreachable. Fixed the read and hoisted the total-raises assertion above the per-platform loop; verified a justified raise now passes and an unjustified or second raise is red.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Synthetic fixture dropped .github, making the install-rollback assertion vacuous; restored .github to the payload allowlist and added a non-empty guard.
- [2.1] [src:code-review] [sev:High] Per-fixture commits diverged, so Install-Plugin's registry-parity check silently stopped running; fixture commit timestamps pinned so every fixture shares one SHA.
- [2.1] [src:code-review] [sev:Med] SuiteFixture cases shared one mutable fixture and pinned .github absence as an invariant; each case now builds its own fixture and the allowlist assertion checks tracked files.
- [2.1] [src:code-review] [sev:Low] New-SkalaryFixtureRepo leaked its temp root when a git step failed mid-build; wrapped in try/catch cleanup.
- [2.2] [src:code-review] [sev:Med] Copy-SkalaryFixtureTree leaked a half-copied case root on a mid-copy failure; the path is never returned so no AfterAll could reclaim it. Added cleanup-and-rethrow.
- [2.2] [src:code-review] [sev:Low] Skalary.Tests.ps1 AfterAll removed fixtures without -ErrorAction SilentlyContinue under ErrorActionPreference Stop, so one failure skipped the template cleanup.

## CR Capture
Phase: 5

- [5.1] [src:code-review] [sev:Med] Published exit-code contract was false: Invoke-Pester -CI sets Run.Exit, so Pester exited with the failure count before the script could, making the PesterNotInstalled sentinel 2 indistinguishable from a two-failure run and leaving exit 1 dead. Replaced -CI with an explicit PesterConfiguration (TestResult.Enabled kept, Run.Exit off) and added an assertion that a failing run exits 1 and never collides with the sentinel.
- [5.2] [src:code-review] [sev:High] Zero-discovery guard left the other half open: a test file that throws during discovery contributes to neither TotalCount nor FailedCount, so a suite with an unparseable file exited 0 with that file never run - including this file, which would have taken the REQ-5 gate down with it. Added a FailedContainersCount guard (exit 4, TestFilesNotDiscoverable, names the files), folded FailedBlocksCount into the failed-run branch, and landed test:RunUnitTests.UndiscoverableTestFileFails proven red against the pre-fix script.

## CR Capture
Phase: 6

- [6.1] [src:code-review] [sev:Med] Get-PlanStageOrder published dr-round but Resolve-PlanStage rejected it, so a caller-supplied floor failed with the plan-blaming RISK-6 error; Test-PlanStageAtLeast now ranks -Minimum against the family list and says the floor is the caller's bug.
- [6.2] [src:code-review] [sev:Low] No findings on the final state; the cep manifest gap that would have half-scaffolded a plan folder was already fixed and guarded by the widened manifest-coverage test before review completed.
- [6.3] [src:code-review] [sev:Med] The stage floor was cosmetic: scripts/validate.ps1 re-validated every plan unconditionally, so a below-floor plan was skipped by leg 1 and hard-failed by leg 3 of npm test. Both legs now share Get-PlanValidationDecision.

## CR Capture
Phase: 7

- [7.2] [src:code-review] [sev:High] Test-Registry.ps1 carried a duplicate New-ReadmeCatalogTable still using culture-sensitive Sort-Object, so the drift gate would reject a correctly generated README on a cs-CZ host. Fixed: gate now shares the ordinal comparer, and CzechCollationFixtureIsStable runs Test-Registry.ps1 under both cultures (verified non-vacuous by reverting the sort).
- [7.3] [src:code-review] [sev:Med] Test-ReparsePoint returned true on any exception, so an unreadable file silently left the parsed set — a fail-open in the gate that exists to prove every payload file parses. Fixed: it now throws, and only directory descent swallows the error via Test-DirectoryWalkable.
- [7.3] [src:code-review] [sev:Med] Allowlist drift and an empty parse set were both silent. Fixed: -RequireRoot throws on a missing/unreadable root, validate.ps1 errors on a zero-file enumeration, and test:Validate.PayloadRootsCoverRepository fails when a new top-level directory is neither allowlisted nor pruned.
