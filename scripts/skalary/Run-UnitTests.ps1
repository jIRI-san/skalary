#requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester unit-test suite, failing whenever it cannot actually test.
.DESCRIPTION
    This script is the focused repository test command and the executor behind every
    `test:` evidence marker. A green run therefore has to mean tests ran:
    reporting success having executed zero assertions forges evidence (REQ-5).

    Every focused run is supervised: this script hands the request to a child process running
    the private body `internal/Invoke-UnitTestRun.ps1`, targets less than 30 seconds, warns
    only after a 30-60 second completion, and terminates the child process tree at 60
    seconds. There is no parameter, variable or environment value that selects an unsupervised
    focused run, and no step of the focused dispatch is reachable by command-name resolution.
    Only the direct `-FullRepository` and `-StartBudgetClock` routes run in this process, and
    legacy broad runtime observations remain on `-FullRepository` pending their separately
    owned cleanup.

    Exit codes:
      0  tests ran and passed
      1  tests ran and at least one failed
      2  PesterNotInstalled — the framework is absent; the message names the install command
      3  NoTestsDiscovered — Pester ran but found nothing to assert, including a -TestName
            filter that matched no runnable test
      4  TestFilesNotDiscoverable — a test file failed to load, so its tests never ran
            5  Reserved — runtime overruns are advisory
            6  Reserved — missing budget metadata is advisory
      7  EnvironmentLeaked — a test changed the caller's process environment and did not restore it
      8  RequiredEvidenceSkipped — mandatory review evidence did not execute
      9  SuiteTierInvalid — the tracked tier manifest is absent or invalid
        10  Reserved — stale runtime measurements are advisory
     11  MeasurementTokenInvalid — a measurement-mode token failed closed validation
     12  FocusedScopeRequired — Fast did not receive focused test paths or -FullRepository
     13  FocusedTimeout — a focused run exceeded 60 seconds and its child process tree was
            terminated. The same code rejects malformed focused evidence IDs/output paths
            before execution.
     14  FocusedWorkerStartFailed — the supervisor could not start the focused child
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -TestPath tests/skalary/SkillContracts.Tests.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -FullRepository
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..')),

    [ValidateSet('Fast', 'Slow', 'All')]
    [string]$Tier = 'Fast',

    # Fast is focused by default. Callers must name the directly relevant test files;
    # the old complete Fast complement is available only through -FullRepository.
    [string[]]$TestPath = @(),

    # Optional Pester full-name filters. Required when focused Fast selects a file
    # assigned to Slow, so only the relevant sub-minute case executes.
    [string[]]$TestName = @(),

    # Stable IDs from leading `test:<id>` tokens in Pester test names. This uses the same
    # discovery and invocation as focused Fast, but also emits one structured result per ID.
    [string[]]$EvidenceTestId = @(),

    [string]$EvidenceResultPath,

    [switch]$FullRepository,

    # Writes the budget clock and returns. The `pretest` hook calls this before the first leg
    # of `npm test`, which is the only way a leg can measure a command that spans three of them.
    [switch]$StartBudgetClock,

    # Defaults to a temp path derived from $RepoRoot. Derived rather than fixed because the
    # suite runs this script against sandbox roots of its own: a shared path would let one of
    # those nested runs consume the clock belonging to the real run that spawned it.
    [string]$BudgetClockPath,

    # Where the NUnit report is written. Pester's default is a fixed name in the working
    # directory, which two CI matrix legs would both produce and neither could be told apart
    # from — so CI names it per platform (REQ-9) and everything else keeps the default.
    [string]$TestResultPath,

    [ValidateRange(0.05, 30)]
    [double]$FocusedWarningSeconds = 30,

    [ValidateRange(0.1, 60)]
    [double]$FocusedTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The only check that stays here: a warning threshold at or past the timeout would make the
# supervisor unable to distinguish a slow run from a killed one, and no child can report that.
# Focused dispatch below resolves no command by name: an alias or function in the calling
# session cannot redirect the body path, the request, or the supervisor.
if ($FocusedWarningSeconds -ge $FocusedTimeoutSeconds) {
    [System.Console]::Out.WriteLine('FocusedScopeRequired: focused warning threshold must be lower than the focused timeout.')
    exit 12
}

$unitTestBody = [System.IO.Path]::Combine($PSScriptRoot, 'internal', 'Invoke-UnitTestRun.ps1')

$request = @{
    RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    Tier = $Tier
    TestPath = @($TestPath)
    TestName = @($TestName)
    EvidenceTestId = @($EvidenceTestId)
    FullRepository = [bool]$FullRepository
    StartBudgetClock = [bool]$StartBudgetClock
}
if ($EvidenceResultPath) { $request.EvidenceResultPath = $EvidenceResultPath }
if ($BudgetClockPath) { $request.BudgetClockPath = $BudgetClockPath }
if ($TestResultPath) { $request.TestResultPath = $TestResultPath }

# Direct broad runs and the clock-only leg are not focused work and stay in this process.
# Everything else is focused and enters the supervisor: there is no argument, variable, or
# environment value that reaches the branch below, so no caller can select the unsupervised
# path for a focused run.
if ($FullRepository -or $StartBudgetClock) {
    . $unitTestBody
    Invoke-SkalaryUnitTestRun @request
    exit 0
}

$supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'internal', 'FocusedSupervision.ps1'))
exit (& $supervision.InvokeSupervisedBody -BodyPath $unitTestBody -Request $request `
        -Label 'selected unit tests' -WarningSeconds $FocusedWarningSeconds `
        -TimeoutSeconds $FocusedTimeoutSeconds)
