#requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester unit-test suite, failing whenever it cannot actually test.
.DESCRIPTION
    This script is the `test:unit` leg of the repository test command and the executor
    behind every `test:` evidence marker. A green run therefore has to mean tests ran:
    reporting success having executed zero assertions forges evidence (REQ-5).

    Exit codes:
      0  tests ran and passed
      1  tests ran and at least one failed
      2  PesterNotInstalled — the framework is absent; the message names the install command
      3  NoTestsDiscovered — Pester ran but found nothing to assert
      4  TestFilesNotDiscoverable — a test file failed to load, so its tests never ran
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# RISK-3: an environment without Pester now fails instead of skipping, so the message has to
# carry the way out of that state rather than only the diagnosis.
$installCommand = 'Install-Module Pester -Scope CurrentUser -Force'

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pesterModule) {
    Write-Host "PesterNotInstalled: cannot run the unit tests because Pester is not installed. Install it with: $installCommand" -ForegroundColor Red
    exit 2
}

$testPath = Join-Path $RepoRoot 'tests'
if (-not (Test-Path -LiteralPath $testPath -PathType Container)) {
    throw "Unit test path not found: $testPath"
}

# Pester throws rather than returning a result when the path holds no test file at all.
# Checking first keeps that case as this script's own diagnosis and leaves every other
# Invoke-Pester failure loud instead of swallowed by a catch.
$testFiles = @(Get-ChildItem -LiteralPath $testPath -Recurse -File -Filter '*.Tests.ps1')
if ($testFiles.Count -eq 0) {
    Write-Host "NoTestsDiscovered: no *.Tests.ps1 file exists under '$testPath', so there was nothing to discover." -ForegroundColor Red
    exit 3
}

Import-Module Pester -MinimumVersion $pesterModule.Version -ErrorAction Stop

# `-CI` is Pester's shorthand for `Run.Exit` plus `TestResult.Enabled`, and `Run.Exit` makes
# Pester exit with the failure count before this script can. That collides a "could not test"
# code with "that many tests failed" — the one distinction this script exists to make — so the
# NUnit output is kept and the exit is taken back.
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testPath
$configuration.Run.PassThru = $true
$configuration.Run.Exit = $false
$configuration.TestResult.Enabled = $true

$result = Invoke-Pester -Configuration $configuration

# Test files that discover no test are the quieter half of the same failure: Pester returns a
# clean zero-failure result, so the run would otherwise be reported as a pass having asserted
# nothing (REQ-5).
if ($null -eq $result -or [int]$result.TotalCount -le 0) {
    Write-Host "NoTestsDiscovered: Pester $($pesterModule.Version) discovered 0 tests in $($testFiles.Count) file(s) under '$testPath'. A run that asserts nothing is not a pass." -ForegroundColor Red
    exit 3
}

# A test file that throws while being discovered contributes nothing to either count above:
# Pester tracks it separately. Deciding on FailedCount alone therefore reports a pass for a
# suite in which a whole file never ran — including this file, which would take the REQ-5
# gate down with it and stay green.
if ([int]$result.FailedContainersCount -gt 0) {
    $undiscoverable = @($result.FailedContainers | ForEach-Object { [string]$_.Item })
    Write-Host "TestFilesNotDiscoverable: $($result.FailedContainersCount) test file(s) failed to load, so their tests never ran: $($undiscoverable -join ', ')" -ForegroundColor Red
    exit 4
}

if ([int]$result.FailedCount -gt 0 -or [int]$result.FailedBlocksCount -gt 0) {
    exit 1
}

exit 0
