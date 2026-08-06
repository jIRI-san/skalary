#requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester unit-test suite, failing whenever it cannot actually test.
.DESCRIPTION
    This script is the `test:unit` leg of the repository test command and the executor
    behind every `test:` evidence marker. A green run therefore has to mean tests ran:
    reporting success having executed zero assertions forges evidence (REQ-5).

    It is also where the runtime budget is enforced (REQ-2), and the only place that check
    lives, so the CI workflow REQ-9 describes must invoke this script rather than calling
    Invoke-Pester directly (that wiring lands in this plan's phase 8). The budget in
    `tools/suite-budget.psd1` is stated per platform and measured against the whole `npm test`
    command, not this leg alone — so the clock is started by the `pretest` hook (this same
    script, `-StartBudgetClock`) and read here, with this script last in the chain. Invoked
    outside that chain there is no clock, and the elapsed time of this leg is a *lower bound*
    on the command's: over budget on a subset is over budget, but under budget on one is not a
    verdict on the whole, and the report says which of the two it is.

    Exit codes:
      0  tests ran and passed
      1  tests ran and at least one failed
      2  PesterNotInstalled — the framework is absent; the message names the install command
      3  NoTestsDiscovered — Pester ran but found nothing to assert
      4  TestFilesNotDiscoverable — a test file failed to load, so its tests never ran
      5  OverBudget — the run is slower than this platform's hard ceiling
      6  BudgetNotDefined — no budget file, or no entry for this platform
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

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
    [string]$TestResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$legStart = [DateTimeOffset]::UtcNow
$budgetClockSchema = 'skalary/suite-budget-clock@1'

function Get-BudgetPlatformKey {
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS) { return 'MacOS' }
    return 'Linux'
}

if (-not $BudgetClockPath) {
    $rootKey = [System.IO.Path]::GetFullPath($RepoRoot)
    $digest = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($rootKey))
    $suffix = ([System.BitConverter]::ToString($digest) -replace '-', '').Substring(0, 12).ToLowerInvariant()
    $BudgetClockPath = Join-Path ([System.IO.Path]::GetTempPath()) "skalary-suite-budget-clock-$suffix.json"
}

# The clock is a file because the legs of `npm test` are separate processes: an environment
# variable set by the first one is gone by the time the last one reads it.
if ($StartBudgetClock) {
    $clock = [ordered]@{
        schema = $budgetClockSchema
        startedAt = $legStart.ToString('o')
        command = 'npm test'
    }
    Set-Content -LiteralPath $BudgetClockPath -Value (($clock | ConvertTo-Json -Depth 4) + "`n") -Encoding utf8NoBOM
    exit 0
}

# RISK-3: an environment without Pester now fails instead of skipping, so the message has to
# carry the way out of that state rather than only the diagnosis.
$installCommand = 'Install-Module Pester -Scope CurrentUser -Force'

# Read and clear the clock before anything that can exit. A clock left behind by a run that
# ended on any other branch — a failing earlier leg, an absent Pester, a red suite — would be
# charged to the next invocation, which is a failure invented rather than measured.
$clockStartedAt = $null
if (Test-Path -LiteralPath $BudgetClockPath -PathType Leaf) {
    $clockText = Get-Content -LiteralPath $BudgetClockPath -Raw
    Remove-Item -LiteralPath $BudgetClockPath -Force -ErrorAction SilentlyContinue

    $clock = $null
    try { $clock = $clockText | ConvertFrom-Json } catch { $clock = $null }
    if ($clock -and @($clock.PSObject.Properties.Name) -contains 'startedAt') {
        # ConvertFrom-Json coerces an ISO timestamp to [datetime], and casting that back to a
        # string renders it invariant (MM/dd/yyyy) while TryParse reads the current culture. On
        # a dd/MM host the two disagree and the clock is misread as ~59 days old, silently
        # discarded as residue, leaving the budget measuring this leg alone. Use the coerced
        # value directly, and parse only a value JSON left as text.
        $raw = $clock.startedAt
        if ($raw -is [datetime]) {
            $clockStartedAt = [DateTimeOffset]$raw
        }
        else {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse(
                    [string]$raw,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind,
                    [ref]$parsed)) {
                $clockStartedAt = $parsed
            }
        }
    }
}

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

if ($TestResultPath) {
    $resultDirectory = Split-Path -Parent $TestResultPath
    if ($resultDirectory -and -not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $resultDirectory -Force)
    }
    $configuration.TestResult.OutputPath = $TestResultPath
}

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

# REQ-2: the gate the ceiling exists for. A suite nobody runs because it is slow is a gate
# that is not enforced, so the runtime is checked here rather than left to whoever remembers.
$budgetPath = Join-Path $RepoRoot 'tools/suite-budget.psd1'
if (-not (Test-Path -LiteralPath $budgetPath -PathType Leaf)) {
    Write-Host "BudgetNotDefined: no budget at '$budgetPath'. The runtime ceiling is part of this gate, so a missing budget is a failure rather than an unbudgeted pass." -ForegroundColor Red
    exit 6
}

$budget = Import-PowerShellDataFile -LiteralPath $budgetPath
$platformKey = Get-BudgetPlatformKey

# D13: the same suite measured roughly 10x apart between platforms, so a platform without an
# entry has no ceiling that means anything — that is an error, not an exemption.
if (-not $budget.Contains('Platforms') -or -not $budget.Platforms.Contains($platformKey)) {
    Write-Host "BudgetNotDefined: '$budgetPath' carries no entry for platform '$platformKey'. Add one rather than letting this platform run unbudgeted." -ForegroundColor Red
    exit 6
}

$platformBudget = $budget.Platforms[$platformKey]

# Every field this check reads, named before any of them is read. Under Set-StrictMode a
# missing key is a terminating error, which would exit 1 — the code that means "tests failed",
# which is the one distinction this script exists to make.
foreach ($required in @('MeasuredCommand', 'AbsoluteCapSeconds')) {
    if (-not $budget.Contains($required)) {
        Write-Host "BudgetNotDefined: '$budgetPath' is missing '$required'. A budget that does not state it cannot be enforced." -ForegroundColor Red
        exit 6
    }
}
foreach ($required in @('HardCeilingSeconds', 'TargetSeconds')) {
    if (-not $platformBudget.Contains($required)) {
        Write-Host "BudgetNotDefined: the '$platformKey' entry in '$budgetPath' is missing '$required'. A budget that does not state it cannot be enforced." -ForegroundColor Red
        exit 6
    }
}

$hardCeilingSeconds = [double]$platformBudget.HardCeilingSeconds
$targetSeconds = [double]$platformBudget.TargetSeconds

# The budget measures the whole `npm test` command (D2). This leg can only see the rest of it
# through the clock the `pretest` hook started, so the scope is reported with the figure: an
# unclocked run measures a subset and must not be read as a verdict on the whole command.
$measuredScope = 'test:unit leg'
$measuredSeconds = ([DateTimeOffset]::UtcNow - $legStart).TotalSeconds

# Residue from a run that died before the clock could be read. The bound is the plan-wide
# absolute cap rather than this platform's ceiling: bounding it by the ceiling would discard
# exactly the clocks that prove a badly over-budget run, which is the case the check exists for.
$staleAfterSeconds = [double]$budget.AbsoluteCapSeconds * 4

if ($null -ne $clockStartedAt) {
    $clockedSeconds = ([DateTimeOffset]::UtcNow - $clockStartedAt).TotalSeconds
    if ($clockedSeconds -gt $staleAfterSeconds) {
        Write-Warning "Suite budget: ignoring a clock started $([math]::Round($clockedSeconds, 0))s ago, which is past the $($staleAfterSeconds)s no run reaches; it is residue from an abandoned run and has been cleared."
    }
    elseif ($clockedSeconds -ge $measuredSeconds) {
        $measuredScope = [string]$budget.MeasuredCommand
        $measuredSeconds = $clockedSeconds
    }
}

$measuredSeconds = [math]::Round($measuredSeconds, 3)
$budgetReport = "measured $($measuredSeconds)s ($measuredScope) against a ceiling of $($hardCeilingSeconds)s and a target of $($targetSeconds)s on $platformKey"

if ($measuredSeconds -gt $hardCeilingSeconds) {
    Write-Host "OverBudget: $budgetReport. The ceiling is bound in '$budgetPath'; make the suite cheaper rather than the ceiling higher." -ForegroundColor Red
    exit 5
}

if ($measuredSeconds -gt $targetSeconds) {
    Write-Warning "Suite budget: $budgetReport."
}
else {
    Write-Host "Suite budget: $budgetReport."
}

if ($measuredScope -ne [string]$budget.MeasuredCommand) {
    Write-Host "Suite budget: no '$($budget.MeasuredCommand)' clock was found, so the figure above covers this leg only and is a lower bound on the budgeted command." -ForegroundColor Yellow
}

exit 0
