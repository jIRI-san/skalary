#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$UpstreamRoot,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ExpectedUpstreamRepository,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$ExpectedUpstreamHost,
    [Parameter(Mandatory)][ValidateSet('Small', 'PlanSized')][string]$WorkSize
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$maxArtifactBytes = 64KB
$maxInstructionBytes = 256KB
$protocol = 'cross-repo-si-export/v1'

$module = Join-Path $PSScriptRoot 'SiResolverReceipt.psm1'
Import-Module $module -Force

function Get-CrossRepoExportId {
    param([Parameter(Mandatory)][string]$CanonicalPayload)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($protocol + $CanonicalPayload)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function ConvertTo-RedactedSiText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $value = [regex]::Replace(
        $Text,
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
    return [regex]::Replace($value, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
}

$artifactFull = [System.IO.Path]::GetFullPath($ArtifactPath)
$upstreamFull = [System.IO.Path]::GetFullPath($UpstreamRoot)
if (-not (Test-Path -LiteralPath $artifactFull -PathType Leaf)) {
    throw "Cross-repository SI artifact '$artifactFull' was not found."
}
if ((Get-Item -LiteralPath $artifactFull).Length -gt $maxArtifactBytes) {
    throw "capacity-blocked: cross-repository SI artifact exceeds $maxArtifactBytes bytes."
}
if (-not (Test-Path -LiteralPath (Join-Path $upstreamFull '.git'))) {
    $gitMarker = & git -C $upstreamFull rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($gitMarker -join ''))) {
        throw "Upstream root '$upstreamFull' is not a Git checkout."
    }
}
$topLevel = (& git -C $upstreamFull rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or
    -not [string]::Equals(
        [System.IO.Path]::GetFullPath($topLevel).TrimEnd('\', '/'),
        $upstreamFull.TrimEnd('\', '/'),
        $(if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal })
    )) {
    throw 'The upstream checkout must be the workspace root.'
}
$dirty = @(& git -C $upstreamFull status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
    throw 'The upstream checkout must be clean before importing consumer context.'
}
$remote = (@(& git -C $upstreamFull config --get remote.origin.url) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
    throw 'The upstream checkout must have an origin remote.'
}
$remoteRepository = $null
$remoteHost = $null
if ($remote -match '^(?:https?://|ssh://git@)(?<host>[^/]+)/(?<repo>[^/]+/[^/]+?)(?:\.git)?$') {
    $remoteHost = $Matches.host
    $remoteRepository = $Matches.repo
}
elseif ($remote -match '^(?:[^@]+@)?(?<host>[^:]+):(?<repo>[^/]+/[^/]+?)(?:\.git)?$') {
    $remoteHost = $Matches.host
    $remoteRepository = $Matches.repo
}
if (-not [string]::Equals(
        $remoteHost,
        $ExpectedUpstreamHost,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -or -not [string]::Equals(
        $remoteRepository,
        $ExpectedUpstreamRepository,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "The checkout origin does not match expected upstream '$ExpectedUpstreamRepository'."
}

$instructionRelativePaths = @(
    '.github/copilot-instructions.md',
    'docs/design-notes/.design-notes.md',
    'docs/architecture-notes/.architecture-notes.md'
)
$instructionDigests = [System.Collections.Generic.List[object]]::new()
$instructionBytes = 0L
foreach ($relative in $instructionRelativePaths) {
    $path = Join-Path $upstreamFull $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Upstream instruction file '$relative' must not be a link or reparse point."
    }
    $length = $item.Length
    if (($instructionBytes + $length) -gt $maxInstructionBytes) {
        throw "capacity-blocked: upstream instruction files exceed $maxInstructionBytes bytes."
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $instructionBytes += $bytes.Length
    $instructionDigests.Add([pscustomobject]@{
            path = $relative
            sha256 = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()
        })
}
if ($instructionDigests.Count -eq 0) {
    throw 'The upstream checkout has no recognized repository instruction file.'
}

$artifactText = [System.IO.File]::ReadAllText($artifactFull)
$artifactSchema = Join-Path (Split-Path -Parent $PSScriptRoot) 'schemas/cross-repo-export.schema.json'
if (-not ($artifactText | Test-Json -SchemaFile $artifactSchema -ErrorAction SilentlyContinue)) {
    throw 'Cross-repository SI artifact failed its closed schema validation.'
}
try { $artifact = $artifactText | ConvertFrom-Json -Depth 100 }
catch { throw "Cross-repository SI artifact is malformed JSON: $($_.Exception.Message)" }
if ($artifact.schema -ne $protocol -or $artifact.payload.trust -ne 'untrusted-context-only' -or
    [string]$artifact.exportId -notmatch '^[0-9a-f]{64}$') {
    throw 'Cross-repository SI artifact failed its closed envelope validation.'
}
$actualId = Get-CrossRepoExportId `
    -CanonicalPayload (ConvertTo-SiJcsJson -Value $artifact.payload)
if (-not [string]::Equals($actualId, [string]$artifact.exportId, [System.StringComparison]::Ordinal)) {
    throw 'Cross-repository SI artifact failed its content-addressed replay check.'
}
if (@($artifact.payload.candidates).Count -gt 5) {
    throw 'Cross-repository SI artifact exceeds the candidate bound.'
}

$fenceId = [Guid]::NewGuid().ToString('N')
$safeArtifact = ConvertTo-RedactedSiText -Text ($artifactText.TrimEnd())
$context = @(
    "<<<UNTRUSTED_INPUT_START id=$fenceId source=`"cross-repo-si:$($artifact.exportId)`">>>"
    '````json'
    $safeArtifact
    '````'
    "<<<UNTRUSTED_INPUT_END id=$fenceId>>>"
) -join "`n"

[pscustomobject]@{
    Status = 'complete'
    Action = $(if ($WorkSize -eq 'Small') { '/si' } else { '/cip' })
    ExportId = [string]$artifact.exportId
    UpstreamRoot = $upstreamFull
    PinnedHead = (& git -C $upstreamFull rev-parse HEAD).Trim()
    Instructions = $instructionDigests.ToArray()
    Context = $context
    ScopeGuard = '.github/skills/si/scripts/Test-SiWriteScope.ps1'
    DraftOnly = $true
    AutoMerge = $false
}
