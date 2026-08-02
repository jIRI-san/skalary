#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$PlanPath,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

function Resolve-DefaultPlanPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $plans = @(Get-ChildItem -LiteralPath (Join-Path $Root 'docs/implementation-plans') -File -Recurse -Filter 'plan.md' |
        Where-Object { $_.FullName -notmatch '/archived/' } |
        Sort-Object FullName)
    if ($plans.Count -eq 0) {
        throw 'No plan.md files found in docs/implementation-plans/.'
    }

    # Every candidate's stage is resolved, not just the chosen one: a plan carrying a bad marker is a
    # defect wherever it sits, and passing over it would hide it until the day it happens to be picked.
    $validatable = @($plans | Where-Object { (Get-PlanValidationDecision -Path $_.FullName).ShouldValidate })
    if ($validatable.Count -eq 0) {
        return $null
    }

    foreach ($plan in $validatable) {
        $content = Get-Content -LiteralPath $plan.FullName -Raw
        if ($content -match '(?m)^\s*-\s\[(?:~|\s)\]\s+\d+\.\d+[a-z]?\s') {
            return $plan.FullName
        }
    }

    return $validatable[0].FullName
}

$targetPlan = if ([string]::IsNullOrWhiteSpace($PlanPath)) { Resolve-DefaultPlanPath -Root $RepoRoot } else { $PlanPath }

# A skip is reported in a form a downstream check cannot read as a pass. Exiting 0 with no signal is
# what turns "nothing was validated" into "validation succeeded".
if (-not $targetPlan) {
    Write-Host 'PLAN-VALIDATION: SKIPPED reason=no-plan-at-or-above-floor'
    exit 0
}

$decision = Get-PlanValidationDecision -Path $targetPlan
Write-Host $decision.Signal
if (-not $decision.ShouldValidate) {
    exit 0
}

$validatorPath = Join-Path $RepoRoot 'scripts/skalary/Test-Plan.ps1'
& $validatorPath -PlanPath $targetPlan -RepoRoot $RepoRoot -Stage Draft
exit $LASTEXITCODE
