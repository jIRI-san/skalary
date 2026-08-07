#requires -Version 7.0
<#
.SYNOPSIS
    Measures the unit suite's cost model and emits tools/suite-profile.json.
.DESCRIPTION
    Runs the whole `tests/` tree with `tests/SuiteProfile.psm1` recording enabled,
    then aggregates the samples into per-operation call counts and aggregate
    seconds, plus a per-file breakdown of where the runtime sits.

    The profile is the measurement REQ-1 requires before anything is optimised:
    it covers the whole test tree rather than one file, and it is machine-readable
    so later phases can record their achieved saving against it.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Measure-SuiteProfile.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$TestPath = 'tests',

    [string]$OutputPath,

    [string[]]$Operations = @('New-RepoClone', 'Install-Plugin', 'Build-Registry', 'Test-Registry'),

    [int]$Phase = 1,

    [string]$Label = 'baseline',

    [string]$Note = 'Baseline cost model measured before any optimisation.',

    [double]$TargetSavingSeconds = 0,

    # What the phase's saving is measured over. 'run' is the whole wall clock; an operation
    # name scopes it to that operation's aggregate seconds, which is what a phase that
    # targets one fixture cost actually moves and is measured far more precisely than a
    # 100-second wall clock.
    [string]$Scope = 'run',

    # The figure the phase is measured against, read from the profile this phase inherited.
    # Carried on the row rather than derived, because the document is rewritten each run and
    # the numbers the phase started from would otherwise be gone.
    [double]$BaselineSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$defaultOutputPath = Join-Path $repoRootPath 'tools/suite-profile.json'
if (-not $OutputPath) { $OutputPath = $defaultOutputPath }

$testRoot = Join-Path $repoRootPath $TestPath
if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) {
    throw "Test path not found: $testRoot"
}

# The committed profile is the whole-tree cost model REQ-1 requires. A subtree run writes
# somewhere else rather than overwriting it with a partial measurement.
$writesCommittedProfile = [System.IO.Path]::GetFullPath($OutputPath) -eq [System.IO.Path]::GetFullPath($defaultOutputPath)
if ($writesCommittedProfile -and ([System.IO.Path]::GetFullPath($testRoot) -ne [System.IO.Path]::GetFullPath((Join-Path $repoRootPath 'tests')))) {
    throw "Refusing to overwrite '$defaultOutputPath' from the partial scope '$TestPath'; pass -OutputPath for a subtree profile."
}

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pesterModule) {
    throw 'Pester is not installed. Install it with: Install-Module Pester -Scope CurrentUser -Force'
}
Import-Module Pester -MinimumVersion $pesterModule.Version -ErrorAction Stop

function ConvertTo-RepoRelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return 'unknown' }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $Path }
    if ($full.StartsWith($repoRootPath, [System.StringComparison]::Ordinal)) {
        $full = $full.Substring($repoRootPath.Length).TrimStart([char]'/', [char]'\')
    }
    return ($full -replace '\\', '/')
}

$testFiles = @(
    Get-ChildItem -LiteralPath $testRoot -Recurse -File -Filter '*.Tests.ps1' |
        ForEach-Object { ConvertTo-RepoRelativePath $_.FullName } |
        Sort-Object -CaseSensitive
)
if ($testFiles.Count -eq 0) {
    throw "No *.Tests.ps1 files found under $testRoot; refusing to emit an empty profile."
}

$sink = Join-Path ([System.IO.Path]::GetTempPath()) ('suite-profile-' + [guid]::NewGuid().ToString('N') + '.jsonl')
[System.IO.File]::WriteAllText($sink, '', [System.Text.UTF8Encoding]::new($false))

$previousSink = $env:SKALARY_SUITE_PROFILE
$env:SKALARY_SUITE_PROFILE = $sink

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $testRoot
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $result = Invoke-Pester -Configuration $configuration
}
finally {
    $stopwatch.Stop()
    $env:SKALARY_SUITE_PROFILE = $previousSink
}

$samples = @()
foreach ($line in [System.IO.File]::ReadAllLines($sink)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $samples += ($line | ConvertFrom-Json)
}
Remove-Item -LiteralPath $sink -Force -ErrorAction SilentlyContinue

# An all-zero profile is not a cheaper cost model, it is a lost one: the instrumentation was
# not reached, so writing it would replace measurements with silence.
if ($samples.Count -eq 0) {
    throw "No instrumentation samples were recorded for '$TestPath'; refusing to write an empty cost model to '$OutputPath'."
}

$operationReport = [System.Collections.Generic.List[object]]::new()
$observed = @($samples | ForEach-Object { [string]$_.op } | Sort-Object -Unique)
$allOperations = @($Operations) + @($observed | Where-Object { $Operations -notcontains $_ })
foreach ($operation in $allOperations) {
    $matched = @($samples | Where-Object { [string]$_.op -eq $operation })
    $total = 0.0
    foreach ($sample in $matched) { $total += [double]$sample.seconds }

    $sources = [System.Collections.Generic.List[object]]::new()
    foreach ($group in ($matched | Group-Object { ConvertTo-RepoRelativePath ([string]$_.source) } | Sort-Object Name)) {
        $sourceTotal = 0.0
        foreach ($sample in $group.Group) { $sourceTotal += [double]$sample.seconds }
        $sources.Add([ordered]@{
                source = $group.Name
                count = $group.Count
                totalSeconds = [math]::Round($sourceTotal, 3)
            })
    }

    $operationReport.Add([ordered]@{
            operation = $operation
            count = $matched.Count
            totalSeconds = [math]::Round($total, 3)
            meanSeconds = if ($matched.Count -gt 0) { [math]::Round($total / $matched.Count, 3) } else { 0 }
            sources = $sources.ToArray()
        })
}

$instrumentedSeconds = 0.0
foreach ($entry in $operationReport) { $instrumentedSeconds += [double]$entry.totalSeconds }

$wallClockSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)

# The phase's own figure. An operation scope that recorded nothing is a lost measurement,
# not a 100% saving, so it throws rather than certifying the phase on silence.
if ($Scope -eq 'run') {
    $scopeSeconds = $wallClockSeconds
}
else {
    $scoped = @($operationReport | Where-Object { [string]$_.operation -eq $Scope })
    if ($scoped.Count -ne 1 -or [int]$scoped[0].count -eq 0) {
        throw "Scope '$Scope' recorded no samples in this run; refusing to score phase $Phase against a measurement that did not happen."
    }
    $scopeSeconds = [double]$scoped[0].totalSeconds
}

$achievedSaving = if ($BaselineSeconds -gt 0) { [math]::Round($BaselineSeconds - $scopeSeconds, 3) } else { 0.0 }

$fileReport = [System.Collections.Generic.List[object]]::new()
foreach ($container in @($result.Containers)) {
    $path = $null
    if ($container.Item -and $container.Item.PSObject.Properties.Name -contains 'FullName') {
        $path = [string]$container.Item.FullName
    }
    $fileReport.Add([ordered]@{
            file = ConvertTo-RepoRelativePath $path
            seconds = [math]::Round([double]$container.Duration.TotalSeconds, 3)
            tests = [int]$container.TotalCount
        })
}
$sortedFiles = @($fileReport | Sort-Object -Property { -[double]$_.seconds })

$profileDocument = [ordered]@{
    schema = 'skalary/suite-profile@1'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
    environment = [ordered]@{
        os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
        psVersion = $PSVersionTable.PSVersion.ToString()
        pesterVersion = $pesterModule.Version.ToString()
        processorCount = [Environment]::ProcessorCount
        ci = [bool]$env:CI
    }
    scope = [ordered]@{
        root = ($TestPath -replace '\\', '/')
        pattern = '*.Tests.ps1'
        fileCount = $testFiles.Count
        testFiles = $testFiles
    }
    run = [ordered]@{
        command = "Invoke-Pester -Path $($TestPath -replace '\\', '/')"
        budgetCommand = 'npm test'
        wallClockSeconds = $wallClockSeconds
        instrumentedSeconds = [math]::Round($instrumentedSeconds, 3)
        totalTests = [int]$result.TotalCount
        passed = [int]$result.PassedCount
        failed = [int]$result.FailedCount
        skipped = [int]$result.SkippedCount
    }
    operations = $operationReport.ToArray()
    files = $sortedFiles
    phases = @(
        [ordered]@{
            phase = $Phase
            label = $Label
            scope = $Scope
            baselineSeconds = [math]::Round($BaselineSeconds, 3)
            scopeSeconds = [math]::Round($scopeSeconds, 3)
            targetSavingSeconds = [math]::Round($TargetSavingSeconds, 3)
            achievedSavingSeconds = $achievedSaving
            metTarget = ($achievedSaving -ge $TargetSavingSeconds)
            achievedSeconds = $wallClockSeconds
            note = $Note
        }
    )
}

if ($profileDocument.commit) { $profileDocument.commit = ([string]$profileDocument.commit).Trim() } else { $profileDocument.commit = 'unknown' }

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
}

# Preserve phase rows recorded by earlier runs so a later phase appends rather than overwrites.
# Rows written before the scoring fields existed are filled in with the values they implied —
# no target, no claimed saving — so every row can be read the same way.
if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
    if ($existing.PSObject.Properties.Name -contains 'phases') {
        $kept = @($existing.phases | Where-Object { [int]$_.phase -ne $Phase } | ForEach-Object {
                $row = $_
                $names = $row.PSObject.Properties.Name
                $keptTarget = if ($names -contains 'targetSavingSeconds') { [double]$row.targetSavingSeconds } else { 0.0 }
                $keptAchieved = if ($names -contains 'achievedSeconds') { [double]$row.achievedSeconds } else { 0.0 }
                $keptScopeSeconds = if ($names -contains 'scopeSeconds') { [double]$row.scopeSeconds } else { $keptAchieved }
                $keptBaseline = if ($names -contains 'baselineSeconds') { [double]$row.baselineSeconds } else { 0.0 }
                $keptSaving = if ($names -contains 'achievedSavingSeconds') {
                    [double]$row.achievedSavingSeconds
                }
                elseif ($keptBaseline -gt 0) {
                    [math]::Round($keptBaseline - $keptScopeSeconds, 3)
                }
                else {
                    # A row with nothing to be measured against claimed no saving. Subtracting
                    # its own runtime from zero would invent a large negative one.
                    0.0
                }

                [ordered]@{
                    phase = [int]$row.phase
                    label = [string]$row.label
                    scope = if ($names -contains 'scope') { [string]$row.scope } else { 'run' }
                    baselineSeconds = $keptBaseline
                    scopeSeconds = $keptScopeSeconds
                    targetSavingSeconds = $keptTarget
                    achievedSavingSeconds = $keptSaving
                    metTarget = ($keptSaving -ge $keptTarget)
                    achievedSeconds = $keptAchieved
                    note = [string]$row.note
                }
            })
        if ($kept.Count -gt 0) {
            $profileDocument.phases = @($kept + $profileDocument.phases | Sort-Object { [int]$_.phase })
        }
    }
}

Set-Content -LiteralPath $OutputPath -Value (($profileDocument | ConvertTo-Json -Depth 12) + "`n") -Encoding utf8NoBOM
Write-Host "Suite profile written to $(ConvertTo-RepoRelativePath $OutputPath) ($($profileDocument.run.wallClockSeconds)s wall clock, $($profileDocument.run.instrumentedSeconds)s instrumented)."

if ($TargetSavingSeconds -gt 0) {
    Write-Host "Phase $Phase ($Scope): baseline $([math]::Round($BaselineSeconds, 3))s, achieved $([math]::Round($scopeSeconds, 3))s, saving $($achievedSaving)s against a target of $([math]::Round($TargetSavingSeconds, 3))s."
}

if ($result.FailedCount -gt 0) {
    Write-Warning "Profile captured with $($result.FailedCount) failing test(s); the cost model is still valid but the suite is red."
}

# D4's stop condition. The row is written either way, so a miss is recorded rather than
# retried until it passes; the non-zero exit is what stops the phase continuing on silence.
if ($TargetSavingSeconds -gt 0 -and $achievedSaving -lt $TargetSavingSeconds) {
    Write-Error "Phase $Phase missed its declared target: saved $($achievedSaving)s of a required $([math]::Round($TargetSavingSeconds, 3))s on '$Scope'. Escalate rather than continuing."
    exit 1
}
