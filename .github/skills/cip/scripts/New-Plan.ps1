#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [string]$Slug,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),

    [string]$PlanId,

    [string]$TemplatePath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

function Get-SanitizedSlug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $clean = $Value.ToLowerInvariant()
    $clean = $clean -replace '[^a-z0-9]+', '-'
    $clean = $clean.Trim('-')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "Slug '$Value' is empty after sanitization; supply alphanumeric characters."
    }

    return $clean
}

function Resolve-ConfinedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$FolderName
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $FolderName))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $resolvedRoot.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved plan folder '$candidate' escapes plans root '$resolvedRoot'."
    }

    return $candidate
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'
if (-not (Test-Path -LiteralPath $plansRoot)) {
    New-Item -ItemType Directory -Path $plansRoot -Force | Out-Null
}

if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    throw "Date '$Date' must be in yyyy-MM-dd format."
}

$slugClean = Get-SanitizedSlug -Value $Slug

if ($PlanId) {
    $PlanId = $PlanId.Trim().ToLowerInvariant()
    if ($PlanId -notmatch '^[0-9a-f]{6}$') {
        throw "PlanId '$PlanId' must be exactly 6 hex chars."
    }
}
else {
    $PlanId = New-PlanId -RepoRoot $repoRootPath
}

$folderName = "$Date-$PlanId-$slugClean"
$targetDir = Resolve-ConfinedFolder -Root $plansRoot -FolderName $folderName
$planFile = Join-Path $targetDir 'plan.md'

if ((Test-Path -LiteralPath $targetDir) -and -not $Force) {
    throw "Plan folder already exists: $targetDir (use -Force to overwrite plan.md)."
}

if (-not $TemplatePath) {
    $TemplatePath = Join-Path $repoRootPath 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
}
if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
    throw "Plan template not found: $TemplatePath"
}

$templateRaw = Get-Content -LiteralPath $TemplatePath -Raw
$normalized = $templateRaw -replace "`r`n", "`n"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]]($normalized.Split("`n")))

$titleReplaced = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if (-not $titleReplaced -and $lines[$i] -match '^#\s+') {
        $lines[$i] = "# ${PlanId}: $Title"
        if (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s*<!--\s*plan-id:') {
            $lines[$i + 1] = "<!-- plan-id: $PlanId -->"
        }
        else {
            $lines.Insert($i + 1, "<!-- plan-id: $PlanId -->")
        }
        $titleReplaced = $true
        break
    }
}

if (-not $titleReplaced) {
    $lines.Insert(0, "<!-- plan-id: $PlanId -->")
    $lines.Insert(0, "# ${PlanId}: $Title")
}

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
$content = ($lines -join "`n")
Set-Content -LiteralPath $planFile -Value $content -Encoding utf8NoBOM

$result = [pscustomobject]@{
    PlanId = $PlanId
    Slug = $slugClean
    Date = $Date
    FolderName = $folderName
    Path = $targetDir
    PlanFile = $planFile
}

Write-Host "Created plan '$folderName' (plan-id $PlanId) at $planFile" -ForegroundColor Green
return $result
