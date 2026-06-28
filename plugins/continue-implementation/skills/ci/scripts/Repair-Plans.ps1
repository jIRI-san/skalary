#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'

$migrated = [System.Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $plansRoot -PathType Container)) {
    return [pscustomobject]@{ PlansRoot = $plansRoot; Migrated = @(); Count = 0 }
}

# Loose plan files live directly under the plans root (archived/ is a subdirectory and is a non-goal).
$looseFiles = Get-ChildItem -LiteralPath $plansRoot -File -Filter '*.md' -ErrorAction SilentlyContinue

foreach ($file in $looseFiles) {
    $base = $file.BaseName
    $isLegacy = $base -match '^\d{3}-.+'
    $isNew = $base -match '^\d{4}-\d{2}-\d{2}-[0-9a-f]{6}-.+'
    if (-not ($isLegacy -or $isNew)) {
        continue
    }

    $targetDir = Join-Path $plansRoot $base
    $targetPlan = Join-Path $targetDir 'plan.md'

    if (Test-Path -LiteralPath $targetPlan -PathType Leaf) {
        Write-Warning "Skipping '$($file.Name)': '$base/plan.md' already exists."
        continue
    }

    if ($PSCmdlet.ShouldProcess($file.FullName, "Migrate to $base/plan.md")) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Move-Item -LiteralPath $file.FullName -Destination $targetPlan
    }

    $migrated.Add([pscustomobject]@{
        From     = $file.Name
        ToFolder = $base
        To       = $targetPlan
    })
}

return [pscustomobject]@{
    PlansRoot = $plansRoot
    Migrated  = $migrated.ToArray()
    Count     = $migrated.Count
}
