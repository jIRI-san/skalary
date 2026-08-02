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
if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
