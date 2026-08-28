#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][string]$RunPath,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]$InstalledPluginVersion,
    [string]$OutputPath = 'docs/self-improvement/cross-repo-export.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$maxRunBytes = 1MB
$maxArtifactBytes = 64KB
$protocol = 'cross-repo-si-export/v1'

$atomicModule = Join-Path $PSScriptRoot 'AtomicStore.psm1'
if (-not (Test-Path -LiteralPath $atomicModule -PathType Leaf)) {
    $atomicModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/si/scripts/AtomicStore.psm1'
}
Import-Module $atomicModule -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force

function Get-CrossRepoExportId {
    param([Parameter(Mandatory)][string]$CanonicalPayload)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($protocol + $CanonicalPayload)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function ConvertTo-RedactedSiText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $value = $Text
    $value = [regex]::Replace(
        $value,
        '(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
        '[REDACTED_PRIVATE_KEY]'
    )
    $value = [regex]::Replace(
        $value,
        '(?i)\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,})\b',
        '[REDACTED_TOKEN]'
    )
    $value = [regex]::Replace(
        $value,
        '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{16,}=*',
        'Bearer [REDACTED_TOKEN]'
    )
    $value = [regex]::Replace(
        $value,
        '(?i)\b(token|password|secret|api[_-]?key)\b(\s*[:=]\s*)(["'']?)[^\s,"'']{8,}\3',
        '$1$2[REDACTED_SECRET]'
    )
    $value = [regex]::Replace($value, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
    return $value
}

function ConvertTo-SafeMetadata {
    param([Parameter(Mandatory)][string]$Value)
    $safe = [regex]::Replace($Value, '[\r\n"]', '_')
    return ConvertTo-RedactedSiText -Text $safe
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$runFull = [System.IO.Path]::GetFullPath(
    $(if ([System.IO.Path]::IsPathRooted($RunPath)) { $RunPath } else { Join-Path $repoRootFull $RunPath })
)
$outputFull = [System.IO.Path]::GetFullPath(
    $(if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRootFull $OutputPath })
)
if (-not (Test-Path -LiteralPath $runFull -PathType Leaf)) {
    throw "SI run '$runFull' was not found."
}
if ((Get-Item -LiteralPath $runFull).Length -gt $maxRunBytes) {
    throw "capacity-blocked: SI run exceeds the $maxRunBytes-byte export input ceiling."
}

$runText = [System.IO.File]::ReadAllText($runFull)
$runSchema = Join-Path (Split-Path -Parent $PSScriptRoot) 'schemas/run.schema.json'
if (-not ($runText | Test-Json -SchemaFile $runSchema -ErrorAction SilentlyContinue)) {
    throw 'SI run failed its closed schema validation.'
}
try { $run = $runText | ConvertFrom-Json -Depth 100 }
catch { throw "SI run is malformed JSON: $($_.Exception.Message)" }
$required = @('runId', 'dueId', 'status', 'provenance', 'rankedSet', 'choices', 'proposalPr')
if (@($required | Where-Object { $run.PSObject.Properties.Name -notcontains $_ }).Count -gt 0) {
    throw 'SI run is missing required durable activity fields.'
}
if ($run.status -notin @('ranked', 'proposal-pending', 'no-candidates', 'completed')) {
    throw "SI run status '$($run.status)' is not exportable."
}
if (@($run.rankedSet.candidates).Count -gt 5 -or
    [int]$run.rankedSet.count -ne @($run.rankedSet.candidates).Count) {
    throw 'SI run candidate set exceeds the closed export bounds.'
}

$choiceById = @{}
foreach ($choice in @($run.choices)) {
    if ($choiceById.ContainsKey([string]$choice.candidateId)) {
        throw "SI run contains duplicate disposition for '$($choice.candidateId)'."
    }
    $choiceById[[string]$choice.candidateId] = $choice
}

$candidates = [System.Collections.Generic.List[object]]::new()
foreach ($candidate in @($run.rankedSet.candidates)) {
    $candidateId = [string]$candidate.candidateId
    if ($candidateId -notmatch '^[0-9a-f]{64}$') {
        throw 'SI run contains an invalid candidate identity.'
    }
    $title = ConvertTo-RedactedSiText -Text ([string]$candidate.title)
    $rationale = ConvertTo-RedactedSiText -Text ([string]$candidate.rationale)
    $sourceLabel = ConvertTo-SafeMetadata -Value ([string]$run.provenance.repoId)
    $candidateText = @(
        "<<<UNTRUSTED_INPUT_START id=$candidateId source=`"$sourceLabel`">>>"
        '````'
        "Title: $title"
        "Rationale: $rationale"
        '````'
        "<<<UNTRUSTED_INPUT_END id=$candidateId>>>"
    ) -join "`n"
    if ([System.Text.Encoding]::UTF8.GetByteCount($candidateText) -gt 17KB) {
        throw "capacity-blocked: candidate '$candidateId' exceeds the export text ceiling after fencing."
    }
    $choice = if ($choiceById.ContainsKey($candidateId)) { $choiceById[$candidateId] } else { $null }
    $disposition = if ($null -eq $choice) { 'pending' } else { [string]$choice.disposition }
    if ($disposition -notin @('pending', 'accepted', 'declined', 'deferred')) {
        throw "SI run candidate '$candidateId' has invalid disposition '$disposition'."
    }
    $candidates.Add([ordered]@{
            candidateId = $candidateId
            rank = [int]$candidate.rank
            candidateText = $candidateText
            sources = [string[]]@($candidate.sources | ForEach-Object { ConvertTo-SafeMetadata -Value ([string]$_) })
            targets = [string[]]@($candidate.targets | ForEach-Object { ConvertTo-SafeMetadata -Value ([string]$_) })
            disposition = $disposition
            proposalPr = if ($null -eq $choice) { $null } else { $choice.proposalPr }
        })
}

$payload = [ordered]@{
    trust = 'untrusted-context-only'
    source = [ordered]@{
        repoId = ConvertTo-SafeMetadata -Value ([string]$run.provenance.repoId)
        planId = [string]$run.provenance.planId
        sourceCommit = [string]$run.provenance.sourceCommit
        installedPluginVersion = $InstalledPluginVersion
    }
    provenance = [ordered]@{
        runId = [string]$run.runId
        dueId = [string]$run.dueId
        pinnedBaseOid = [string]$run.provenance.pinnedBaseOid
        resolverReceiptId = $run.provenance.resolverReceiptId
    }
    candidates = $candidates.ToArray()
}
$canonicalPayload = ConvertTo-SiJcsJson -Value $payload
$exportId = Get-CrossRepoExportId -CanonicalPayload $canonicalPayload
$artifact = [ordered]@{ schema = $protocol; exportId = $exportId; payload = $payload }
$content = (ConvertTo-SiJcsJson -Value $artifact) + "`n"
if ([System.Text.Encoding]::UTF8.GetByteCount($content) -gt $maxArtifactBytes) {
    throw "capacity-blocked: cross-repository SI export exceeds the $maxArtifactBytes-byte artifact ceiling."
}
$artifactSchema = Join-Path (Split-Path -Parent $PSScriptRoot) 'schemas/cross-repo-export.schema.json'
if (-not ($content | Test-Json -SchemaFile $artifactSchema -ErrorAction SilentlyContinue)) {
    throw 'Generated cross-repository SI export failed its closed schema validation.'
}

$written = $true
$expectedGeneration = Get-AtomicStoreGeneration -Path $outputFull
if ($expectedGeneration -ne 'absent') {
    $current = [System.IO.File]::ReadAllText($outputFull)
    if ([string]::Equals($current, $content, [System.StringComparison]::Ordinal)) {
        $written = $false
    }
}
if ($written) {
    $result = Set-AtomicStoreContent -Path $outputFull -Content $content -ExpectedGeneration $expectedGeneration
    if ($result.Status -ne 'complete') {
        throw "Cross-repository SI export write failed with status '$($result.Status)'."
    }
}

[pscustomobject]@{
    Status = 'complete'
    ExportId = $exportId
    Path = $outputFull
    Written = $written
    Candidates = $candidates.Count
}
