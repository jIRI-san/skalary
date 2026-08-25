#requires -Version 7.0
<#
.SYNOPSIS
Scaffolds architecture-notes assets into a target repository, never overwriting existing files.

.DESCRIPTION
On init the architecture-notes skill copies its shipped schema assets (and, in later
steps, templates) into the consuming repo's own tree — e.g. schemas/architecture/architecture-contract.schema.json.
Installers cannot write outside .github/, so this runtime helper performs the copy.

The copy is strictly no-overwrite: an existing target file is left untouched and reported as
'skipped'. The contract schema is versioned: the one known unversioned v1 scaffold is upgraded,
while an unversioned customized or unknown-version schema is refused rather than overwritten.
Each shipped asset is emitted with the action taken (`created`, `upgraded`, or `skipped`).
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
    [pscustomobject]@{ SourceDir = 'schemas'; DestDir = 'schemas/architecture' }
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
        if ([System.IO.Path]::GetFileName($DestPath) -ne 'architecture-contract.schema.json') {
            return [pscustomobject]@{ Path = $DestPath; Action = 'skipped' }
        }

        $sourceSchema = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -Depth 100
        $currentVersion = $sourceSchema.'x-skalary-schema-version'
        $parsedVersion = 0
        if (-not [int]::TryParse([string]$currentVersion, [ref]$parsedVersion) -or $parsedVersion -lt 1) {
            throw "Shipped architecture schema has no valid x-skalary-schema-version: $SourcePath"
        }
        $currentVersion = $parsedVersion

        $targetRaw = [System.IO.File]::ReadAllText($DestPath)
        try {
            $targetSchema = $targetRaw | ConvertFrom-Json -Depth 100
        }
        catch {
            throw "Existing architecture schema is invalid JSON and cannot be upgraded safely: $DestPath"
        }
        $targetVersion = if ($targetSchema.PSObject.Properties.Name -contains 'x-skalary-schema-version') {
            $targetSchema.'x-skalary-schema-version'
        }
        else {
            $null
        }
        if ($targetVersion -eq $currentVersion) {
            return [pscustomobject]@{ Path = $DestPath; Action = 'skipped' }
        }

        $legacyV1Sha256 = '2ee7b24548076cdcb077ef4ef29cd218c4641a91cbe6e41bd587a2ed3ad9067d'
        $targetSha256 = (Get-FileHash -LiteralPath $DestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($null -ne $targetVersion -or
            -not [string]::Equals($targetSha256, $legacyV1Sha256, [System.StringComparison]::Ordinal)) {
            throw "Existing architecture schema version is unknown or customized; refusing unsafe overwrite: $DestPath"
        }

        $action = 'whatif'
        if ($Cmdlet.ShouldProcess($DestPath, "Upgrade architecture schema to version $currentVersion")) {
            Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
            $action = 'upgraded'
        }
        return [pscustomobject]@{ Path = $DestPath; Action = $action }
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
