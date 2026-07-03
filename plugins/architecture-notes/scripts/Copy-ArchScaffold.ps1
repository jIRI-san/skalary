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
# reconstruction. Grows as later steps add templates.
$scaffoldMap = @(
    [pscustomobject]@{ SourceDir = 'schemas'; DestDir = 'schemas' }
)

$results = [System.Collections.Generic.List[object]]::new()

foreach ($mapping in $scaffoldMap) {
    $sourceDir = Join-Path $AssetRoot $mapping.SourceDir
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { continue }

    $destDir = Join-Path $TargetRoot $mapping.DestDir

    foreach ($sourceFile in (Get-ChildItem -LiteralPath $sourceDir -File | Sort-Object Name)) {
        $destPath = Join-Path $destDir $sourceFile.Name

        if (Test-Path -LiteralPath $destPath -PathType Leaf) {
            $results.Add([pscustomobject]@{ Path = $destPath; Action = 'skipped' })
            continue
        }

        $action = 'whatif'
        if ($PSCmdlet.ShouldProcess($destPath, "Scaffold from '$($sourceFile.FullName)'")) {
            if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $destDir -Force)
            }
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
            $action = 'created'
        }
        $results.Add([pscustomobject]@{ Path = $destPath; Action = $action })
    }
}

return , @($results)
