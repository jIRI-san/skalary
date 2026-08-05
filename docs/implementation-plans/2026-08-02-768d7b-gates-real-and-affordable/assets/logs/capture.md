## Capture
Phase: 1

- [1.1] [src:note] Baseline measured in the autopilot Linux container: Pester leg 102.3s wall clock over 710 tests, 25.7s of it inside the four instrumented operations (New-RepoClone 29 calls/9.7s, Install-Plugin 10/8.4s, Test-Registry 6/6.0s, Build-Registry 10/2.9s). The plan's 1741.8s figure came from a Windows host, so phase 4 must record the platform with the achieved figure.
- [1.1] [src:note] Costliest files after Skalary.Tests.ps1 (29.6s): Add-LedgerEntry 16.7s, PlanAssets 11.9s, Test-Plan 9.4s, Remove-LedgerEntry 7.8s - the input phase 3.2 asks for.

## Capture
Phase: 2

No entries for this phase.

## Capture
Phase: 5

- [5.1] Step 2.2 is left in-progress with uncommitted work whose Copy-DirectoryContent resolves cp via Get-Command without taking the first match, so the path becomes two paths joined and 20 cases in Skalary.Tests.ps1/SuiteFixture.Tests.ps1 fail. Pre-existing and unrelated to phase 5; the phase-5 commits do not stage those files.

## Capture
Phase: 6

No entries for this phase.

## Capture
Phase: 7

- [7.1] D8 satisfied: collation fixture (plugin names chata/cukr/hrad/ivan, accented+mixed-case tags and file names) is RED against pre-fix Build-Registry — en-US yields 'chata, cukr, hrad, ivan', cs-CZ yields 'cukr, hrad, chata, ivan'; FixtureIsRedBeforeFix passes, CzechCollationFixtureIsStable fails.

## Capture
Phase: 3

No entries for this phase.

## Capture
Phase: 4

- [4.1] [src:note] npm test measured on the runners the gate will enforce on: ci:ubuntu-latest 108.998s, ci:windows-latest 223.142s, both green, both 4-core, commit c99d5d1. D13/RISK-4's 10x platform gap is gone - Windows was 1157s before phases 2 and 3 and is now 2.05x Linux, so the tier split D13 held in reserve is not needed. The autopilot container measures 86s on 16 cores; the CI figures are the slower and therefore the ones the ceiling is tightened against.
- [4.1] [src:note] Windows cannot be measured from the Linux autopilot container, so step 4.1 measured it on windows-latest through a temporary path-filtered workflow (.github/workflows/suite-runtime-measure.yml), imported both rows through Measure-SuiteRuntime.ps1 -ImportRow, and deleted the workflow in the same phase; the durable CI wiring stays phase 8's job.
