#requires -Version 7.0
<#
.SYNOPSIS
    Measures the budgeted command end to end and records the figure with its environment.
.DESCRIPTION
    `tools/suite-budget.psd1` budgets the whole `npm test` command per platform (D2, D13).
    This script produces the figure that budget is tightened against: it runs the budgeted
    command, times it end to end, and writes a row for the platform it ran on into
    `tools/suite-runtime.json`.

    A figure without its environment is not a measurement — the same suite ran roughly 10x
    apart between the Linux container and a Windows host, so a bare number cannot be
    attributed to a ceiling. Every row therefore carries the OS, PowerShell and Pester
    versions, processor count, commit and provenance label alongside the seconds.

    A failed run is not recorded. The budgeted command is a `&&` chain, so a failure stops it
    early and its wall clock is *shorter* than a green run's: recording it would tighten the
    ceiling against a run that did less work than the one the ceiling governs.

    Platforms this host cannot run are measured where they exist and imported here. The run
    prints its row as a single `SUITE-RUNTIME-ROW:` line, and `-ImportRow` merges exactly that
    line back, so a CI-measured figure lands through the same writer as a local one instead of
    being hand-copied into the document.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Measure-SuiteRuntime.ps1 -Source container:autopilot
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Measure-SuiteRuntime.ps1 -ImportRow '{"platform":"Windows",...}'
#>
[CmdletBinding(DefaultParameterSetName = 'Measure')]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$OutputPath,

    # Where the figure came from, so a row can be read back as evidence rather than as a
    # number of unknown provenance: 'container:autopilot', 'ci:windows-latest', 'host:...'.
    [Parameter(ParameterSetName = 'Measure')]
    [string]$Source = 'local',

    [Parameter(ParameterSetName = 'Measure')]
    [string]$Note = '',

    # Measure only; do not write the document. Used by a host that reports its row elsewhere.
    [Parameter(ParameterSetName = 'Measure')]
    [switch]$NoWrite,

    # Merge a row emitted by another host's run, verbatim.
    [Parameter(Mandatory, ParameterSetName = 'Import')]
    [string]$ImportRow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)

$budgetPath = Join-Path $repoRootPath 'tools/suite-budget.psd1'
if (-not (Test-Path -LiteralPath $budgetPath -PathType Leaf)) {
    throw "Budget not found at '$budgetPath'; there is nothing for a measurement to be recorded against."
}
$budget = Import-PowerShellDataFile -LiteralPath $budgetPath
if (-not $budget.Contains('MeasuredCommand')) {
    throw "'$budgetPath' does not state a MeasuredCommand, so there is nothing to measure against."
}
$measuredCommand = [string]$budget.MeasuredCommand

# The budget names the document its figures live in, so the two cannot drift apart.
if (-not $OutputPath) {
    if (-not $budget.Contains('MeasurementRecord')) {
        throw "'$budgetPath' does not name a MeasurementRecord for the achieved figures to be written to."
    }
    $OutputPath = Join-Path $repoRootPath ([string]$budget.MeasurementRecord)
}

$rowSchema = 'skalary/suite-runtime-row@1'
$documentSchema = 'skalary/suite-runtime@1'
$rowMarker = 'SUITE-RUNTIME-ROW:'

function Get-CurrentPlatformKey {
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS) { return 'MacOS' }
    return 'Linux'
}

function ConvertTo-CanonicalRow {
    <#
    .SYNOPSIS
        Puts a row's fields in a fixed order.
    .DESCRIPTION
        A row that arrives from another host is deserialised in whatever order it was written,
        so merging one would otherwise reshuffle the document and turn a one-figure change into
        a whole-file diff.
    #>
    param($Row)

    function ConvertTo-PropertyMap {
        param($Value)
        $map = @{}
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) { $map[[string]$key] = $Value[$key] }
        }
        else {
            foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = $property.Value }
        }
        return $map
    }

    $source = ConvertTo-PropertyMap -Value $Row

    $environment = [ordered]@{}
    if ($source.ContainsKey('environment') -and $null -ne $source['environment']) {
        $raw = ConvertTo-PropertyMap -Value $source['environment']
        foreach ($field in @('os', 'psVersion', 'pesterVersion', 'processorCount', 'ci', 'runner')) {
            if ($raw.ContainsKey($field)) { $environment[$field] = $raw[$field] }
        }
        foreach ($field in @($raw.Keys | Sort-Object -CaseSensitive)) {
            if (-not $environment.Contains($field)) { $environment[$field] = $raw[$field] }
        }
    }

    $canonical = [ordered]@{}
    foreach ($field in @('schema', 'platform', 'measuredCommand', 'seconds', 'succeeded', 'measuredAt', 'commit', 'tree', 'source', 'note')) {
        if ($source.ContainsKey($field)) { $canonical[$field] = $source[$field] }
    }
    $canonical['environment'] = $environment
    return $canonical
}

function Write-RuntimeDocument {
    param($Row)

    $canonical = ConvertTo-CanonicalRow -Row ([pscustomobject]$Row)
    $platform = [string]$canonical.platform
    if (-not $platform) { throw 'A runtime row must name the platform it was measured on.' }

    $rows = [ordered]@{}
    if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        $existing = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
        if ($existing.PSObject.Properties.Name -contains 'platforms') {
            foreach ($property in $existing.platforms.PSObject.Properties) {
                $rows[$property.Name] = ConvertTo-CanonicalRow -Row $property.Value
            }
        }
    }
    $rows[$platform] = $canonical

    $ordered = [ordered]@{}
    foreach ($key in @($rows.Keys | Sort-Object -CaseSensitive)) { $ordered[$key] = $rows[$key] }

    $document = [ordered]@{
        schema = $documentSchema
        measuredCommand = $measuredCommand
        platforms = $ordered
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
    }
    Set-Content -LiteralPath $OutputPath -Value (($document | ConvertTo-Json -Depth 12) + "`n") -Encoding utf8NoBOM

    $ceiling = 'no ceiling recorded'
    if ($budget.Contains('Platforms') -and $budget.Platforms.Contains($platform)) {
        $ceiling = "ceiling $($budget.Platforms[$platform].HardCeilingSeconds)s"
    }
    Write-Host "Recorded $platform at $($canonical.seconds)s in $OutputPath ($ceiling)."
}

if ($PSCmdlet.ParameterSetName -eq 'Import') {
    $payload = $ImportRow.Trim()
    $markerIndex = $payload.IndexOf($rowMarker, [System.StringComparison]::Ordinal)
    if ($markerIndex -ge 0) { $payload = $payload.Substring($markerIndex + $rowMarker.Length).Trim() }

    $imported = $payload | ConvertFrom-Json
    if ([string]$imported.schema -ne $rowSchema) {
        throw "Refusing to import a row of schema '$($imported.schema)'; expected '$rowSchema'."
    }
    if ([string]$imported.measuredCommand -ne $measuredCommand) {
        throw "Refusing to import a row measured against '$($imported.measuredCommand)' into a budget for '$measuredCommand'."
    }
    if (-not [bool]$imported.succeeded) {
        throw 'Refusing to import a row from a failed run: a stopped command did less work than the one the ceiling governs.'
    }

    $row = [ordered]@{}
    foreach ($property in $imported.PSObject.Properties) { $row[$property.Name] = $property.Value }
    Write-RuntimeDocument -Row ([pscustomobject]$row)
    exit 0
}

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

$null = & git -C $repoRootPath diff --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) {
    throw "Refusing to measure tracked working-tree content that differs from the index. Stage every input before measuring '$measuredCommand'."
}
$untrackedBefore = @(& git -C $repoRootPath ls-files --others --exclude-standard 2>$null)
if ($LASTEXITCODE -ne 0) { throw "Cannot inspect untracked inputs before measuring '$measuredCommand'." }
if ($untrackedBefore.Count -gt 0) {
    throw "Refusing to measure with untracked inputs: $($untrackedBefore -join '; ')"
}
$treeBefore = (& git -C $repoRootPath write-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$treeBefore)) {
    throw 'Cannot resolve the staged tree before measurement.'
}
$treeBefore = ([string]$treeBefore).Trim()

Push-Location -LiteralPath $repoRootPath
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    # The budgeted command verbatim, so the figure and the ceiling measure the same thing.
    & npm test
    $exitCode = $LASTEXITCODE
}
finally {
    $stopwatch.Stop()
    Pop-Location
}

$treeAfter = (& git -C $repoRootPath write-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or ([string]$treeAfter).Trim() -cne $treeBefore) {
    throw "The index changed while '$measuredCommand' ran; refusing to attribute the result to a moving staged tree."
}
$null = & git -C $repoRootPath diff --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) {
    throw "The working tree changed while '$measuredCommand' ran; refusing to record a receipt for inputs that differ from staged tree '$treeBefore'."
}
$untrackedAfter = @(& git -C $repoRootPath ls-files --others --exclude-standard 2>$null)
if ($LASTEXITCODE -ne 0 -or $untrackedAfter.Count -gt 0) {
    throw "Untracked inputs appeared while '$measuredCommand' ran; refusing to record a receipt for staged tree '$treeBefore'."
}

$commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
$row = [ordered]@{
    schema = $rowSchema
    platform = Get-CurrentPlatformKey
    measuredCommand = $measuredCommand
    seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    succeeded = ($exitCode -eq 0)
    measuredAt = [DateTimeOffset]::UtcNow.ToString('o')
    commit = if ($commit) { ([string]$commit).Trim() } else { 'unknown' }
    tree = $treeBefore
    source = $Source
    note = $Note
    environment = [ordered]@{
        os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
        psVersion = $PSVersionTable.PSVersion.ToString()
        pesterVersion = if ($pesterModule) { $pesterModule.Version.ToString() } else { 'absent' }
        processorCount = [Environment]::ProcessorCount
        ci = [bool]$env:CI
        runner = if ($env:RUNNER_NAME) { [string]$env:RUNNER_NAME } else { [Environment]::MachineName }
    }
}

# Emitted whether or not the run passed: the row is how another host reports back, and a
# failed run has to be visible as failed rather than absent.
Write-Host "$rowMarker $($row | ConvertTo-Json -Depth 12 -Compress)"

if ($exitCode -ne 0) {
    Write-Error "'$measuredCommand' exited $exitCode after $($row.seconds)s; refusing to record a figure from a run that stopped early."
    exit 1
}

if (-not $NoWrite) { Write-RuntimeDocument -Row $row }

exit 0
