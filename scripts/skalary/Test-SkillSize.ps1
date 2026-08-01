#requires -Version 7.0
<#
.SYNOPSIS
    Enforces the repo-wide `SKILL.md` size cap.
.DESCRIPTION
    Plan b0c0d3 REQ-16. A `SKILL.md` is loaded into context in full every time its skill is
    invoked, so its size is a recurring per-invocation cost rather than a one-off. The cap keeps
    the always-loaded body terse and pushes reference detail into `assets/`, which the skill
    reads on demand.

    Every `SKILL.md` in the repo is measured — plugin sources under `plugins/` and the dogfood
    mirror under `.github/skills/` alike, because the mirror is what VS Code and the Copilot CLI
    actually load. Size is measured in bytes of file content; a file at or under `-MaxBytes`
    passes.

    A file within `-WarnRatio` of the cap is reported as a warning (never a failure) so a skill
    creeping toward the cap is visible before it breaks the gate.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-SkillSize.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-SkillSize.ps1 -MaxBytes 8000 -PassThru
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    # 12 KB. Chosen against the largest skill this plan touches so the cap constrains new
    # authoring without being satisfiable only by gutting an existing skill.
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxBytes = 12000,

    [ValidateRange(0.0, 1.0)]
    [double]$WarnRatio = 0.9,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    Write-Host "Test-SkillSize failed: repo root not found: $repoRootPath" -ForegroundColor Red
    exit 1
}

$skipRegex = '[\\/](\.git|node_modules|bin|obj|\.worktrees)[\\/]'
$violations = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$warnBytes = [int][math]::Floor($MaxBytes * $WarnRatio)

$skillFiles = @(
    # -Force is required: `.github/` is a hidden directory, and without it the dogfood copies
    # the hosts actually load would never be measured.
    Get-ChildItem -LiteralPath $repoRootPath -Recurse -File -Force -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skipRegex } |
        Sort-Object FullName
)

foreach ($file in $skillFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName).Length

    if ($bytes -gt $MaxBytes) {
        $over = $bytes - $MaxBytes
        $violations.Add("$relative is $bytes bytes, $over over the $MaxBytes-byte cap. Move reference detail into its 'assets/' folder and read it on demand (declare the asset in the plugin's files[]).")
    }
    elseif ($bytes -gt $warnBytes) {
        $warnings.Add("$relative is $bytes bytes, within $($MaxBytes - $bytes) of the $MaxBytes-byte cap.")
    }
}

foreach ($warning in $warnings) {
    Write-Host "WARN: $warning" -ForegroundColor Yellow
}

if ($violations.Count -gt 0) {
    foreach ($violation in $violations) {
        Write-Host "ERROR: $violation" -ForegroundColor Red
    }
    if ($PassThru) { $violations }
    exit 1
}

Write-Host "Test-SkillSize passed: $($skillFiles.Count) SKILL.md file(s) within the $MaxBytes-byte cap." -ForegroundColor Green
if ($PassThru) { @() }
exit 0
