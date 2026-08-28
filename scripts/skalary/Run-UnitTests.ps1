#requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester unit-test suite, failing whenever it cannot actually test.
.DESCRIPTION
    This script is the `test:unit` leg of the repository test command and the executor
    behind every `test:` evidence marker. A green run therefore has to mean tests ran:
    reporting success having executed zero assertions forges evidence (REQ-5).

    It is also where runtime observations are reported (REQ-2), so the CI workflow REQ-9
    describes must invoke this script rather than calling
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
            5  Reserved — runtime overruns are advisory
            6  Reserved — missing budget metadata is advisory
      7  EnvironmentLeaked — a test changed the caller's process environment and did not restore it
      8  RequiredEvidenceSkipped — mandatory review evidence did not execute
      9  SuiteTierInvalid — the tracked tier manifest is absent or invalid
        10  Reserved — stale runtime measurements are advisory
     11  MeasurementTokenInvalid — a measurement-mode token failed closed validation
     12  FocusedScopeRequired — Fast did not receive focused test paths or -FullRepository
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -TestPath tests/skalary/SkillContracts.Tests.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1 -FullRepository
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [ValidateSet('Fast', 'Slow', 'All')]
    [string]$Tier = 'Fast',

    # Fast is focused by default. Callers must name the directly relevant test files;
    # the old complete Fast complement is available only through -FullRepository.
    [string[]]$TestPath = @(),

    # Optional Pester full-name filters. Required when focused Fast selects a file
    # assigned to Slow, so only the relevant sub-minute case executes.
    [string[]]$TestName = @(),

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
    $measurementNonce = $null
    $hasToken = -not [string]::IsNullOrWhiteSpace(
        [Environment]::GetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_TOKEN')
    )
    $hasKey = -not [string]::IsNullOrWhiteSpace(
        [Environment]::GetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_KEY')
    )
    if ($hasToken -or $hasKey) {
        $fingerprintScript = Join-Path $RepoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
        if (-not (Test-Path -LiteralPath $fingerprintScript -PathType Leaf)) {
            Write-Host "MeasurementTokenInvalid: fingerprint verifier '$fingerprintScript' is missing." -ForegroundColor Red
            exit 11
        }
        . $fingerprintScript
        $fingerprint = Get-SuiteInputFingerprint -RepoRoot $RepoRoot
        $authorization = Test-SuiteMeasurementAuthorization `
            -Token $env:SKALARY_SUITE_MEASUREMENT_TOKEN `
            -Key $env:SKALARY_SUITE_MEASUREMENT_KEY `
            -ExpectedFingerprint $fingerprint.Fingerprint
        if ($authorization.Status -ne 'complete') {
            Write-Host "MeasurementTokenInvalid: $($authorization.Reason)." -ForegroundColor Red
            exit 11
        }
        $claim = Use-SuiteMeasurementNonce -Nonce $authorization.Nonce `
            -ParentPid $authorization.ParentPid
        if ($claim.Status -ne 'complete') {
            Write-Host "MeasurementTokenInvalid: $($claim.Reason)." -ForegroundColor Red
            exit 11
        }
        $measurementNonce = $authorization.Nonce
    }
    $clock = [ordered]@{
        schema           = $budgetClockSchema
        startedAt        = $legStart.ToString('o')
        command          = 'npm test'
        measurementNonce = $measurementNonce
    }
    Set-Content -LiteralPath $BudgetClockPath -Value (($clock | ConvertTo-Json -Depth 4) + "`n") -Encoding utf8NoBOM
    exit 0
}

# RISK-3: an environment without Pester now fails instead of skipping, so the message has to
# carry the way out of that state rather than only the diagnosis.
$installCommand = 'Install-Module Pester -Scope CurrentUser -Force'

# Read and clear the clock only for explicit complete Fast. Focused Fast and Slow must not
# consume authorization that belongs to a concurrent or later complete run.
$clockStartedAt = $null
$clockMeasurementNonce = $null
if ($Tier -eq 'Fast' -and $FullRepository -and (Test-Path -LiteralPath $BudgetClockPath -PathType Leaf)) {
    $clockText = Get-Content -LiteralPath $BudgetClockPath -Raw
    Remove-Item -LiteralPath $BudgetClockPath -Force -ErrorAction SilentlyContinue

    $clock = $null
    try { $clock = $clockText | ConvertFrom-Json } catch { $clock = $null }
    if ($clock -and @($clock.PSObject.Properties.Name) -contains 'startedAt') {
        if (@($clock.PSObject.Properties.Name) -contains 'measurementNonce') {
            $clockMeasurementNonce = [string]$clock.measurementNonce
        }
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

$testRootPath = Join-Path $RepoRoot 'tests'
if (-not (Test-Path -LiteralPath $testRootPath -PathType Container)) {
    throw "Unit test path not found: $testRootPath"
}

$allTestFiles = @(Get-ChildItem -LiteralPath $testRootPath -Recurse -File -Filter '*.Tests.ps1')
$tierManifestPath = Join-Path $RepoRoot 'tools/suite-tier.psd1'
$slowPaths = @()
$dedicatedPaths = @()

if (Test-Path -LiteralPath $tierManifestPath -PathType Leaf) {
    try {
        $tierManifest = Import-PowerShellDataFile -LiteralPath $tierManifestPath
    }
    catch {
        Write-Host "SuiteTierInvalid: '$tierManifestPath' could not be imported: $($_.Exception.Message)" -ForegroundColor Red
        exit 9
    }

    $requiredTierMembers = @('Schema', 'SlowFiles', 'DedicatedFiles', 'FastFocusedHardCeilingSeconds', 'SlowHardCeilingSeconds', 'CiSetupAllowanceSeconds')
    $missingMembers = @($requiredTierMembers | Where-Object { -not $tierManifest.Contains($_) })
    if ($missingMembers.Count -gt 0) {
        Write-Host "SuiteTierInvalid: '$tierManifestPath' is missing required member(s): $($missingMembers -join ', ')." -ForegroundColor Red
        exit 9
    }
    if ([string]$tierManifest['Schema'] -ne 'skalary/suite-tier@1') {
        Write-Host "SuiteTierInvalid: '$tierManifestPath' has unsupported schema '$($tierManifest['Schema'])'." -ForegroundColor Red
        exit 9
    }
    foreach ($numericMember in @('FastFocusedHardCeilingSeconds', 'SlowHardCeilingSeconds', 'CiSetupAllowanceSeconds')) {
        $numericValue = 0.0
        if (-not [double]::TryParse(
                [string]$tierManifest[$numericMember],
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$numericValue) -or $numericValue -le 0) {
            Write-Host "SuiteTierInvalid: '$tierManifestPath' member '$numericMember' must be a positive number." -ForegroundColor Red
            exit 9
        }
    }

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $rootPrefix = $repoRootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $resolveTierPath = {
        param([string]$RelativePath)

        if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) {
            throw "Suite tier path must be a non-empty repository-relative path: '$RelativePath'."
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFull $RelativePath))
        if (-not $fullPath.StartsWith($rootPrefix, $pathComparison)) {
            throw "Suite tier path escapes the repository: '$RelativePath'."
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Suite tier path does not exist: '$RelativePath'."
        }
        return $fullPath
    }

    try {
        $slowPaths = @($tierManifest['SlowFiles'] | ForEach-Object { & $resolveTierPath ([string]$_) })
        $dedicatedPaths = @($tierManifest['DedicatedFiles'] | ForEach-Object { & $resolveTierPath ([string]$_) })
    }
    catch {
        Write-Host "SuiteTierInvalid: $($_.Exception.Message)" -ForegroundColor Red
        exit 9
    }

    $allDeclared = @($slowPaths) + @($dedicatedPaths)
    $distinctDeclared = @($allDeclared | Sort-Object -Unique)
    if ($distinctDeclared.Count -ne $allDeclared.Count) {
        Write-Host "SuiteTierInvalid: slow and dedicated paths must be unique and disjoint." -ForegroundColor Red
        exit 9
    }
}
else {
    Write-Host "SuiteTierInvalid: tier '$Tier' requires '$tierManifestPath'." -ForegroundColor Red
    exit 9
}

$pathComparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
$slowSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$slowPaths, $pathComparer)
$dedicatedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$dedicatedPaths, $pathComparer)

if ($Tier -ne 'Fast' -and ($FullRepository -or $TestPath.Count -gt 0 -or $TestName.Count -gt 0)) {
    Write-Host "FocusedScopeRequired: -TestPath, -TestName, and -FullRepository are valid only with -Tier Fast." -ForegroundColor Red
    exit 12
}
if ($Tier -eq 'Fast' -and $FullRepository -and ($TestPath.Count -gt 0 -or $TestName.Count -gt 0)) {
    Write-Host "FocusedScopeRequired: choose focused -TestPath/-TestName values or -FullRepository, not both." -ForegroundColor Red
    exit 12
}
if ($Tier -eq 'Fast' -and -not $FullRepository -and $TestPath.Count -eq 0) {
    Write-Host "FocusedScopeRequired: Fast requires one or more repository-relative -TestPath values. Use -FullRepository only for an explicit complete Fast run." -ForegroundColor Red
    exit 12
}
if ($Tier -eq 'Fast' -and -not $FullRepository -and
    @($TestName | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    Write-Host "FocusedScopeRequired: -TestName values must be non-empty Pester full-name filters." -ForegroundColor Red
    exit 12
}

$focusedPaths = @()
if ($Tier -eq 'Fast' -and -not $FullRepository) {
    $testsRootFull = [System.IO.Path]::GetFullPath($testRootPath)
    $testsRootPrefix = $testsRootFull.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    try {
        $focusedPaths = @($TestPath | ForEach-Object {
                $relativePath = [string]$_
                if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
                    throw "Focused test path must be a non-empty repository-relative path: '$relativePath'."
                }
                $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFull $relativePath))
                if (-not $fullPath.StartsWith($testsRootPrefix, $pathComparison) -or
                    -not $fullPath.EndsWith('.Tests.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Focused test path must name a *.Tests.ps1 file under tests/: '$relativePath'."
                }
                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    throw "Focused test path does not exist: '$relativePath'."
                }
                if ($dedicatedSet.Contains($fullPath)) {
                    throw "Focused Fast cannot bypass the dedicated runner for '$relativePath'."
                }
                if ($slowSet.Contains($fullPath) -and $TestName.Count -eq 0) {
                    throw "Focused Fast requires -TestName when selecting a Slow-tier file: '$relativePath'."
                }
                $fullPath
            } | Sort-Object -Unique)
    }
    catch {
        Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
        exit 12
    }
}

$testFiles = @(switch ($Tier) {
        'Slow' { @($allTestFiles | Where-Object { $slowSet.Contains($_.FullName) }) }
        'All' { @($allTestFiles | Where-Object { -not $dedicatedSet.Contains($_.FullName) }) }
        default {
            if ($FullRepository) {
                @($allTestFiles | Where-Object { -not $slowSet.Contains($_.FullName) -and -not $dedicatedSet.Contains($_.FullName) })
            }
            else {
                @($allTestFiles | Where-Object { $focusedPaths -contains $_.FullName })
            }
        }
    })

# Pester throws rather than returning a result when the selected tier holds no test file.
if ($testFiles.Count -eq 0) {
    Write-Host "NoTestsDiscovered: tier '$Tier' selected no *.Tests.ps1 file under '$testRootPath'." -ForegroundColor Red
    exit 3
}

$scopeLabel = if ($Tier -eq 'Fast' -and -not $FullRepository) { 'focused' } elseif ($Tier -eq 'Fast') { 'full repository' } else { 'complete tier' }
Write-Host "Suite tier: $Tier $scopeLabel ($($testFiles.Count) file(s))."

Import-Module Pester -MinimumVersion $pesterModule.Version -ErrorAction Stop

# `-CI` is Pester's shorthand for `Run.Exit` plus `TestResult.Enabled`, and `Run.Exit` makes
# Pester exit with the failure count before this script can. That collides a "could not test"
# code with "that many tests failed" — the one distinction this script exists to make — so the
# NUnit output is kept and the exit is taken back.
$configuration = New-PesterConfiguration
$configuration.Run.Path = @($testFiles.FullName)
$configuration.Run.PassThru = $true
$configuration.Run.Exit = $false
$configuration.TestResult.Enabled = $true
if ($TestName.Count -gt 0) {
    $configuration.Filter.FullName = @($TestName)
}

if ($TestResultPath) {
    $resultDirectory = Split-Path -Parent $TestResultPath
    if ($resultDirectory -and -not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $resultDirectory -Force)
    }
    $configuration.TestResult.OutputPath = $TestResultPath
}

# Pester runs in-process, so a test that assigns $env:X changes this shell and every command run
# in it afterwards. That is invisible to the suite itself: the tests pass and the damage lands on
# whoever ran them. Snapshotted here and compared below rather than trusted.
$environmentBefore = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $environmentBefore[[string]$entry.Key] = [string]$entry.Value
}

$result = Invoke-Pester -Configuration $configuration

# Test files that discover no test are the quieter half of the same failure: Pester returns a
# clean zero-failure result, so the run would otherwise be reported as a pass having asserted
# nothing (REQ-5).
if ($null -eq $result -or [int]$result.TotalCount -le 0) {
    Write-Host "NoTestsDiscovered: Pester $($pesterModule.Version) discovered 0 tests in $($testFiles.Count) file(s) under '$testRootPath'. A run that asserts nothing is not a pass." -ForegroundColor Red
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

# Stable review-report evidence ids are mandatory on every supported leg. Deterministic seams keep
# these cases executable; a skip is an unexecuted evidence marker, not a pass.
$skippedReviewEvidence = @($result.Tests | Where-Object {
        [string]$_.Result -eq 'Skipped' -and [string]$_.Name -match '^test:ReviewReport\.'
    })
if ($skippedReviewEvidence.Count -gt 0) {
    $names = @($skippedReviewEvidence | ForEach-Object { [string]$_.Name })
    Write-Host "RequiredEvidenceSkipped: $($skippedReviewEvidence.Count) review-report evidence test(s) did not execute: $($names -join ', ')" -ForegroundColor Red
    exit 8
}

# A green suite that leaves HOME pointing at TestDrive is still a defect: it sends git looking for
# .gitconfig and .ssh in a deleted temp directory for the rest of the shell's life, and nothing in
# the run reports it. Checked after the failure gates so a real test failure keeps the clearer code.
$environmentAfter = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $environmentAfter[[string]$entry.Key] = [string]$entry.Value
}

$leakedNames = [System.Collections.Generic.List[string]]::new()
$candidateNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($environmentBefore.Keys))
$candidateNames.UnionWith([string[]]@($environmentAfter.Keys))
foreach ($name in ($candidateNames | Sort-Object)) {
    $before = if ($environmentBefore.ContainsKey($name)) { $environmentBefore[$name] } else { $null }
    $after = if ($environmentAfter.ContainsKey($name)) { $environmentAfter[$name] } else { $null }
    if ($before -ne $after) {
        # Rendered rather than interpolated: an unset variable and one set to '' both interpolate to
        # nothing, which turns a real difference into the unreadable "('' -> '')".
        $shown = { param($v) if ($null -eq $v) { '<unset>' } else { "'$v'" } }
        $leakedNames.Add("$name ($(& $shown $before) -> $(& $shown $after))")
    }
}

if ($leakedNames.Count -gt 0) {
    Write-Host "EnvironmentLeaked: the suite changed $($leakedNames.Count) environment variable(s) and did not restore them: $($leakedNames -join '; '). Snapshot and restore them in the owning test." -ForegroundColor Red
    exit 7
}

if ($Tier -eq 'Slow') {
    $slowSeconds = ([DateTimeOffset]::UtcNow - $legStart).TotalSeconds
    $slowCeiling = [double]$tierManifest['SlowHardCeilingSeconds']
    Write-Host "Slow tier runtime: $([math]::Round($slowSeconds, 3))s against a ceiling of ${slowCeiling}s."
    if ($slowSeconds -gt $slowCeiling) {
        Write-Warning "OverBudget: Slow tier runtime $([math]::Round($slowSeconds, 3))s exceeded its ${slowCeiling}s advisory ceiling."
    }
    exit 0
}
if ($Tier -eq 'All') {
    Write-Host "Suite budget: not applied to diagnostic tier 'All'."
    exit 0
}
if (-not $FullRepository) {
    $focusedSeconds = ([DateTimeOffset]::UtcNow - $legStart).TotalSeconds
    $focusedCeiling = [double]$tierManifest['FastFocusedHardCeilingSeconds']
    Write-Host "Focused Fast runtime: $([math]::Round($focusedSeconds, 3))s against a ceiling of ${focusedCeiling}s."
    if ($focusedSeconds -gt $focusedCeiling) {
        Write-Warning "OverBudget: Focused Fast runtime $([math]::Round($focusedSeconds, 3))s exceeded its ${focusedCeiling}s advisory ceiling."
    }
    exit 0
}

# Runtime metadata is retained for visibility while enforcement is deferred to a future redesign.
$budgetPath = Join-Path $RepoRoot 'tools/suite-budget.psd1'
if (-not (Test-Path -LiteralPath $budgetPath -PathType Leaf)) {
    Write-Warning "BudgetNotDefined: no advisory budget at '$budgetPath'; runtime measurement is unavailable."
    exit 0
}

try {
    $budget = Import-PowerShellDataFile -LiteralPath $budgetPath
}
catch {
    Write-Warning "BudgetNotDefined: advisory budget '$budgetPath' could not be read: $($_.Exception.Message)"
    exit 0
}
$platformKey = Get-BudgetPlatformKey

# D13: the same suite measured roughly 10x apart between platforms, so observations remain
# platform-specific even though a missing entry is advisory.
if (-not $budget.Contains('Platforms') -or -not $budget.Platforms.Contains($platformKey)) {
    Write-Warning "BudgetNotDefined: '$budgetPath' carries no advisory entry for platform '$platformKey'."
    exit 0
}

$platformBudget = $budget.Platforms[$platformKey]

# Every field this check reads, named before any of them is read. Under Set-StrictMode a
# missing key is a terminating error, which would exit 1 — the code that means "tests failed",
# which is the one distinction this script exists to make.
foreach ($required in @('MeasuredCommand', 'AbsoluteCapSeconds', 'MeasurementRecord')) {
    if (-not $budget.Contains($required)) {
        Write-Warning "BudgetNotDefined: '$budgetPath' is missing advisory field '$required'."
        exit 0
    }
}
if ([string]::IsNullOrWhiteSpace([string]$budget.MeasurementRecord)) {
    Write-Warning "BudgetNotDefined: '$budgetPath' has an empty advisory 'MeasurementRecord'."
    exit 0
}
foreach ($required in @('HardCeilingSeconds', 'TargetSeconds')) {
    if (-not $platformBudget.Contains($required)) {
        Write-Warning "BudgetNotDefined: the '$platformKey' entry in '$budgetPath' is missing advisory field '$required'."
        exit 0
    }
}

try {
    $hardCeilingSeconds = [double]$platformBudget.HardCeilingSeconds
    $targetSeconds = [double]$platformBudget.TargetSeconds
    $staleAfterSeconds = [double]$budget.AbsoluteCapSeconds * 4
}
catch {
    Write-Warning "BudgetNotDefined: advisory budget '$budgetPath' contains an invalid numeric value: $($_.Exception.Message)"
    exit 0
}

$fingerprintScript = Join-Path $RepoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
if (-not (Test-Path -LiteralPath $fingerprintScript -PathType Leaf)) {
    Write-Warning "BudgetNotDefined: '$budgetPath' names a measurement record but advisory fingerprint script '$fingerprintScript' is missing."
    exit 0
}
try {
    . $fingerprintScript
    $freshness = Test-SuiteRuntimeFreshness -RepoRoot $RepoRoot -Budget $budget `
        -PlatformKey $platformKey -ExpectedNonce $clockMeasurementNonce `
        -CurrentProcessId $PID
    if ($freshness.Status -eq 'measurement-token-invalid') {
        Write-Host "MeasurementTokenInvalid: $($freshness.Reason)." -ForegroundColor Red
        exit 11
    }
    if ($freshness.Status -ne 'complete') {
        Write-Warning "StaleMeasurement: $($freshness.Reason). Runtime rows are advisory; refresh them later with scripts/skalary/Measure-SuiteRuntime.ps1."
    }
    if ($freshness.MeasurementMode) {
        Write-Host "Suite budget: authorized measurement mode for fingerprint $($freshness.Fingerprint.Fingerprint); stale runtime rows are permitted for this run only."
    }
}
catch {
    Write-Warning "StaleMeasurement: advisory runtime freshness could not be evaluated: $($_.Exception.Message)"
    exit 0
}

# The budget measures the whole `npm test` command (D2). This leg can only see the rest of it
# through the clock the `pretest` hook started, so the scope is reported with the figure: an
# unclocked run measures a subset and must not be read as a verdict on the whole command.
$measuredScope = 'test:unit leg'
$measuredSeconds = ([DateTimeOffset]::UtcNow - $legStart).TotalSeconds

# Residue from a run that died before the clock could be read. The bound is the plan-wide
# absolute cap rather than this platform's ceiling: bounding it by the ceiling would discard
# exactly the clocks that prove a badly over-budget run, which is the case the check exists for.
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
    Write-Warning "OverBudget: $budgetReport. Runtime budgets are advisory pending test-infrastructure redesign."
}
elseif ($measuredSeconds -gt $targetSeconds) {
    Write-Warning "Suite budget: $budgetReport."
}
else {
    Write-Host "Suite budget: $budgetReport."
}

if ($measuredScope -ne [string]$budget.MeasuredCommand) {
    Write-Host "Suite budget: no '$($budget.MeasuredCommand)' clock was found, so the figure above covers this leg only and is a lower bound on the budgeted command." -ForegroundColor Yellow
}

exit 0
