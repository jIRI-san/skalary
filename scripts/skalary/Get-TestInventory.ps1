#requires -Version 7.0
<#
.SYNOPSIS
    Captures the test-name inventory of the whole `tests/` tree.
.DESCRIPTION
    Pester discovery only — no test executes — so the inventory is cheap enough
    to run inside the suite itself as the coverage guard REQ-3 requires.

    Pester exposes test counts, not assertion counts, and `-TestCases` expands one
    `It` into N executions that can share a single expanded name. The inventory
    therefore records a per-name occurrence count: consolidating five cases into
    one is a coverage change the name list alone cannot see.

    Writing over an existing inventory preserves its `mustKeep` and `removals`
    entries and refuses to drop any recorded name that is not already enumerated as
    a removal, so regenerating the file cannot become the way round the reason
    requirement.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Get-TestInventory.ps1 -OutputPath tools/suite-coverage-baseline.json
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$TestPath = 'tests',

    [string]$OutputPath,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$testRoot = Join-Path $repoRootPath $TestPath
if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) {
    throw "Test path not found: $testRoot"
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

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$discovery = Invoke-Pester -Configuration $configuration

$entries = @{}
foreach ($test in @($discovery.Tests)) {
    $name = [string]$test.ExpandedPath
    if ([string]::IsNullOrWhiteSpace($name)) { $name = ($test.Path -join '.') }
    $file = ConvertTo-RepoRelativePath ([string]$test.ScriptBlock.File)

    $key = "$file|$name"
    if ($entries.ContainsKey($key)) {
        $entries[$key].count++
    }
    else {
        $entries[$key] = [pscustomobject]@{ file = $file; test = $name; count = 1 }
    }
}

if ($entries.Count -eq 0) {
    throw "Pester discovered no tests under $testRoot; refusing to write an empty inventory."
}

$tests = @(
    $entries.Values |
        Sort-Object -Property @{ Expression = 'file' }, @{ Expression = 'test' } |
        ForEach-Object { [ordered]@{ file = $_.file; test = $_.test; count = $_.count } }
)

$totalExecutions = 0
foreach ($entry in $tests) { $totalExecutions += [int]$entry.count }

$mustKeep = @()
$removals = @()
if ($OutputPath -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    $existing = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
    if ($existing.PSObject.Properties.Name -contains 'mustKeep') { $mustKeep = @($existing.mustKeep) }
    if ($existing.PSObject.Properties.Name -contains 'removals') { $removals = @($existing.removals) }

    # Regenerating must not be a way around the removal list: a name that shrinks or disappears
    # has to be enumerated with a reason first, or the guard would defend whatever it was last
    # overwritten with.
    $recordedRemovals = @($removals | ForEach-Object { [string]$_.test })
    $liveCounts = @{}
    foreach ($entry in $tests) {
        $name = [string]$entry.test
        if ($liveCounts.ContainsKey($name)) { $liveCounts[$name] += [int]$entry.count }
        else { $liveCounts[$name] = [int]$entry.count }
    }

    $previousCounts = @{}
    foreach ($entry in @($existing.tests)) {
        $name = [string]$entry.test
        if ($previousCounts.ContainsKey($name)) { $previousCounts[$name] += [int]$entry.count }
        else { $previousCounts[$name] = [int]$entry.count }
    }

    $dropped = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $previousCounts.Keys) {
        if ($recordedRemovals -contains $name) { continue }
        if (-not $liveCounts.ContainsKey($name)) {
            $dropped.Add("$name (gone)")
        }
        elseif ($liveCounts[$name] -lt $previousCounts[$name]) {
            $dropped.Add("$name ($($liveCounts[$name]) of $($previousCounts[$name]) case(s) left)")
        }
    }

    if ($dropped.Count -gt 0) {
        throw ("Refusing to shrink '$OutputPath': $($dropped.Count) test name(s) would be dropped without an enumerated removal - " +
            ($dropped -join '; ') +
            ". Add a removals entry with a test, reason and step for each, then regenerate.")
    }
}

$commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) { $commit = 'unknown' } else { $commit = $commit.Trim() }

$inventory = [ordered]@{
    schema = 'skalary/suite-coverage@1'
    capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
    commit = $commit
    scope = [ordered]@{
        root = ($TestPath -replace '\\', '/')
        pattern = '*.Tests.ps1'
    }
    uniqueTestCount = $tests.Count
    executionCount = $totalExecutions
    tests = $tests
    mustKeep = $mustKeep
    removals = $removals
}

if ($OutputPath) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
    }
    Set-Content -LiteralPath $OutputPath -Value (($inventory | ConvertTo-Json -Depth 8) + "`n") -Encoding utf8NoBOM
    Write-Host "Test inventory written to $(ConvertTo-RepoRelativePath $OutputPath) ($($tests.Count) unique names, $totalExecutions executions)."
}

if ($PassThru -or -not $OutputPath) {
    $inventory | ConvertTo-Json -Depth 8
}
