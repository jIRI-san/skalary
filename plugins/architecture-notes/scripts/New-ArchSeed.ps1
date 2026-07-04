#requires -Version 7.0
<#
.SYNOPSIS
Materializes a greenfield architecture seed: 1-2 draft contracts + arch notes + a human-doc
skeleton, scaffolding the tier without overwriting existing files.

.DESCRIPTION
The seed operation of the architecture-notes skill. An agent runs the interview (see
assets/interview-guide.md), records the answers into a seed-spec JSON, and hands it here. This
script is the script-mediated, deterministic materialization step:

  1. Scaffolds the tier (schema + index) via Copy-ArchScaffold.ps1 (no-overwrite).
  2. Writes each boundary as a **draft** contract JSON under schemas/ (no-overwrite) and validates
     it with Test-ArchContract.ps1.
  3. Writes a terse arch note per boundary from the note template.
  4. Writes the human-doc skeleton from the human-doc template (no-overwrite).

It never writes a `locked` contract. The seed-spec must declare 1..MaxBoundaries boundaries
(default 2) — "no big design upfront". Each shipped/written file is reported with the action
taken ('created', 'skipped', or 'whatif') so callers and evals can assert the outcome.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Repository root the seed is materialized into.
    [Parameter(Mandatory)][string]$TargetRoot,

    # Path to the seed-spec JSON produced from the interview (see assets/interview-guide.md).
    [Parameter(Mandatory)][string]$SeedSpecPath,

    # Root of the shipped assets (…/architecture-notes/assets). Auto-detected when omitted.
    [string]$AssetRoot,

    # Upper bound on seeded boundaries. Keeps the seed light.
    [int]$MaxBoundaries = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
    throw "TargetRoot not found or not a directory: $TargetRoot"
}
# Resolve to an absolute path so .NET (CWD-based) and PowerShell provider ($PWD-based) path
# resolution can never diverge for a relative -TargetRoot.
$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path
if (-not (Test-Path -LiteralPath $SeedSpecPath -PathType Leaf)) {
    throw "Seed-spec file not found: $SeedSpecPath"
}

$copyScaffold = Join-Path $PSScriptRoot 'Copy-ArchScaffold.ps1'
$validateContract = Join-Path $PSScriptRoot 'Test-ArchContract.ps1'
foreach ($s in @($copyScaffold, $validateContract)) {
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) {
        throw "Required sibling script missing: $s"
    }
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
$humanDocTemplate = Join-Path $AssetRoot 'templates/architecture-human-doc.template.md'
foreach ($t in @($noteTemplate, $humanDocTemplate)) {
    if (-not (Test-Path -LiteralPath $t -PathType Leaf)) { throw "Required template missing: $t" }
}

$spec = Get-Content -LiteralPath $SeedSpecPath -Raw | ConvertFrom-Json
function Get-SpecProp {
    param($Object, [string]$Name, $Default = $null)
    if ($Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

$rawBoundaries = Get-SpecProp $spec 'boundaries'
if ($null -eq $rawBoundaries) {
    throw "Seed-spec must declare 1..$MaxBoundaries boundaries (no big design upfront); 'boundaries' is missing or null."
}
$boundaries = @($rawBoundaries)
if ($boundaries.Count -lt 1 -or $boundaries.Count -gt $MaxBoundaries) {
    throw "Seed-spec must declare 1..$MaxBoundaries boundaries (no big design upfront); got $($boundaries.Count)."
}
# Reject duplicate ids (case-insensitive — file paths collide on Windows/macOS) up front so no
# boundary's contract/note is silently skipped by the no-overwrite guard.
$seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($b in $boundaries) {
    $bid = [string](Get-SpecProp $b 'id')
    if ($bid -and -not $seenIds.Add($bid)) {
        throw "Seed-spec has a duplicate (case-insensitive) boundary id: '$bid'."
    }
}
$project = [string](Get-SpecProp $spec 'project' 'Project')
if ([string]::IsNullOrWhiteSpace($project)) { $project = 'Project' }

# Ids that would shadow a scaffolded artifact or a Windows reserved device name are disallowed.
$reservedIdBasenames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in @(
        'architecture-contract.schema', '.architecture-notes', 'architecture.human',
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')) {
    [void]$reservedIdBasenames.Add($n)
}

function Write-SeedFile {
    param(
        [Parameter(Mandatory)][string]$DestPath,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)]$Cmdlet
    )
    if (Test-Path -LiteralPath $DestPath -PathType Leaf) {
        return 'skipped'
    }
    $action = 'whatif'
    if ($Cmdlet.ShouldProcess($DestPath, 'Write seed file')) {
        $destDir = Split-Path -Parent $DestPath
        if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
            [void][System.IO.Directory]::CreateDirectory($destDir)
        }
        Set-Content -LiteralPath $DestPath -Value $Content -NoNewline
        $action = 'created'
    }
    return $action
}

# 1) Scaffold the tier (schema + index), no-overwrite.
$scaffoldResult = & $copyScaffold -TargetRoot $TargetRoot -AssetRoot $AssetRoot

$schemasDir = Join-Path $TargetRoot 'schemas'
$notesDir = Join-Path $TargetRoot 'docs/architecture-notes'
$targetSchema = Join-Path $schemasDir 'architecture-contract.schema.json'

$idPattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
$noteTemplateText = Get-Content -LiteralPath $noteTemplate -Raw

$contracts = [System.Collections.Generic.List[object]]::new()
$notes = [System.Collections.Generic.List[object]]::new()

foreach ($b in $boundaries) {
    $id = [string](Get-SpecProp $b 'id')
    $title = [string](Get-SpecProp $b 'title')
    $prose = [string](Get-SpecProp $b 'prose')
    $scope = [string](Get-SpecProp $b 'scope' '**')
    if ($id -notmatch $idPattern) { throw "Boundary id '$id' does not match $idPattern." }
    if ($reservedIdBasenames.Contains($id)) {
        throw "Boundary id '$id' is reserved (shadows a scaffolded artifact or a Windows device name); choose another id."
    }
    if ([string]::IsNullOrWhiteSpace($title)) { throw "Boundary '$id' is missing a title." }
    if ([string]::IsNullOrWhiteSpace($prose)) { throw "Boundary '$id' is missing prose." }

    # 2) Draft contract (never locked).
    $contract = [ordered]@{
        id       = $id
        title    = $title
        maturity = 'draft'
        prose    = $prose
    }
    $description = Get-SpecProp $b 'description'
    if ($description) { $contract['description'] = [string]$description }

    $contractPath = Join-Path $schemasDir ($id + '.json')
    $json = ($contract | ConvertTo-Json -Depth 10)
    $action = Write-SeedFile -DestPath $contractPath -Content $json -Cmdlet $PSCmdlet

    $valid = $null
    if (Test-Path -LiteralPath $contractPath -PathType Leaf) {
        $schemaArg = if (Test-Path -LiteralPath $targetSchema -PathType Leaf) { $targetSchema } else { $null }
        $res = if ($schemaArg) {
            & $validateContract -ContractPath $contractPath -SchemaPath $schemaArg
        }
        else {
            & $validateContract -ContractPath $contractPath
        }
        $valid = [bool]$res.Valid
    }
    $contracts.Add([pscustomobject]@{ Path = $contractPath; Id = $id; Maturity = 'draft'; Action = $action; Valid = $valid })

    # 3) Terse arch note.
    $noteText = $noteTemplateText.
        Replace('<SUBSYSTEM>', $title).
        Replace('<SCOPE_GLOB>', $scope).
        Replace('<CONTRACT_ID>', $id)
    $noteSlug = ($id.ToLowerInvariant() -replace '[^a-z0-9._-]', '-')
    $notePath = Join-Path $notesDir ($noteSlug + '.md')
    $noteAction = Write-SeedFile -DestPath $notePath -Content $noteText -Cmdlet $PSCmdlet
    $notes.Add([pscustomobject]@{ Path = $notePath; Action = $noteAction })
}

# 4) Human-doc skeleton (excluded from the index auto-load path).
$humanDocText = (Get-Content -LiteralPath $humanDocTemplate -Raw).Replace('<PROJECT_NAME>', $project)
$humanDocPath = Join-Path $notesDir 'architecture.human.md'
$humanDocAction = Write-SeedFile -DestPath $humanDocPath -Content $humanDocText -Cmdlet $PSCmdlet

[pscustomobject]@{
    Project   = $project
    Scaffold  = @($scaffoldResult)
    Contracts = @($contracts)
    Notes     = @($notes)
    HumanDoc  = [pscustomobject]@{ Path = $humanDocPath; Action = $humanDocAction }
}
