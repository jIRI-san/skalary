#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PlanPath,

    [Parameter(Mandatory)]
    [ValidateRange(0, 999)]
    [int]$Phase,

    [string]$RepoRoot = (git rev-parse --show-toplevel),

    [string]$HarvestValidator = (Join-Path $PSScriptRoot 'Invoke-PhaseHarvest.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $planPathFull = [System.IO.Path]::GetFullPath(
        $(if ([System.IO.Path]::IsPathRooted($PlanPath)) {
                $PlanPath
            }
            else {
                Join-Path $repoRootFull $PlanPath
            })
    )
    if (-not (Test-Path -LiteralPath $planPathFull -PathType Leaf)) {
        throw "Plan file not found: $planPathFull"
    }
    if (-not (Test-Path -LiteralPath $HarvestValidator -PathType Leaf)) {
        throw "Phase-harvest validator not found: $HarvestValidator"
    }

    Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
    $metadata = Get-PlanMetadata -Path $planPathFull -RepoRoot $repoRootFull
    $phaseHeading = @(
        $metadata.PhaseSteps.Keys |
            Where-Object { [string]$_ -match "^##\s+Phase\s+$Phase(?:\D|$)" }
    )
    if ($phaseHeading.Count -ne 1) {
        throw "Plan must contain exactly one Phase $Phase heading."
    }

    $steps = @($metadata.PhaseSteps[$phaseHeading[0]])
    if ($steps.Count -eq 0) {
        throw "Phase $Phase contains no executable steps."
    }
    if (@($steps | Where-Object { [string]$_.Status -ne 'x' }).Count -gt 0) {
        Write-Output 'execution-required'
        return
    }

    $planDirFull = Split-Path -Parent $planPathFull
    $receiptRoot = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind HarvestReceiptRoot `
        -RepoRoot $repoRootFull
    $receiptPath = Join-Path $receiptRoot ('phase-{0:D3}.json' -f $Phase)
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        Write-Output 'close-pending'
        return
    }

    foreach ($requiredPath in @($planPathFull, $receiptPath)) {
        $relativePath = (& git -C $repoRootFull ls-files --full-name --error-unmatch -- $requiredPath 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($relativePath)) {
            Write-Output 'close-pending'
            return
        }
        $pathStatus = (& git -C $repoRootFull status --porcelain --untracked-files=all -- $requiredPath)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect committed phase-close path '$requiredPath'."
        }
        if (-not [string]::IsNullOrWhiteSpace(($pathStatus -join "`n"))) {
            Write-Output 'close-pending'
            return
        }
    }

    $validationOutput = & pwsh -NoProfile -File $HarvestValidator `
        -PlanDir $planDirFull -Phase $Phase -ValidateReceipt -RepoRoot $repoRootFull 2>&1
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine(
            "Phase $Phase harvest receipt is invalid.`n$($validationOutput -join "`n")"
        )
        exit 2
    }

    Write-Output 'closed'
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
