#requires -Version 7.0
<#
.SYNOPSIS
Materializes one explicit Git baseline and invokes the pure-file retirement comparator.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [Parameter(Mandatory)]
    [string]$BaselineSha,

    [Parameter(Mandatory)]
    [string]$CandidateSha,

    [string]$CandidatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($BaselineSha -notmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') {
    throw "BaselineSha must be a full Git object id: '$BaselineSha'."
}
if ($CandidateSha -notmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') {
    throw "CandidateSha must be a full Git object id: '$CandidateSha'."
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $CandidatePath) {
    $CandidatePath = Join-Path $root 'registry-retirements.json'
}
$comparisonScript = Join-Path $PSScriptRoot 'Test-PluginRetirementHistory.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plugin-retirement-history-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)
$baselinePath = Join-Path $tempRoot 'baseline.json'
$emptyTree = $BaselineSha -match '^0+$'
$baselineIdentity = if ($emptyTree) { 'empty-tree' } else { $BaselineSha }

try {
    git -C $root cat-file -e "$CandidateSha`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Required plugin-retirement candidate commit is unavailable: $CandidateSha"
    }

    if (-not $emptyTree) {
        git -C $root cat-file -e "$BaselineSha`^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Required plugin-retirement baseline commit is unavailable: $BaselineSha"
        }
    }

    $hasBaselineFile = $false
    if (-not $emptyTree) {
        git -C $root cat-file -e "${BaselineSha}:registry-retirements.json" 2>$null
        $hasBaselineFile = $LASTEXITCODE -eq 0
    }
    if ($hasBaselineFile) {
        $lines = @(git -C $root show "${BaselineSha}:registry-retirements.json")
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to materialize plugin-retirement baseline from $BaselineSha."
        }
        [System.IO.File]::WriteAllText($baselinePath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
    else {
        [System.IO.File]::WriteAllText($baselinePath, "{`n  `"retiredPlugins`": [],`n  `"version`": 1`n}`n", [System.Text.UTF8Encoding]::new($false))
    }

    $result = & $comparisonScript -BaselinePath $baselinePath -CandidatePath $CandidatePath
    Write-Host "RETIREMENT-HISTORY baseline=$baselineIdentity baselineCount=$($result.BaselineCount) candidate=$CandidateSha candidateCount=$($result.CandidateCount)"
    $result
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
