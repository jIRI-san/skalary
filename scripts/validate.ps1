#requires -Version 7.0
<#
.SYNOPSIS
    Full-repository validation gate for the skalary customizations repo.
.DESCRIPTION
    Dependency-free verification used as both the autopilot `build` and `test`
    command (wired through package.json so it satisfies the autopilot config
    schema's `npm run` / `npm test` prefixes). It:
      * parses every PowerShell script (*.ps1/*.psm1/*.psd1) and fails on syntax
        errors, and
      * validates every JSON file (*.json) parses.
    The file set comes from PayloadScope.psm1, which enumerates an allowlist of
    payload roots so both platforms see the same files (REQ-8).
    Full scope is opt-in through -FullRepository so a phase Fast check cannot
    accidentally expand into this repository-wide scan.
    No external modules are required, so it runs identically on the Windows host
    and inside the Linux autopilot container (which ships pwsh).
#>
[CmdletBinding()]
param(
    [switch]$FullRepository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $FullRepository) {
    Write-Host 'FullRepositoryRequired: scripts/validate.ps1 scans the entire repository. Pass -FullRepository only at finalization or an explicit operator-requested full run.' -ForegroundColor Red
    exit 2
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

# REQ-8/RISK-5: the file set is an allowlist of payload roots, canonicalised, with
# reparse points refused. Without it `.github` was parsed on Windows and skipped on
# Linux — where pwsh treats dot-prefixed entries as hidden — so the two CI legs passed
# over different files while both reported success.
Import-Module (Join-Path $PSScriptRoot 'skalary/PayloadScope.psm1') -Force -DisableNameChecking

Write-Host '== Validating PowerShell scripts =='
$psFiles = @(Get-SkalaryPayloadFile -RepoRoot $repoRoot -Extension '.ps1', '.psm1', '.psd1' -RequireRoot)
foreach ($file in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        foreach ($pe in $parseErrors) {
            $errors.Add("${file}:$($pe.Extent.StartLineNumber) $($pe.Message)")
        }
    }
}
Write-Host "  Parsed $($psFiles.Count) PowerShell file(s)."
if ($psFiles.Count -eq 0) {
    # An allowlist can fail by scanning nothing as easily as a denylist fails by scanning
    # too much, and a gate that parsed nothing has proved nothing.
    $errors.Add('No PowerShell files were enumerated; the payload allowlist matched nothing, so this run asserted nothing.')
}

Write-Host '== Validating JSON files =='
$jsonFiles = @(Get-SkalaryPayloadFile -RepoRoot $repoRoot -Extension '.json' -RequireRoot)
foreach ($file in $jsonFiles) {
    try {
        # -AsHashtable so standard npm lock files (which use an empty-string root package key under
        # "packages") still validate as well-formed; the check only asserts the JSON parses.
        $null = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        $errors.Add("${file}: invalid JSON - $($_.Exception.Message)")
    }
}
Write-Host "  Parsed $($jsonFiles.Count) JSON file(s)."
if ($jsonFiles.Count -eq 0) {
    $errors.Add('No JSON files were enumerated; the payload allowlist matched nothing, so this run asserted nothing.')
}

Write-Host '== Validating architecture contract integrity =='
$contractIntegrityGate = Join-Path $repoRoot 'scripts/skalary/Test-ArchitectureContractIntegrity.ps1'
try {
    $contractIntegrity = & $contractIntegrityGate -RepoRoot $repoRoot -NoExit
    if (-not $contractIntegrity.Valid) {
        foreach ($message in $contractIntegrity.Errors) {
            $errors.Add([string]$message)
        }
    }
    Write-Host "  Checked $($contractIntegrity.Count) architecture contract(s)."
}
catch {
    $errors.Add("Architecture contract integrity sweep failed: $($_.Exception.Message)")
}

Write-Host '== Validating plugin script bundles =='
$bundleSync = Join-Path $repoRoot 'scripts/skalary/Sync-PluginScripts.ps1'
try {
    & $bundleSync -RepoRoot $repoRoot -WhatIf *> $null
    Write-Host '  Plugin script bundles in sync with scripts/skalary.'
}
catch {
    $errors.Add("Plugin script bundle drift: $($_.Exception.Message)")
}

Write-Host '== Validating Copilot CLI marketplace =='
$marketplaceBuild = Join-Path $repoRoot 'scripts/skalary/Build-Marketplace.ps1'
try {
    & $marketplaceBuild -RepoRoot $repoRoot -WhatIf *> $null
    Write-Host '  .github/plugin/marketplace.json in sync with plugins/ sources.'
}
catch {
    $errors.Add("Marketplace drift: $($_.Exception.Message)")
}

Write-Host '== Validating agent model declarations =='
$modelAllowlistGate = Join-Path $repoRoot 'scripts/skalary/Test-ModelAllowlist.ps1'
& $modelAllowlistGate -RepoRoot $repoRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    # Re-run visibly so the operator sees which agent or config drifted.
    & $modelAllowlistGate -RepoRoot $repoRoot
    $errors.Add('Agent model declarations violate tools/model-allowlist.psd1.')
}

Write-Host '== Validating skill size cap =='
$skillSizeGate = Join-Path $repoRoot 'scripts/skalary/Test-SkillSize.ps1'
& $skillSizeGate -RepoRoot $repoRoot
if ($LASTEXITCODE -ne 0) {
    $errors.Add('One or more SKILL.md files exceed the size cap; move detail into the skill''s assets/.')
}

Write-Host '== Validating implementation plans (Draft stage) =='
Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
$planValidator = Join-Path $repoRoot 'scripts/skalary/Test-Plan.ps1'
$planPaths = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs/implementation-plans') -Recurse -File -Filter 'plan.md' |
    Sort-Object FullName
$checkedCount = 0
$skippedCount = 0
foreach ($plan in $planPaths) {
    # The same decision `Validate-Plan.ps1` makes, from the same place. Both legs of `npm test` validate
    # plans, so a floor honoured by only one of them changes nothing except which leg reports the
    # failure. An unrecognised stage is a hard error here, never a skip.
    try {
        $decision = Get-PlanValidationDecision -Path $plan.FullName
    }
    catch {
        $errors.Add("$($plan.FullName): $($_.Exception.Message)")
        continue
    }

    if (-not $decision.ShouldValidate) {
        Write-Host "  $($decision.Signal)"
        $skippedCount++
        continue
    }

    & $planValidator -PlanPath $plan.FullName -RepoRoot $repoRoot -Stage Draft
    $checkedCount++
    if ($LASTEXITCODE -ne 0) {
        $errors.Add("$($plan.FullName): Test-Plan failed at Draft stage.")
    }
}
Write-Host "  Checked $checkedCount plan file(s); skipped $skippedCount below the drafted floor."

Write-Host '== Validating architecture human-doc freshness =='
$freshnessGate = Join-Path $repoRoot 'scripts/skalary/Test-ArchDocFreshness.ps1'
try {
    & $freshnessGate -RepoRoot $repoRoot *> $null
    if ($LASTEXITCODE -ne 0) {
        $errors.Add('Architecture human doc is stale; regenerate it with New-ArchHumanDoc.ps1 (/uan).')
    }
    else {
        Write-Host '  Architecture human doc fresh (or tier not seeded).'
    }
}
catch {
    $errors.Add("Architecture doc freshness check failed: $($_.Exception.Message)")
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host "VALIDATION FAILED ($($errors.Count) error(s)):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host 'Validation passed.' -ForegroundColor Green
exit 0
