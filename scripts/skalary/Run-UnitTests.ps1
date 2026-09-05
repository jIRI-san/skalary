#requires -Version 7.0
<#
.SYNOPSIS
    Runs explicitly selected Pester tests.
.DESCRIPTION
    Routine use requires repository-relative -TestPath values and runs in a supervised child
    process. Focused runs target less than 30 seconds and terminate the child process tree at
    60 seconds. The complete tests/ tree remains available only through the direct,
    operator-only -FullRepository switch.

    Exit codes:
      0  selected tests ran and passed
      1  at least one selected test failed
      2  Pester is not installed
      3  no runnable test was discovered
      4  a selected test file failed to load
      7  a test leaked an environment-variable change
      8  required typed evidence was skipped or did not pass
     12  focused scope or an output path is invalid
     13  focused execution exceeded its timeout
     14  the focused worker could not start
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -TestPath tests/skalary/SkillContracts.Tests.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -FullRepository
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..')),
    [string[]]$TestPath = @(),
    [string[]]$TestName = @(),
    [string[]]$EvidenceTestId = @(),
    [string]$EvidenceResultPath,
    [switch]$FullRepository,
    [string]$TestResultPath,
    [ValidateRange(0.05, 30)]
    [double]$FocusedWarningSeconds = 30,
    [ValidateRange(0.1, 60)]
    [double]$FocusedTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FocusedWarningSeconds -ge $FocusedTimeoutSeconds) {
    [System.Console]::Out.WriteLine(
        'FocusedScopeRequired: focused warning threshold must be lower than the focused timeout.')
    exit 12
}

$body = [System.IO.Path]::Combine($PSScriptRoot, 'internal', 'Invoke-UnitTestRun.ps1')
$request = @{
    RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    TestPath = @($TestPath)
    TestName = @($TestName)
    EvidenceTestId = @($EvidenceTestId)
    FullRepository = [bool]$FullRepository
}
if ($EvidenceResultPath) { $request.EvidenceResultPath = $EvidenceResultPath }
if ($TestResultPath) { $request.TestResultPath = $TestResultPath }

if ($FullRepository) {
    . $body
    Invoke-SkalaryUnitTestRun @request
    exit 0
}

$supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'internal', 'FocusedSupervision.ps1'))
exit (& $supervision.InvokeSupervisedBody -BodyPath $body -Request $request `
        -Label 'selected unit tests' -WarningSeconds $FocusedWarningSeconds `
        -TimeoutSeconds $FocusedTimeoutSeconds)
