#requires -Version 7.0
<#
.SYNOPSIS
Brownfield harvest: scans an existing repository and emits an initial architecture-notes set
(draft contracts + terse arch notes + a manifest) into a QUARANTINE staging area that the
`.architecture-notes.md` auto-load index never references.

.DESCRIPTION
The harvest operation of the architecture-notes skill. It performs a deterministic, read-only
scan of the target repo to discover candidate architectural boundaries (…detected .NET projects,
JS/TS packages, or top-level source directories…) and materializes, for each, a **draft** contract
plus a terse arch note.

Two hard invariants make harvest safe to run autonomously on an untrusted/unfamiliar codebase:

  1. **Draft-only.** Every emitted contract has `maturity: draft`. The script never writes a
     `locked` contract — locking is a human-commit-bound action performed later, one contract at a
     time, after review.
  2. **Quarantined.** All output lands under a staging directory (default
     `docs/architecture-notes/.staging/`) that is NOT the auto-loaded tier and is NOT referenced by
     `docs/architecture-notes/.architecture-notes.md`. A `HARVEST.md` manifest carries
     `reviewed: false`. Nothing enters the auto-loaded tier until a human reviews and promotes it.

The scan is heuristic and content is derived from untrusted repo text, so harvested prose is
treated as data: it is written into quarantine only and never auto-loaded into agent context.

The copy is strictly no-overwrite: existing staging files are left untouched and reported as
'skipped'. Each written file is emitted with its path and the action taken ('created', 'skipped',
or 'whatif') so callers and evals can assert the outcome.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Repository root to scan.
    [Parameter(Mandatory)][string]$RepoRoot,

    # Quarantine staging directory. Defaults to <RepoRoot>/docs/architecture-notes/.staging.
    [string]$StagingRoot,

    # Root of the shipped assets (…/architecture-notes/assets). Auto-detected when omitted.
    [string]$AssetRoot,

    # Upper bound on harvested boundaries. Keeps the initial set reviewable.
    [int]$MaxBoundaries = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    throw "RepoRoot not found or not a directory: $RepoRoot"
}
# Resolve to an absolute path so .NET (CWD-based) and PowerShell provider ($PWD-based) path
# resolution can never diverge for a relative -RepoRoot.
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if (-not $StagingRoot) {
    $StagingRoot = Join-Path $RepoRoot 'docs/architecture-notes/.staging'
}

$validateContract = Join-Path $PSScriptRoot 'Test-ArchContract.ps1'
if (-not (Test-Path -LiteralPath $validateContract -PathType Leaf)) {
    throw "Required sibling script missing: $validateContract"
}

if (-not $AssetRoot) {
    # Dual-layout probe, matching the sibling scripts. Require the templates/ subtree so a
    # stray same-named directory cannot win.
    $candidates = @(
        (Join-Path $PSScriptRoot '..' 'skills' 'architecture-notes' 'assets'),
        (Join-Path $PSScriptRoot '..' 'assets')
    )
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'templates') -PathType Container)) {
            $AssetRoot = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
    if (-not $AssetRoot) {
        throw "Could not locate architecture-notes assets relative to $PSScriptRoot; pass -AssetRoot explicitly."
    }
}
if (-not (Test-Path -LiteralPath $AssetRoot -PathType Container)) {
    throw "AssetRoot not found or not a directory: $AssetRoot"
}

$noteTemplate = Join-Path $AssetRoot 'templates/architecture-note.template.md'
$schemaPath = Join-Path $AssetRoot 'schemas/architecture-contract.schema.json'
foreach ($f in @($noteTemplate, $schemaPath)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Required asset missing: $f" }
}
$noteTemplateText = Get-Content -LiteralPath $noteTemplate -Raw
$noteEol = if ($noteTemplateText -match "`r`n") { "`r`n" } else { "`n" }

# Directories that never represent an authored architectural boundary.
$pruneDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($d in @('.git', 'node_modules', 'bin', 'obj', '.vs', '.vscode', 'dist', 'out',
        'packages', '.staging', 'TestResults', 'coverage', '.idea')) {
    [void]$pruneDirs.Add($d)
}

function Test-PrunedPath {
    param([string]$FullPath)
    $rel = $FullPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    foreach ($seg in ($rel -split '[\\/]+')) {
        if ($pruneDirs.Contains($seg)) { return $true }
    }
    return $false
}

function Get-RelDir {
    param([string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    $rel = $dir.Substring($RepoRoot.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($rel)) { return '.' }
    return ($rel -replace '\\', '/')
}

# Ids that would collide with a Windows reserved device name are disallowed as file basenames.
$script:reservedIdBasenames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')) {
    [void]$script:reservedIdBasenames.Add($n)
}

function ConvertTo-BoundaryId {
    param([string]$Name)
    # Reduce to the id charset; collapse runs; trim leading/trailing separators.
    $id = $Name -replace '[^A-Za-z0-9._-]', '-'
    $id = $id -replace '-{2,}', '-'
    $id = $id.Trim('-', '.', '_')
    if ([string]::IsNullOrWhiteSpace($id)) { $id = 'Boundary' }
    if ($id -notmatch '^[A-Za-z0-9]') { $id = 'B-' + $id }
    # Prefix reserved Windows device names so the derived <id>.json / <id>.md paths are writable.
    if ($script:reservedIdBasenames.Contains($id)) { $id = 'B-' + $id }
    return $id
}

function ConvertTo-MarkdownCell {
    param([string]$Text)
    # Harvested text is untrusted; keep it from breaking or injecting into markdown tables/prose.
    if ($null -eq $Text) { return '' }
    return ($Text -replace '[\r\n]+', ' ' -replace '\|', '\|').Trim()
}

# --- Scan for candidate boundaries -------------------------------------------------------------
$candidatesFound = [System.Collections.Generic.List[object]]::new()

# .NET projects (C#, F#, VB).
$dotnetProjects = foreach ($ext in @('*.csproj', '*.fsproj', '*.vbproj')) {
    Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter $ext -ErrorAction SilentlyContinue
}
foreach ($proj in ($dotnetProjects |
        Where-Object { -not (Test-PrunedPath $_.FullName) } | Sort-Object FullName)) {
    $relDir = Get-RelDir $proj.FullName
    $scope = if ($relDir -eq '.') { '**' } else { "$relDir/**" }
    $candidatesFound.Add([pscustomobject]@{
            Name      = [System.IO.Path]::GetFileNameWithoutExtension($proj.Name)
            Framework = 'dotnet'
            Kind      = '.NET project'
            Scope     = $scope
            Source    = ($proj.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/')
        })
}

# JS/TS packages (any package.json outside pruned dirs).
foreach ($pkg in (Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter 'package.json' -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PrunedPath $_.FullName) } | Sort-Object FullName)) {
    $relDir = Get-RelDir $pkg.FullName
    $scope = if ($relDir -eq '.') { '**' } else { "$relDir/**" }
    $pkgName = $null
    try {
        $pkgJson = Get-Content -LiteralPath $pkg.FullName -Raw | ConvertFrom-Json
        if ($pkgJson.PSObject.Properties.Name -contains 'name' -and $pkgJson.name) {
            $pkgName = [string]$pkgJson.name
        }
    }
    catch { $pkgName = $null }
    if (-not $pkgName) { $pkgName = if ($relDir -eq '.') { Split-Path -Leaf $RepoRoot } else { Split-Path -Leaf $relDir } }
    $hasTs = Test-Path -LiteralPath (Join-Path (Split-Path -Parent $pkg.FullName) 'tsconfig.json') -PathType Leaf
    $candidatesFound.Add([pscustomobject]@{
            Name      = $pkgName
            Framework = if ($hasTs) { 'typescript' } else { 'javascript' }
            Kind      = if ($hasTs) { 'TypeScript package' } else { 'JavaScript package' }
            Scope     = $scope
            Source    = ($pkg.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/')
        })
}

# Fallback: top-level source directories when no project/package manifests were found.
if ($candidatesFound.Count -eq 0) {
    foreach ($top in @('src', 'lib', 'app', 'apps', 'services', 'source')) {
        $topPath = Join-Path $RepoRoot $top
        if (Test-Path -LiteralPath $topPath -PathType Container) {
            $candidatesFound.Add([pscustomobject]@{
                    Name      = $top
                    Framework = 'unknown'
                    Kind      = 'source directory'
                    Scope     = "$top/**"
                    Source    = "$top/"
                })
        }
    }
}

# Deterministic order + cap; assign unique ids (case-insensitive).
$ordered = @($candidatesFound | Sort-Object Name, Source)
$selected = @($ordered | Select-Object -First $MaxBoundaries)
$truncated = $ordered.Count -gt $selected.Count

$usedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($c in $selected) {
    $baseId = ConvertTo-BoundaryId $c.Name
    $id = $baseId
    $n = 2
    while (-not $usedIds.Add($id)) { $id = "$baseId-$n"; $n++ }
    Add-Member -InputObject $c -NotePropertyName 'Id' -NotePropertyValue $id -Force
}

# --- Write quarantine --------------------------------------------------------------------------
$stagingSchemas = Join-Path $StagingRoot 'schemas'
$stagingNotes = Join-Path $StagingRoot 'notes'

function Write-HarvestFile {
    param(
        [Parameter(Mandatory)][string]$DestPath,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)]$Cmdlet
    )
    if (Test-Path -LiteralPath $DestPath -PathType Leaf) { return 'skipped' }
    $action = 'whatif'
    if ($Cmdlet.ShouldProcess($DestPath, 'Write harvest file')) {
        $destDir = Split-Path -Parent $DestPath
        if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
            [void][System.IO.Directory]::CreateDirectory($destDir)
        }
        Set-Content -LiteralPath $DestPath -Value $Content -NoNewline
        $action = 'created'
    }
    return $action
}

$contracts = [System.Collections.Generic.List[object]]::new()
$notes = [System.Collections.Generic.List[object]]::new()

foreach ($c in $selected) {
    $safeName = ConvertTo-MarkdownCell $c.Name
    $safeSource = ConvertTo-MarkdownCell $c.Source
    $prose = "Harvested candidate boundary for '$safeName' ($($c.Kind), detected at $safeSource). " +
    'Draft only: review, refine the interface contract, then promote. Content derived from repo scan; verify before locking.'

    # Draft contract (never locked). maturity is hard-coded to guarantee the draft-only invariant.
    # `frameworks` (the deterministic adapter) is a human review decision, so harvest leaves it
    # unset; the detected stack is captured in prose and the manifest instead.
    $contract = [ordered]@{
        id       = $c.Id
        title    = $safeName
        maturity = 'draft'
        prose    = $prose
    }

    $contractPath = Join-Path $stagingSchemas ($c.Id + '.json')
    $json = ($contract | ConvertTo-Json -Depth 10)
    $action = Write-HarvestFile -DestPath $contractPath -Content $json -Cmdlet $PSCmdlet

    $valid = $null
    if (Test-Path -LiteralPath $contractPath -PathType Leaf) {
        $res = & $validateContract -ContractPath $contractPath -SchemaPath $schemaPath
        $valid = [bool]$res.Valid
    }
    $contracts.Add([pscustomobject]@{
            Path     = $contractPath
            Id       = $c.Id
            Maturity = 'draft'
            Action   = $action
            Valid    = $valid
        })

    $noteText = $noteTemplateText.
    Replace('<SUBSYSTEM>', $safeName).
    Replace('<CONTRACT_ID>', $c.Id)
    # Neutralize the path-scoped auto-attach front-matter so a quarantined note can never be
    # glob-matched into agent context before human review (RISK-5). The detected scope is kept
    # under a non-triggering key for the reviewer; promotion into the tier restores real globs.
    $noteText = [regex]::Replace(
        $noteText,
        'globs:\s*\r?\n\s*-\s*"<SCOPE_GLOB>"',
        { param($m) "quarantined: true$noteEol" + 'stagedScope: "' + $c.Scope + '"' })
    $noteSlug = ($c.Id.ToLowerInvariant() -replace '[^a-z0-9._-]', '-')
    $notePath = Join-Path $stagingNotes ($noteSlug + '.md')
    $noteAction = Write-HarvestFile -DestPath $notePath -Content $noteText -Cmdlet $PSCmdlet
    $notes.Add([pscustomobject]@{ Path = $notePath; Action = $noteAction })
}

# Manifest with reviewed:false — the promotion gate. Excluded from auto-load (lives under .staging).
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$rows = if ($selected.Count -gt 0) {
    ($selected | ForEach-Object { "| $($_.Id) | $(ConvertTo-MarkdownCell $_.Name) | $($_.Framework) | draft | $(ConvertTo-MarkdownCell $_.Source) |" }) -join "`n"
}
else {
    '| _none detected_ | | | | |'
}
$manifest = @"
---
reviewed: false
harvestedAt: $stamp
boundaries: $($selected.Count)
truncated: $truncated
---

# Architecture Harvest (QUARANTINED — reviewed: false)

This directory is a **staging quarantine**. It is **not** part of the auto-loaded architecture
tier and is **not** referenced by ``.architecture-notes.md``. Nothing here reaches agent context
until a human reviews it and promotes selected contracts/notes into the auto-loaded tier
(``schemas/`` + ``docs/architecture-notes/``).

Every harvested contract is ``draft`` (warn-only). No contract is ``locked``. Locking is a
separate, human-commit-bound action performed one contract at a time after review.

## Candidate boundaries

| Contract Id | Title | Framework | Maturity | Detected at |
|---|---|---|---|---|
$rows

## Review & promote

1. Read each draft contract under ``schemas/`` and its note under ``notes/``; correct the
   interface, scope, and rules. Harvested prose is a **starting point derived from an automated
   scan** — verify it.
2. Move the reviewed contract into the repo ``schemas/`` directory and its note into
   ``docs/architecture-notes/``; add rows to ``.architecture-notes.md``.
3. Only then, and only via a human-authored commit, promote a contract to ``locked``.
4. Flip ``reviewed: true`` here (or delete this staging directory) once promotion is complete.
"@
$manifestPath = Join-Path $StagingRoot 'HARVEST.md'
$manifestAction = Write-HarvestFile -DestPath $manifestPath -Content $manifest -Cmdlet $PSCmdlet

[pscustomobject]@{
    RepoRoot    = $RepoRoot
    StagingRoot = $StagingRoot
    Reviewed    = $false
    Truncated   = $truncated
    Contracts   = @($contracts)
    Notes       = @($notes)
    Manifest    = [pscustomobject]@{ Path = $manifestPath; Action = $manifestAction }
}
