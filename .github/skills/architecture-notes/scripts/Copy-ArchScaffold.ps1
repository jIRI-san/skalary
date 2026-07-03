#requires -Version 7.0
<#
.SYNOPSIS
Scaffolds architecture-notes assets into a target repository, never overwriting existing files.

.DESCRIPTION
On init the architecture-notes skill copies its shipped schema assets (and, in later
steps, templates) into the consuming repo's own tree — e.g. schemas/architecture-contract.schema.json.
Installers cannot write outside .github/, so this runtime helper performs the copy.

The copy is strictly no-overwrite: an existing target file is left untouched and reported as
'skipped'. Each shipped asset is emitted as an object with its resolved target path and the
action taken ('created' or 'skipped') so callers (and evals) can assert the outcome.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Repository root the assets are scaffolded into.
    [Parameter(Mandatory)][string]$TargetRoot,

    # Root of the shipped assets (…/architecture-notes/assets). Auto-detected from the
    # script location across both the authored and installed layouts when omitted.
    [string]$AssetRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
    throw "TargetRoot not found or not a directory: $TargetRoot"
}

if (-not $AssetRoot) {
    $candidates = @(
        # Authored layout: plugins/architecture-notes/scripts -> skills/architecture-notes/assets
        (Join-Path $PSScriptRoot '..' 'skills' 'architecture-notes' 'assets'),
        # Installed layout: .github/skills/architecture-notes/scripts -> ../assets
        (Join-Path $PSScriptRoot '..' 'assets')
    )
    foreach ($candidate in $candidates) {
        # Require the expected asset subtree (schemas/) to be present so a stray
        # same-named directory in either layout can never win.
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'schemas') -PathType Container)) {
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

# Asset subtrees scaffolded into the target repo. Source dir is under $AssetRoot; dest dir
# is under $TargetRoot. Each subtree is copied non-recursively (flat), which matches the
# current flat asset layout; nested subtrees would need -Recurse with dest-path
# reconstruction.
$scaffoldMap = @(
    [pscustomobject]@{ SourceDir = 'schemas'; DestDir = 'schemas' }
)

# Individual asset files scaffolded to a renamed destination (e.g. the tier index template
# lands as the dot-file docs/architecture-notes/.architecture-notes.md).
$fileMap = @(
    [pscustomobject]@{
        Source = 'templates/architecture-notes-index.template.md'
        Dest   = 'docs/architecture-notes/.architecture-notes.md'
    }
)

$results = [System.Collections.Generic.List[object]]::new()

function Copy-ScaffoldFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestPath,
        [Parameter(Mandatory)]$Cmdlet
    )

    if (Test-Path -LiteralPath $DestPath -PathType Leaf) {
        return [pscustomobject]@{ Path = $DestPath; Action = 'skipped' }
    }

    $action = 'whatif'
    if ($Cmdlet.ShouldProcess($DestPath, "Scaffold from '$SourcePath'")) {
        $destDir = Split-Path -Parent $DestPath
        if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
            [void][System.IO.Directory]::CreateDirectory($destDir)
        }
        Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
        $action = 'created'
    }
    return [pscustomobject]@{ Path = $DestPath; Action = $action }
}

foreach ($mapping in $scaffoldMap) {
    $sourceDir = Join-Path $AssetRoot $mapping.SourceDir
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { continue }

    $destDir = Join-Path $TargetRoot $mapping.DestDir

    foreach ($sourceFile in (Get-ChildItem -LiteralPath $sourceDir -File | Sort-Object Name)) {
        $destPath = Join-Path $destDir $sourceFile.Name
        $results.Add((Copy-ScaffoldFile -SourcePath $sourceFile.FullName -DestPath $destPath -Cmdlet $PSCmdlet))
    }
}

foreach ($file in $fileMap) {
    $sourcePath = Join-Path $AssetRoot $file.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
    $destPath = Join-Path $TargetRoot $file.Dest
    $results.Add((Copy-ScaffoldFile -SourcePath $sourcePath -DestPath $destPath -Cmdlet $PSCmdlet))
}

return , @($results)
