#requires -Version 7.0
<#
.SYNOPSIS
    Validates every committed agent model declaration against the closed model allowlist.
.DESCRIPTION
    Model aliases resolve through tools/model-allowlist.psd1. Host-facing agent bindings retain
    the exact qualified VS Code name or bare CLI slug, while operator-facing autopilot configs
    and dispatch guidance use stable aliases. Agent host is selected from the closed map and
    is never inferred from folder layout.

    Checks performed:
      * every `*.agent.md` declares a frontmatter `name`, and that name is mapped to a host;
      * a declared `model:` is a member of that host's list (so a qualified name on a CLI
        agent, or a bare slug on a VS Code agent, fails loud);
      * no agent file references a denied model/vendor anywhere in its text;
      * every `.autopilot.json` / `.autopilot.json.example` `model` is a known alias;
      * the alias map and fallback aliases are self-consistent.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-ModelAllowlist.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$AllowlistPath,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    Write-Host "Test-ModelAllowlist failed: repo root not found: $repoRootPath" -ForegroundColor Red
    exit 1
}

if (-not $AllowlistPath) {
    $AllowlistPath = Join-Path $repoRootPath 'tools/model-allowlist.psd1'
}
$allowlistFullPath = [System.IO.Path]::GetFullPath($AllowlistPath)

$skipRegex = '[\\/](\.git|node_modules|bin|obj|\.worktrees)[\\/]'
$configNames = @('.autopilot.json', '.autopilot.json.example')
$violations = [System.Collections.Generic.List[string]]::new()

function Get-Frontmatter {
    <#
    .SYNOPSIS
    Returns the raw YAML frontmatter block of a markdown file, or $null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $match = [regex]::Match($Content, '(?s)\A---\r?\n(?<body>.*?)\r?\n---\r?\n')
    if (-not $match.Success) { return $null }
    return $match.Groups['body'].Value
}

function Get-FrontmatterField {
    <#
    .SYNOPSIS
    Reads one scalar frontmatter field, stripping surrounding quotes. $null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Frontmatter,
        [Parameter(Mandatory)][string]$Name
    )

    $match = [regex]::Match($Frontmatter, "(?m)^$([regex]::Escape($Name)):\s*(?<value>.*?)\s*$")
    if (-not $match.Success) { return $null }

    $value = $match.Groups['value'].Value
    if ($value.Length -ge 2) {
        foreach ($quote in @('"', "'")) {
            if ($value.StartsWith($quote) -and $value.EndsWith($quote)) {
                $value = $value.Substring(1, $value.Length - 2)
                break
            }
        }
    }
    return $value
}

if (-not (Test-Path -LiteralPath $allowlistFullPath -PathType Leaf)) {
    Write-Host "Test-ModelAllowlist failed: allowlist not found: $allowlistFullPath" -ForegroundColor Red
    exit 1
}

try {
    $allowlist = Import-PowerShellDataFile -LiteralPath $allowlistFullPath
}
catch {
    Write-Host "Test-ModelAllowlist failed: cannot parse '$allowlistFullPath' - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

foreach ($key in @('Aliases', 'Roles', 'AgentHosts', 'Fallback', 'DeniedPatterns')) {
    if (-not $allowlist.ContainsKey($key)) {
        Write-Host "Test-ModelAllowlist failed: allowlist is missing required key '$key'." -ForegroundColor Red
        exit 1
    }
}

$aliases = $allowlist.Aliases
$modelsByHost = @{}
foreach ($hostKey in @('VSCode', 'Cli')) {
    $modelsByHost[$hostKey] = @(
        $aliases.Values |
            ForEach-Object { [string]$_[$hostKey] } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}
$agentHosts = $allowlist.AgentHosts
$deniedPatterns = @($allowlist.DeniedPatterns)

# Manifest self-consistency: all six stable aliases have both host bindings and fallbacks
# point to aliases rather than duplicating concrete provider names.
$requiredAliases = @(
    'primary-model-low'
    'primary-model-mid'
    'primary-model-high'
    'secondary-model-low'
    'secondary-model-mid'
    'secondary-model-high'
)
foreach ($alias in $requiredAliases) {
    if (-not $aliases.ContainsKey($alias)) {
        $violations.Add("allowlist: missing required model alias '$alias'.")
        continue
    }
    foreach ($hostKey in @('VSCode', 'Cli')) {
        if ([string]::IsNullOrWhiteSpace([string]$aliases[$alias][$hostKey])) {
            $violations.Add("allowlist: alias '$alias' has no $hostKey binding.")
        }
    }
}
foreach ($alias in @($aliases.Keys)) {
    if ($alias -notin $requiredAliases) {
        $violations.Add("allowlist: unexpected model alias '$alias'; the public alias set is closed.")
    }
}
foreach ($roleName in @('Routine', 'Standard', 'Deep', 'Independent')) {
    $role = $allowlist.Roles[$roleName]
    if ($null -eq $role) {
        $violations.Add("allowlist: missing required role '$roleName'.")
        continue
    }
    foreach ($field in @('Primary', 'Fallback')) {
        $roleAlias = [string]$role[$field]
        if (-not $aliases.ContainsKey($roleAlias)) {
            $violations.Add("allowlist: role '$roleName' $field '$roleAlias' is not a known alias.")
        }
    }
    if ([string]$role.ReasoningEffort -notin @('low', 'medium', 'high', 'xhigh', 'max')) {
        $violations.Add("allowlist: role '$roleName' has invalid reasoning effort '$($role.ReasoningEffort)'.")
    }
}
foreach ($roleName in @('WazaExecutor', 'WazaJudge')) {
    $roleAlias = [string]$allowlist.Roles[$roleName]
    if (-not $aliases.ContainsKey($roleAlias)) {
        $violations.Add("allowlist: role '$roleName' alias '$roleAlias' is not known.")
    }
}
foreach ($hostKey in @($allowlist.Fallback.Keys)) {
    if (-not $modelsByHost.ContainsKey($hostKey)) {
        $violations.Add("allowlist: Fallback declares unknown host '$hostKey' (expected 'VSCode' or 'Cli').")
        continue
    }
    $fallbackAlias = [string]$allowlist.Fallback[$hostKey]
    if (-not $aliases.ContainsKey($fallbackAlias)) {
        $violations.Add("allowlist: Fallback['$hostKey'] = '$fallbackAlias' is not a known alias.")
    }
}

foreach ($mappedAgent in @($agentHosts.Keys)) {
    $mappedHost = [string]$agentHosts[$mappedAgent]
    if (-not $modelsByHost.ContainsKey($mappedHost)) {
        $violations.Add("allowlist: AgentHosts['$mappedAgent'] = '$mappedHost' is not a known host (expected 'VSCode' or 'Cli').")
    }
}

$agentFiles = @(
    # -Force is required: `.github/` is a hidden directory, and without it the dogfood
    # copies VS Code and Copilot CLI actually load are silently never validated.
    Get-ChildItem -LiteralPath $repoRootPath -Recurse -File -Force -Filter '*.agent.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skipRegex } |
        Sort-Object FullName
)

foreach ($file in $agentFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName)

    foreach ($pattern in $deniedPatterns) {
        if ($content -match $pattern) {
            $violations.Add("$relative references a denied model/vendor (pattern '$pattern').")
        }
    }

    $frontmatter = Get-Frontmatter -Content $content
    if ($null -eq $frontmatter) {
        $violations.Add("$relative has no YAML frontmatter, so its host cannot be resolved.")
        continue
    }

    $agentName = Get-FrontmatterField -Frontmatter $frontmatter -Name 'name'
    if ([string]::IsNullOrWhiteSpace($agentName)) {
        $violations.Add("$relative has no frontmatter 'name', so its host cannot be resolved.")
        continue
    }

    if (-not $agentHosts.ContainsKey($agentName)) {
        $violations.Add("$relative declares agent '$agentName', which is absent from the AgentHosts map in '$([System.IO.Path]::GetFileName($allowlistFullPath))'. Add it explicitly — host is never inferred from folder layout.")
        continue
    }

    $agentHost = [string]$agentHosts[$agentName]
    if (-not $modelsByHost.ContainsKey($agentHost)) {
        # Already reported as an allowlist violation above; skip the per-file cascade.
        continue
    }

    $model = Get-FrontmatterField -Frontmatter $frontmatter -Name 'model'
    if ([string]::IsNullOrWhiteSpace($model)) {
        # Model-agnostic agent: the orchestrator supplies the model as an explicit
        # dispatch parameter, so there is nothing to validate here.
        continue
    }

    if ($modelsByHost[$agentHost] -contains $model) { continue }

    $detail = "$relative declares model '$model', which is not in the $agentHost allowlist."
    $looksQualified = $model -match '^.+\s\([^)]+\)$'
    if ($agentHost -eq 'Cli' -and $looksQualified) {
        $detail += " CLI-hosted agents take a bare slug, never a qualified 'Model Name (vendor)'."
    }
    elseif ($agentHost -eq 'VSCode' -and -not $looksQualified) {
        $detail += " VS Code-hosted agents take the qualified 'Model Name (vendor)' form."
    }
    $violations.Add($detail)
}

# The models dispatched by `/dr` and the shared fallback are named in the dispatch guide, not in
# agent frontmatter. The concern agents are deliberately model-agnostic.
$guideFiles = @(
    Get-ChildItem -LiteralPath $repoRootPath -Recurse -File -Force -Filter 'dispatch-guide.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skipRegex } |
        Sort-Object FullName
)

foreach ($file in $guideFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName)

    foreach ($pattern in $deniedPatterns) {
        if ($content -match $pattern) {
            $violations.Add("$relative references a denied model/vendor (pattern '$pattern').")
        }
    }

    $section = [regex]::Match($content, '(?ms)^##\s+[\d.]*\s*Model roster[^\n]*\n(?<body>.*?)(?=^##\s|\z)')
    if (-not $section.Success) {
        $violations.Add("$relative has no '## Model roster' section, so its dispatch roster cannot be validated.")
        continue
    }

    $rows = [regex]::Matches($section.Groups['body'].Value, '(?m)^\|\s*(?<role>[^|`]+?)\s*\|\s*`(?<model>[^`]+)`\s*\|')
    if ($rows.Count -eq 0) {
        $violations.Add("$relative declares no dispatch roster rows under '## Model roster'.")
        continue
    }

    $fallbackAlias = [string]$allowlist.Fallback['VSCode']
    $sawFallback = $false
    foreach ($row in $rows) {
        $role = $row.Groups['role'].Value
        $model = $row.Groups['model'].Value

        if (-not $aliases.ContainsKey($model)) {
            $violations.Add("$relative dispatches model alias '$model' (row '$role'), which is not in the alias map.")
        }

        if ($role -match '(?i)fallback') {
            $sawFallback = $true
            if ($model -ne $fallbackAlias) {
                $violations.Add("$relative names Pro-tier fallback '$model' but the allowlist declares '$fallbackAlias'.")
            }
        }
    }

    if (-not $sawFallback) {
        $violations.Add("$relative names no Pro-tier fallback row, so the degradation path is undeclared.")
    }
}

$preferenceFiles = @(
    Get-ChildItem -LiteralPath $repoRootPath -Recurse -File -Force -Filter 'model-preferences.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skipRegex } |
        Sort-Object FullName
)

foreach ($file in $preferenceFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName)

    foreach ($pattern in $deniedPatterns) {
        if ($content -match $pattern) {
            $violations.Add("$relative references a denied model/vendor (pattern '$pattern').")
        }
    }

    $section = [regex]::Match($content, '(?ms)^##\s+Models\s*\n(?<body>.*?)(?=^##\s|\z)')
    if (-not $section.Success) {
        $violations.Add("$relative has no '## Models' section, so its model preferences cannot be validated.")
        continue
    }

    $rows = [regex]::Matches($section.Groups['body'].Value, '(?m)^\|\s*(?<role>Primary|Secondary|Backup)\s*\|\s*`(?<model>[^`]+)`\s*\|')
    $roles = @{}
    foreach ($row in $rows) {
        $role = $row.Groups['role'].Value
        $model = $row.Groups['model'].Value
        $roles[$role] = $model
        if (-not $aliases.ContainsKey($model)) {
            $violations.Add("$relative selects model alias '$model' (role '$role'), which is not in the alias map.")
        }
    }

    foreach ($requiredRole in @('Primary', 'Secondary', 'Backup')) {
        if (-not $roles.ContainsKey($requiredRole)) {
            $violations.Add("$relative has no '$requiredRole' model row.")
        }
    }

    if ($roles.ContainsKey('Backup') -and $roles['Backup'] -ne [string]$allowlist.Fallback['VSCode']) {
        $violations.Add("$relative names backup '$($roles['Backup'])' but the allowlist declares '$($allowlist.Fallback['VSCode'])'.")
    }
}

$configFiles = @(
    Get-ChildItem -LiteralPath $repoRootPath -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $configNames -contains $_.Name -and $_.FullName -notmatch $skipRegex } |
        Sort-Object FullName
)
foreach ($file in $configFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')

    try {
        $config = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        $violations.Add("$relative is not valid JSON - $($_.Exception.Message)")
        continue
    }

    if ($null -eq $config -or -not $config.ContainsKey('model')) { continue }

    $model = [string]$config['model']
    if (-not $aliases.ContainsKey($model)) {
        $violations.Add("$relative declares model alias '$model', which is not in the alias map.")
    }
    foreach ($pattern in $deniedPatterns) {
        if ($model -match $pattern) {
            $violations.Add("$relative declares a denied model/vendor '$model' (pattern '$pattern').")
        }
    }
}

if ($violations.Count -gt 0) {
    foreach ($violation in $violations) {
        Write-Host "ERROR: $violation" -ForegroundColor Red
    }
    if ($PassThru) { $violations }
    exit 1
}

Write-Host "Test-ModelAllowlist passed: $($agentFiles.Count) agent file(s), $($guideFiles.Count) dispatch guide(s), $($preferenceFiles.Count) model preference file(s), $($configFiles.Count) autopilot config(s)." -ForegroundColor Green
if ($PassThru) { @() }
exit 0
