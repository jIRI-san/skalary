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
- [2.3] [src:code-review] [sev:High] PhaseTargetsMet checked declarations->rows only, so an undeclared phase row with a zeroed target was ungated; fixed by asserting set equality in both directions.
- [2.3] [src:code-review] [sev:Med] achievedSavingSeconds was the scored number and the only one not derived; now recomputed from baselineSeconds minus scopeSeconds.

## CR Capture
Phase: 5

- [5.1] [src:code-review] [sev:Med] Published exit-code contract was false: Invoke-Pester -CI sets Run.Exit, so Pester exited with the failure count before the script could, making the PesterNotInstalled sentinel 2 indistinguishable from a two-failure run and leaving exit 1 dead. Replaced -CI with an explicit PesterConfiguration (TestResult.Enabled kept, Run.Exit off) and added an assertion that a failing run exits 1 and never collides with the sentinel.
- [5.2] [src:code-review] [sev:High] Zero-discovery guard left the other half open: a test file that throws during discovery contributes to neither TotalCount nor FailedCount, so a suite with an unparseable file exited 0 with that file never run - including this file, which would have taken the REQ-5 gate down with it. Added a FailedContainersCount guard (exit 4, TestFilesNotDiscoverable, names the files), folded FailedBlocksCount into the failed-run branch, and landed test:RunUnitTests.UndiscoverableTestFileFails proven red against the pre-fix script.
- [5.2] [src:code-review] [sev:Med] Phase 5 re-verification clean, but review found a live REQ-2 defect in step 4.3 code: npm test short-circuits on &&, so a failing validate-plan or validate.ps1 leg leaves the pretest budget clock on disk and test:unit never runs to clear it. A later direct npm run test:unit (no pretest hook, same RepoRoot-derived path) adopts that startedAt and exits 5 OverBudget for a run that took seconds. The staleness guard only discards clocks older than AbsoluteCapSeconds*4=3600s, so the whole 330s-3600s window is a spurious hard failure. False red, not false green: exit 5 is unreachable before the REQ-5 branches, so REQ-5 is unaffected. Left unfixed here as out-of-scope for phase 5; belongs to REQ-2 and needs its own test, since SuiteBudget.Tests.ps1 claims to cover the failing-earlier-leg case but invokes the runner directly, the one path that does clear the clock.

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

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] Rebuilding the fixture registry stamped a wall-clock generatedAt into the committed tree, so the fixture commit SHA drifted per build and Install-Plugin's parity check would silently no-op; pinned the timestamp and made CommitIsDeterministic compare two independently built templates.
- [3.2] [src:code-review] [sev:Med] Invoke-SuiteScript read the runspace's LASTEXITCODE, which a failing native command sets just as exit does, so a script without a terminal exit would report that command's code and turn 'Should -Not -Be 0' vacuous; the helper now refuses such a script by AST check and the guard is tested.
- [3.3] [src:code-review] [sev:High] The ordering probes were partly vacuous: the runspace-host probes wrote and read a global inside one probe so position could not change the answer, the leak guard re-implemented the probe body inline instead of running it, the shuffle could return the identity permutation, and Get-Random -SetSeed reseeded the process-wide generator; probes now split read from taint, the guard runs each probe's own body over a tainted tree, the identity permutation is redrawn, and the shuffle uses a local System.Random.

## CR Capture
Phase: 4

- [4.3] [src:code-review] [sev:High] Clock was consumed only on the green path, so a red suite or a failing earlier leg stranded it and the next direct test:unit run was charged the abandoned run's wall clock (reproduced: 1.3s run reported as 408s over budget). Fixed by reading and clearing the clock before any exit; covered by test:SuiteBudget.ClockedRunIsMeasuredAsTheWholeCommand.
- [4.3] [src:code-review] [sev:Med] Staleness bound fell back to HardCeilingSeconds*4 when AbsoluteCapSeconds was absent, so the worse the overrun the more certainly the clock was discarded and the run passed on a leg-only figure. AbsoluteCapSeconds is now required (exit 6 when missing).
- [4.3] [src:code-review] [sev:Med] A budget entry missing a field the check reads died under StrictMode with exit 1 - the code that means tests failed - destroying the one distinction the runner exists to make. Every field is now named in the guard before it is read; covered by test:SuiteBudget.OverBudgetRunFails.
- [4.3] [src:code-review] [sev:Med] Docstring claimed CI already invokes this script; registry-ci.yml still calls Invoke-Pester on one file. Claim reworded as the REQ-9 contract phase 8 wires, not a statement about the present.
