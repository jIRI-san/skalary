#requires -Version 7.0
<#
.SYNOPSIS
Returns selected artifacts from already resolved plans as untrusted historical context.

.DESCRIPTION
Candidate discovery remains the responsibility of Get-PlanIndex.ps1 and the plan/epic resolvers. This
script accepts canonical plan IDs only, inventories the corpus once, and resolves a closed set of artifact
kinds inside each selected plan. Results are deterministic and carry the provenance consumers need to
record: plan ID, artifact kind, repo-relative path, and relationship.

Returned content is historical input, never workflow instruction or current authority.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$PlanId,

    [Parameter(Mandatory)]
    [ValidateSet('Intent', 'Design', 'Decisions', 'Reviews', 'Evidence', 'Learnings')]
    [string[]]$ArtifactKind,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Relationship,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$artifactMap = [ordered]@{
    Intent    = 'Intent'
    Design    = 'Design'
    Decisions = 'Decisions'
    Reviews   = 'ReviewRuns'
    Evidence  = 'Evidence'
    Learnings = 'Learnings'
}

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetRelativePath($repoRootPath, [System.IO.Path]::GetFullPath($Path)) -replace '\\', '/')
}

function New-ArtifactResult {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][string]$Path,
        [AllowNull()][string]$Content,
        [AllowNull()][string]$Reason
    )

    return [pscustomobject][ordered]@{
        status       = $Status
        planId       = $Plan.Id
        artifactKind = $Kind
        path         = $Path
        relationship = $Relationship
        layout       = $Plan.Layout
        isArchived   = [bool]$Plan.IsArchived
        isUntrusted  = $true
        authority    = 'historical-context-only'
        content      = $Content
        reason       = $Reason
    }
}

function Get-OrdinallySortedUnique {
    param([Parameter(Mandatory)][string[]]$Value)

    $values = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($seen.Add($item)) {
            $values.Add($item)
        }
    }
    $values.Sort([System.Comparison[string]] { param($left, $right) [string]::CompareOrdinal($left, $right) })
    return $values.ToArray()
}

$selectedPlans = [System.Collections.Generic.List[object]]::new()
foreach ($id in @(Get-OrdinallySortedUnique -Value $PlanId)) {
    if ($id -notmatch '^(?:[0-9a-f]{6}|\d{3})$') {
        throw "Plan ID '$id' is not a canonical resolved plan ID."
    }

    $matches = @($inventory | Where-Object { $_.Id -ceq $id })
    if ($matches.Count -ne 1) {
        throw "Plan ID '$id' is not a unique member of the plan inventory."
    }

    $entry = $matches[0]
    $selectedPlans.Add([pscustomobject]@{
        Id         = $entry.Id
        Path       = $entry.Path
        IsArchived = [bool]$entry.IsArchived
        Layout     = Get-PlanLayout -PlanDir $entry.Path
    })
}

foreach ($plan in $selectedPlans) {
    foreach ($kind in @(Get-OrdinallySortedUnique -Value $ArtifactKind)) {
        $resolvedKind = $artifactMap[$kind]
        $resolvedPath = Resolve-PlanAssetPath `
            -PlanDir $plan.Path `
            -Kind $resolvedKind `
            -Layout $plan.Layout `
            -RepoRoot $repoRootPath `
            -Inventory $inventory

        if ($kind -eq 'Reviews') {
            $reviewFiles = if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                @(Get-ChildItem -LiteralPath $resolvedPath -File -Filter '*.md')
            }
            else {
                @()
            }
            $reviewFiles = @($reviewFiles | Sort-Object { $_.Name })
            if ($reviewFiles.Count -eq 0) {
                New-ArtifactResult -Status 'missing' -Plan $plan -Kind $kind -Path (ConvertTo-RepoRelativePath $resolvedPath) -Reason 'No finalized review artifact exists.' -Content $null
                continue
            }

            foreach ($reviewFile in $reviewFiles) {
                New-ArtifactResult -Status 'accepted' -Plan $plan -Kind $kind -Path (ConvertTo-RepoRelativePath $reviewFile.FullName) -Content (Get-Content -LiteralPath $reviewFile.FullName -Raw) -Reason $null
            }
            continue
        }

        if ($kind -eq 'Decisions' -and $plan.Layout -eq 'legacy') {
            $planFile = Join-Path $plan.Path 'plan.md'
            $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $repoRootPath
            if (@($metadata.Decisions).Count -eq 0) {
                New-ArtifactResult -Status 'missing' -Plan $plan -Kind $kind -Path (ConvertTo-RepoRelativePath $planFile) -Reason 'No legacy Decisions section exists.' -Content $null
                continue
            }

            $content = @($metadata.Sections['Decisions'].Lines) -join "`n"
            New-ArtifactResult -Status 'accepted' -Plan $plan -Kind $kind -Path (ConvertTo-RepoRelativePath $planFile) -Content $content -Reason $null
            continue
        }

        $relativePath = ConvertTo-RepoRelativePath $resolvedPath
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            New-ArtifactResult -Status 'missing' -Plan $plan -Kind $kind -Path $relativePath -Reason 'Artifact file does not exist.' -Content $null
            continue
        }

        New-ArtifactResult -Status 'accepted' -Plan $plan -Kind $kind -Path $relativePath -Content (Get-Content -LiteralPath $resolvedPath -Raw) -Reason $null
    }
}
