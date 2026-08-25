#requires -Version 7.0
<#
.SYNOPSIS
    Measures the budgeted command end to end and records the figure with its environment.
.DESCRIPTION
    `tools/suite-budget.psd1` budgets the whole `npm test` command per platform (D2, D13).
    This script produces the figure that budget is tightened against: it runs the budgeted
    command, times it end to end, and writes a row for the platform it ran on into
    `tools/suite-runtime.json`.

    A figure without its environment and exact tracked-input fingerprint is not a measurement —
    the same suite ran roughly 10x
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

    [Parameter(ParameterSetName = 'Measure')]
    [ValidateSet('Fast', 'Slow')]
    [string]$Tier = 'Fast',

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
. (Join-Path $repoRootPath 'scripts/skalary/Get-SuiteInputFingerprint.ps1')

$budgetPath = Join-Path $repoRootPath 'tools/suite-budget.psd1'
if (-not (Test-Path -LiteralPath $budgetPath -PathType Leaf)) {
    throw "Budget not found at '$budgetPath'; there is nothing for a measurement to be recorded against."
}
$budget = Import-PowerShellDataFile -LiteralPath $budgetPath
if (-not $budget.Contains('MeasuredCommand')) {
    throw "'$budgetPath' does not state a MeasuredCommand, so there is nothing to measure against."
}
$measuredCommand = [string]$budget.MeasuredCommand
$tierManifest = $null
if ($Tier -eq 'Slow') {
    $tierManifestPath = Join-Path $repoRootPath 'tools/suite-tier.psd1'
    $tierManifest = Import-PowerShellDataFile -LiteralPath $tierManifestPath
    $measuredCommand = 'npm run test:slow'
}

# The budget names the document its figures live in, so the two cannot drift apart.
if (-not $OutputPath) {
    $recordMember = if ($Tier -eq 'Slow') { 'SlowMeasurementRecord' } else { 'MeasurementRecord' }
    $recordOwner = if ($Tier -eq 'Slow') { $tierManifest } else { $budget }
    if (-not $recordOwner.Contains($recordMember)) {
        throw "The $Tier runtime contract does not name '$recordMember' for achieved figures."
    }
    $OutputPath = Join-Path $repoRootPath ([string]$recordOwner[$recordMember])
}

$rowSchema = 'skalary/suite-runtime-row@2'
$documentSchema = 'skalary/suite-runtime@2'
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

    $source = @{}
    foreach ($property in $Row.PSObject.Properties) { $source[$property.Name] = $property.Value }

    $environment = [ordered]@{}
    if ($source.ContainsKey('environment') -and $null -ne $source['environment']) {
        $raw = @{}
        if ($source['environment'] -is [System.Collections.IDictionary]) {
            foreach ($key in $source['environment'].Keys) {
                $raw[[string]$key] = $source['environment'][$key]
            }
        }
        else {
            foreach ($property in $source['environment'].PSObject.Properties) {
                $raw[$property.Name] = $property.Value
            }
        }
        foreach ($field in @('os', 'psVersion', 'pesterVersion', 'processorCount', 'ci', 'runner')) {
            if ($raw.ContainsKey($field)) { $environment[$field] = $raw[$field] }
        }
        foreach ($field in @($raw.Keys | Sort-Object -CaseSensitive)) {
            if (-not $environment.Contains($field)) { $environment[$field] = $raw[$field] }
        }
    }

    $canonical = [ordered]@{}
    foreach ($field in @(
            'schema', 'platform', 'measuredCommand', 'fingerprintProtocol', 'inputFingerprint',
            'seconds', 'succeeded', 'measuredAt', 'commit', 'source', 'note'
        )) {
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
                $existingRow = ConvertTo-CanonicalRow -Row $property.Value
                if (
                    [string]$existingRow.schema -eq $rowSchema -and
                    [string]$existingRow.fingerprintProtocol -eq
                    [string]$canonical.fingerprintProtocol -and
                    [string]$existingRow.inputFingerprint -eq
                    [string]$canonical.inputFingerprint
                ) {
                    $rows[$property.Name] = $existingRow
                }
            }
        }
    }
    $rows[$platform] = $canonical

    $ordered = [ordered]@{}
    foreach ($key in @($rows.Keys | Sort-Object -CaseSensitive)) { $ordered[$key] = $rows[$key] }

    $document = [ordered]@{
        schema          = $documentSchema
        measuredCommand = $measuredCommand
        platforms       = $ordered
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
    }
    Set-Content -LiteralPath $OutputPath -Value (($document | ConvertTo-Json -Depth 12) + "`n") -Encoding utf8NoBOM

    $ceiling = 'no ceiling recorded'
    if ($Tier -eq 'Slow') {
        $ceiling = "ceiling $($tierManifest.SlowHardCeilingSeconds)s"
    }
    elseif ($budget.Contains('Platforms') -and $budget.Platforms.Contains($platform)) {
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
    $importFingerprint = Get-SuiteInputFingerprint -RepoRoot $repoRootPath
    if ([string]$imported.fingerprintProtocol -ne $importFingerprint.Protocol -or
        [string]$imported.inputFingerprint -ne $importFingerprint.Fingerprint) {
        throw 'Refusing to import a runtime row measured against a different tracked-input fingerprint.'
    }

    $row = [ordered]@{}
    foreach ($property in $imported.PSObject.Properties) { $row[$property.Name] = $property.Value }
    Write-RuntimeDocument -Row ([pscustomobject]$row)
    exit 0
}

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
$measurementFingerprint = Get-SuiteInputFingerprint -RepoRoot $repoRootPath
$authorization = New-SuiteMeasurementAuthorization `
    -Fingerprint $measurementFingerprint.Fingerprint -ParentPid $PID
$previousToken = [Environment]::GetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_TOKEN')
$previousKey = [Environment]::GetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_KEY')

Push-Location -LiteralPath $repoRootPath
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    [Environment]::SetEnvironmentVariable(
        'SKALARY_SUITE_MEASUREMENT_TOKEN',
        $authorization.Token
    )
    [Environment]::SetEnvironmentVariable(
        'SKALARY_SUITE_MEASUREMENT_KEY',
        $authorization.Key
    )
    # The budgeted command verbatim, so the figure and the ceiling measure the same thing.
    if ($Tier -eq 'Slow') { & npm run test:slow } else { & npm test }
    $exitCode = $LASTEXITCODE
}
finally {
    if ($null -eq $previousToken) {
        Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_TOKEN', $previousToken)
    }
    if ($null -eq $previousKey) {
        Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('SKALARY_SUITE_MEASUREMENT_KEY', $previousKey)
    }
    $stopwatch.Stop()
    Pop-Location
}

$afterFingerprint = Get-SuiteInputFingerprint -RepoRoot $repoRootPath
if ($exitCode -eq 0 -and
    $afterFingerprint.Fingerprint -ne $measurementFingerprint.Fingerprint) {
    Write-Error 'The tracked-input fingerprint changed during measurement; refusing to emit a row for mixed inputs.'
    exit 1
}

$commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
$row = [ordered]@{
    schema              = $rowSchema
    platform            = Get-CurrentPlatformKey
    measuredCommand     = $measuredCommand
    fingerprintProtocol = $measurementFingerprint.Protocol
    inputFingerprint    = $measurementFingerprint.Fingerprint
    seconds             = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    succeeded           = ($exitCode -eq 0)
    measuredAt          = [DateTimeOffset]::UtcNow.ToString('o')
    commit              = if ($commit) { ([string]$commit).Trim() } else { 'unknown' }
    source              = $Source
    note                = $Note
    environment         = [ordered]@{
        os             = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
        psVersion      = $PSVersionTable.PSVersion.ToString()
        pesterVersion  = if ($pesterModule) { $pesterModule.Version.ToString() } else { 'absent' }
        processorCount = [Environment]::ProcessorCount
        ci             = [bool]$env:CI
        runner         = if ($env:RUNNER_NAME) { [string]$env:RUNNER_NAME } else { [Environment]::MachineName }
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
