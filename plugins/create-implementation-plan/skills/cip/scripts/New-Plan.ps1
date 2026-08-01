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

function Get-PlanAssetScaffold {
    [CmdletBinding()]
    param()

    # Scaffolded asset files always carry an explicit placeholder and are never zero-length, so
    # "present-but-empty" (which Resolve-PlanSection fails loud on) stays distinguishable from "authored".
    return [ordered]@{
        'intent.md'       = @'
# Intent

<!-- Captured during the /cip interview. Placeholder — replace before drafting. -->

## Goal

TBD

## Desired outcome

TBD

## Success signals

- TBD

## Non-goals

- TBD

## Definition of done

- TBD
'@
        'requirements.md' = @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | | Use typed evidence markers in criteria: `test:<TestId>` · `file:<path>#exists` · `file:<path>#contains:<regex>` · `file:<path>#count>=<N>` · `file:<path>#dircount>=<N>` · `review:cr|dr` | |
'@
        'risks.md'        = @'
# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | | Low/Medium/High | Low/Medium/High | | 1.2 |
'@
        'decisions.md'    = @'
# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- TBD
'@
        'references.md'   = @'
# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- TBD
'@
    }
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

# Plans and epics share one id space — `/ci` accepts either handle — so both inventories reserve ids,
# in both directions, and an explicitly supplied id is collision-checked rather than trusted.
$takenIds = @(Get-PlanInventory -RepoRoot $repoRootPath) + @(Get-EpicInventory -RepoRoot $repoRootPath)

if ($PlanId) {
    $PlanId = $PlanId.Trim().ToLowerInvariant()
    if ($PlanId -notmatch '^[0-9a-f]{6}$') {
        throw "PlanId '$PlanId' must be exactly 6 hex chars."
    }
}
else {
    $PlanId = New-PlanId -ExistingId @($takenIds | ForEach-Object { $_.Id })
}

foreach ($existing in $takenIds) {
    if ($existing.Id -and $existing.Id.ToLowerInvariant() -eq $PlanId -and $existing.FolderName -ne "$Date-$PlanId-$slugClean") {
        throw "Plan id '$PlanId' is already taken by '$($existing.FolderName)'."
    }
}

$folderName = "$Date-$PlanId-$slugClean"
$targetDir = Resolve-ConfinedFolder -Root $plansRoot -FolderName $folderName
$planFile = Join-Path $targetDir 'plan.md'

if ((Test-Path -LiteralPath $targetDir) -and -not $Force) {
    throw "Plan folder already exists: $targetDir (use -Force to overwrite plan.md)."
}

if (-not $TemplatePath) {
    # An installed copy has no `plugins/` tree — only `.github/skills/<skill>/…` — so probe the skill's
    # own assets folder beside this script first and fall back to the source-repo layout.
    $templateCandidates = @(
        (Join-Path $PSScriptRoot '..' 'assets' 'plan-template.md')
        (Join-Path $repoRootPath 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md')
        (Join-Path $repoRootPath '.github/skills/cip/assets/plan-template.md')
    )
    foreach ($candidate in $templateCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $TemplatePath = [System.IO.Path]::GetFullPath($candidate)
            break
        }
    }
    if (-not $TemplatePath) {
        throw "Plan template not found; probed: $(($templateCandidates | ForEach-Object { [System.IO.Path]::GetFullPath($_) }) -join ', ')."
    }
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

$assetsDir = Resolve-ConfinedFolder -Root $targetDir -FolderName 'assets'
New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
$assetFiles = [System.Collections.Generic.List[string]]::new()
foreach ($entry in (Get-PlanAssetScaffold).GetEnumerator()) {
    $assetPath = Join-Path $assetsDir $entry.Key
    # Never overwrite an existing asset: -Force means "overwrite plan.md", and re-scaffolding over
    # authored requirements/risks/decisions would silently destroy the plan's content.
    if (Test-Path -LiteralPath $assetPath -PathType Leaf) {
        $assetFiles.Add($assetPath)
        continue
    }
    Set-Content -LiteralPath $assetPath -Value ($entry.Value -replace "`r`n", "`n") -Encoding utf8NoBOM
    $assetFiles.Add($assetPath)
}

$result = [pscustomobject]@{
    PlanId = $PlanId
    Slug = $slugClean
    Date = $Date
    FolderName = $folderName
    Path = $targetDir
    PlanFile = $planFile
    AssetsDir = $assetsDir
    AssetFiles = $assetFiles.ToArray()
}

Write-Host "Created plan '$folderName' (plan-id $PlanId) at $planFile" -ForegroundColor Green
return $result
