#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [Parameter(Mandatory)]
    [string]$PlanPath,
    [string]$DependencyReference = '006'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force

function Resolve-DependencyId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Reference,
        [Parameter(Mandatory)]
        [string]$Root,
        [AllowEmptyCollection()]
        [object[]]$Inventory = @()
    )

    $literal = $Reference.Trim().ToLowerInvariant()
    if ($Inventory.Count -gt 0) {
        try {
            $resolved = Resolve-Plan -Reference $Reference -RepoRoot $Root -Inventory $Inventory
            if ($resolved -and $resolved.Id) {
                return $resolved.Id.ToLowerInvariant()
            }
        }
        catch {
            # No unambiguous plan match; fall back to literal token comparison below.
        }
    }
    return $literal
}

function Test-PlanDependsOnTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$TargetReference
    )

    $inventory = @()
    try {
        $inventory = @(Get-PlanInventory -RepoRoot $Root)
    }
    catch {
        $inventory = @()
    }

    # Resolve the guarded plan reference and every declared dependency to a canonical id so a
    # legacy 3-digit number, a hash (prefix), a slug, or a date all trigger identical behavior.
    $targetId = Resolve-DependencyId -Reference $TargetReference -Root $Root -Inventory $inventory

    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    foreach ($match in [regex]::Matches($content, '<!--\s*depends-on:\s*(?<deps>[^>]+?)-->', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $deps = $match.Groups['deps'].Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($dep in $deps) {
            if ((Resolve-DependencyId -Reference $dep -Root $Root -Inventory $inventory) -eq $targetId) {
                return $true
            }
        }
    }

    return $false
}

function Assert-FileContains {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $fullPath = Join-Path $Root ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Missing required dependency file '$RelativePath'."
    }

    $text = Get-Content -LiteralPath $fullPath -Raw -Encoding utf8
    if ($text -notmatch $Pattern) {
        throw "Dependency contract missing in '$RelativePath' (pattern '$Pattern')."
    }
}

function Invoke-TestPlanEvidenceProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [Parameter(Mandatory)]
        [string]$Marker
    )

    $output = @(
        & pwsh -NoProfile -File $ScriptPath -RepoRoot $Root -EvidenceMarker $Marker -EvidenceStage PhaseCrosscheck 2>&1
    )

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | ForEach-Object { "$_" }) -join "`n"
    }
}

try {
    $resolvedRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepoRoot).Path)
    $resolvedPlanPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PlanPath).Path)

    $rootWithSeparator = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedPlanPath -ne $resolvedRoot -and -not $resolvedPlanPath.StartsWith($rootWithSeparator, [System.StringComparison]::Ordinal)) {
        throw "Plan path '$resolvedPlanPath' is outside repository root '$resolvedRoot'."
    }

    if (-not (Test-PlanDependsOnTarget -Path $resolvedPlanPath -Root $resolvedRoot -TargetReference $DependencyReference)) {
        Write-Host "Plan does not declare depends-on: $DependencyReference; dependency gate skipped."
        exit 0
    }

    $testPlanPath = Join-Path $PSScriptRoot 'Test-Plan.ps1'
    if (-not (Test-Path -LiteralPath $testPlanPath -PathType Leaf)) {
        throw "Missing required script 'scripts/skalary/Test-Plan.ps1'."
    }

    $testPlanCommand = Get-Command -Name $testPlanPath -CommandType ExternalScript -ErrorAction Stop
    $hasPublicEvaluatorPath = $testPlanCommand.Parameters.ContainsKey('EvidenceMarker') -or $testPlanCommand.Parameters.ContainsKey('VerifyEvidence')
    if (-not $hasPublicEvaluatorPath) {
        throw "Test-Plan public file-evidence path is unavailable (expected parameter 'EvidenceMarker' or 'VerifyEvidence')."
    }

    $passProbe = Invoke-TestPlanEvidenceProbe -Root $resolvedRoot -ScriptPath $testPlanPath -Marker 'file:README.md#exists'
    if ($passProbe.ExitCode -ne 0) {
        throw "Expected file-evidence pass probe failed.`n$($passProbe.Output)"
    }

    $failProbe = Invoke-TestPlanEvidenceProbe -Root $resolvedRoot -ScriptPath $testPlanPath -Marker 'file:README.md#contains:__SKALARY_PLAN006_DEPENDENCY_PROBE_SHOULD_FAIL__'
    if ($failProbe.ExitCode -eq 0) {
        throw 'Expected file-evidence fail probe unexpectedly passed.'
    }
    if ($failProbe.Output -notmatch 'Evidence failed') {
        throw "Expected file-evidence fail probe failed for an unexpected reason (no 'Evidence failed' signal).`n$($failProbe.Output)"
    }

    # Compatibility-anchor tokens: literal contract strings that downstream skills/agents depend on.
    # Phase-5 slimming MUST preserve these exact tokens; this gate fails loudly if any are dropped.
    $compatibilityAnchors = @(
        @{ Path = 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md'; Pattern = 'Test-Plan\.ps1' }
        @{ Path = 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'; Pattern = 'test:<TestId>' }
        @{ Path = 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'; Pattern = 'file:<path>#<assertion>' }
        @{ Path = 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'; Pattern = 'review:cr\|dr' }
        @{ Path = 'plugins/autopilot/agents/autopilot.agent.md'; Pattern = 'Run-UnitTests\.ps1 -TestPath' }
    )
    foreach ($anchor in $compatibilityAnchors) {
        Assert-FileContains -Root $resolvedRoot -RelativePath $anchor.Path -Pattern $anchor.Pattern
    }

    $packageJsonPath = Join-Path $resolvedRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        throw "Missing required dependency file 'package.json'."
    }

    $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$packageJson.scripts.test -notmatch 'Run-UnitTests\.ps1\s+-TestPath') {
        throw "package.json script 'test' must use focused Run-UnitTests.ps1 -TestPath."
    }

    Write-Host "Plan $DependencyReference dependency preflight passed."
    exit 0
}
catch {
    Write-Host "Plan $DependencyReference dependency preflight failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
