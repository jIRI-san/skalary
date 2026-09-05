#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$policyPath = Join-Path $repoRootPath 'tools/model-allowlist.psd1'
$policy = Import-PowerShellDataFile -LiteralPath $policyPath
$changes = [System.Collections.Generic.List[string]]::new()

function Set-GeneratedContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $current = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [System.IO.File]::ReadAllText($Path)
    }
    else {
        $null
    }
    if ($current -ceq $Content) { return }

    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $Path).Replace('\', '/')
    $changes.Add($relative)
    if ($Check) { return }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    if ($PSCmdlet.ShouldProcess($relative, 'Update generated model binding')) {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    }
}

$policyContent = [System.IO.File]::ReadAllText($policyPath)
$assetPaths = @(
    'plugins/autopilot/skills/autopilot/assets/model-aliases.psd1'
    'plugins/code-review/skills/cr/assets/model-aliases.psd1'
    'plugins/continue-implementation/skills/ci/assets/model-aliases.psd1'
    'plugins/create-implementation-plan/skills/cip/assets/model-aliases.psd1'
    'plugins/design-review/skills/dr/assets/model-aliases.psd1'
)
foreach ($relative in $assetPaths) {
    Set-GeneratedContent -Path (Join-Path $repoRootPath $relative) -Content $policyContent
}

$executorAlias = [string]$policy.Roles.WazaExecutor
$judgeAlias = [string]$policy.Roles.WazaJudge
$executorModel = [string]$policy.Aliases[$executorAlias].Cli
$judgeModel = [string]$policy.Aliases[$judgeAlias].Cli
if ([string]::IsNullOrWhiteSpace($executorModel) -or [string]::IsNullOrWhiteSpace($judgeModel)) {
    throw 'Waza model aliases must resolve to concrete CLI model identifiers.'
}

$specFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRootPath 'plugins') -Recurse -File -Filter 'eval.yaml' |
        Where-Object { $_.FullName -match '[\\/]evals[\\/]waza[\\/]eval\.yaml$' }
)
foreach ($file in $specFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $updated = [regex]::Replace(
        $content,
        '(?m)^(?<prefix>  model:\s*)[^\r\n]+$',
        "`${prefix}$executorModel"
    )
    $updated = [regex]::Replace(
        $updated,
        '(?m)^(?<prefix>  judge_model:\s*)[^\r\n]+$',
        "`${prefix}$judgeModel"
    )
    Set-GeneratedContent -Path $file.FullName -Content $updated
}

$taskFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRootPath 'plugins') -Recurse -File -Filter '*.yaml' |
        Where-Object { $_.FullName -match '[\\/]evals[\\/]waza[\\/]tasks[\\/]' }
)
foreach ($file in $taskFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $updated = [regex]::Replace(
        $content,
        '(?m)^(?<prefix>\s{6}model:\s*)[^\r\n]+$',
        "`${prefix}$judgeModel"
    )
    Set-GeneratedContent -Path $file.FullName -Content $updated
}

if ($Check -and $changes.Count -gt 0) {
    throw "Model binding drift detected: $($changes -join ', '). Run scripts/skalary/Sync-ModelBindings.ps1."
}

Write-Host "Model binding sync completed. Changed file count: $($changes.Count)."
