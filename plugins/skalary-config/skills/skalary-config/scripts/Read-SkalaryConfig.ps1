#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('show', 'validate', 'diff', 'preview')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidateSet(
        'autopilot',
        'models-reviews',
        'local-review-standards',
        'terminal-approvals',
        'evals',
        'design-architecture',
        'plugin-distribution',
        'repository-toolchain'
    )]
    [string]$Category,

    [string]$RepoRoot = (Get-Location).Path,
    [string]$ExpectedDigest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Repository root does not exist: $root"
}

$categories = @{
    autopilot = @{
        Canonical = @('.autopilot.json')
        Default = 'plugins/autopilot/.autopilot.json.example'
        Generated = @('.github/skills/autopilot/.autopilot.json.example')
        Precedence = 'Root .autopilot.json overrides the shipped example.'
        Sensitivity = 'Executable settings; credentials are availability-only.'
        Bootstrap = 'Selected-only from the shipped example.'
        Owner = 'Autopilot launcher'
        Validator = 'tests/autopilot/ModelConfiguration.Tests.ps1'
        Installed = $true
    }
    'models-reviews' = @{
        Canonical = @('tools/model-allowlist.psd1')
        Default = 'Committed aliases and role assignments.'
        Generated = @('plugins/*/skills/*/assets/model-aliases.psd1', '.github/skills/*/assets/model-aliases.psd1')
        Precedence = 'The allowlist is authoritative; bindings are generated.'
        Sensitivity = 'Advanced maintainer policy.'
        Bootstrap = 'None.'
        Owner = 'Sync-ModelBindings.ps1'
        Validator = 'Test-ModelAllowlist.ps1'
        Installed = $false
    }
    'local-review-standards' = @{
        Canonical = @('docs/review-standards.md')
        Default = 'No shipped local file; base CR/DR rules remain active.'
        Generated = @()
        Precedence = 'Optional local standards refine supplied base rules.'
        Sensitivity = 'Non-secret Markdown.'
        Bootstrap = 'Selected-only strict Markdown scaffold.'
        Owner = 'CR/DR standards resolver'
        Validator = 'tests/skalary/ReviewPolicy.Tests.ps1'
        Installed = $true
    }
    'terminal-approvals' = @{
        Canonical = @('.vscode/settings.json')
        Default = 'No Skalary default.'
        Generated = @()
        Precedence = 'VS Code workspace settings are authoritative.'
        Sensitivity = 'Read-only focused scripts only.'
        Bootstrap = 'No automatic bootstrap.'
        Owner = 'Set-ScriptApproval.ps1'
        Validator = 'tests/skalary/SetScriptApproval.Tests.ps1'
        Installed = $true
    }
    evals = @{
        Canonical = @('.eval.config.json', '.eval.config.json.example')
        Default = '.eval.config.json.example'
        Generated = @('plugins/*/evals/waza/eval.yaml')
        Precedence = 'Per-plugin Waza specs own model and judge values; local config owns credential targets.'
        Sensitivity = 'Never reads credential values.'
        Bootstrap = 'Selected-only copy of the example.'
        Owner = 'Resolve-EvalToken.ps1 and Invoke-WazaEvals.ps1'
        Validator = 'tests/evals/EvalTools.Tests.ps1'
        Installed = $false
    }
    'design-architecture' = @{
        Canonical = @('docs/design-notes', 'docs/architecture-notes')
        Default = 'Owning plugin templates.'
        Generated = @()
        Precedence = 'Existing notes and contracts retain ownership.'
        Sensitivity = 'Architecture lock promotion is excluded.'
        Bootstrap = 'Use the owning scaffold command.'
        Owner = 'design-notes and architecture-notes plugins'
        Validator = 'Test-ArchDocFreshness.ps1'
        Installed = $true
    }
    'plugin-distribution' = @{
        Canonical = @('plugins')
        Default = 'Plugin manifests.'
        Generated = @('registry.json', '.github/plugin/marketplace.json', '.github')
        Precedence = 'Plugin source is authoritative; catalogs and dogfood are generated.'
        Sensitivity = 'Advanced maintainer policy.'
        Bootstrap = 'None.'
        Owner = 'distribution generators'
        Validator = 'Test-Registry.ps1'
        Installed = $false
    }
    'repository-toolchain' = @{
        Canonical = @('package.json', 'tools/eval-tools.psd1', '.github/copilot-instructions.md')
        Default = 'Committed repository policy.'
        Generated = @('package-lock.json')
        Precedence = 'Owning package and tool policies are authoritative.'
        Sensitivity = 'Advanced and show-only by default.'
        Bootstrap = 'None.'
        Owner = 'package and tool owners'
        Validator = 'Owning focused validator'
        Installed = $false
    }
}

$entry = $categories[$Category]
$sourceLayout = (Test-Path -LiteralPath (Join-Path $root 'plugins') -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $root 'scripts/skalary') -PathType Container)
$layout = if ($sourceLayout) { 'source' } else { 'installed-consumer' }

$inputs = @()
foreach ($relative in $entry.Canonical) {
    $path = Join-Path $root $relative
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.LinkType) { throw "Refusing linked configuration path: $relative" }
        if ($item -is [System.IO.FileInfo]) { $inputs += $path }
    }
}
$digestInputs = @($inputs)
if ($Category -eq 'autopilot') {
    $defaultPath = Join-Path $root 'plugins/autopilot/.autopilot.json.example'
    if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
        $defaultItem = Get-Item -LiteralPath $defaultPath -Force
        if ($defaultItem.LinkType) { throw 'Refusing linked configuration path: plugins/autopilot/.autopilot.json.example' }
        $digestInputs += $defaultPath
    }
}
$hasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $digestMaterial = foreach ($path in @($digestInputs | Sort-Object -Unique)) {
        $relative = [System.IO.Path]::GetRelativePath($root, $path)
        "${relative}:$([Convert]::ToHexString($hasher.ComputeHash([System.IO.File]::ReadAllBytes($path))))"
    }
    if ($Category -eq 'models-reviews' -and $sourceLayout) {
        $headPolicy = & git -C $root rev-parse --verify 'HEAD:tools/model-allowlist.psd1' 2>$null
        if ($LASTEXITCODE -ne 0 -or $headPolicy -notmatch '^[0-9a-f]{40,64}$') {
            throw 'Cannot derive shipped model defaults from HEAD.'
        }
        $digestMaterial += "HEAD:tools/model-allowlist.psd1:$headPolicy"
    }
    $digest = [Convert]::ToHexString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes(($digestMaterial -join "`n")))).ToLowerInvariant()
}
finally {
    $hasher.Dispose()
}

if ($ExpectedDigest -and $ExpectedDigest -ne $digest) {
    throw "SourceChanged: $Category canonical inputs changed; preview again before Apply."
}

$result = [ordered]@{
    Action = $Action
    Category = $Category
    Layout = $layout
    CanonicalPaths = @($entry.Canonical)
    ExistingCanonicalPaths = @($inputs | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_) })
    Default = $entry.Default
    GeneratedPaths = @($entry.Generated)
    Precedence = $entry.Precedence
    Sensitivity = $entry.Sensitivity
    Bootstrap = $entry.Bootstrap
    Owner = $entry.Owner
    Validator = $entry.Validator
    InstalledConsumerAvailable = [bool]$entry.Installed
    SourceDigest = $digest
}

if ($Action -eq 'show' -and $Category -eq 'autopilot' -and $inputs) {
    try {
        $config = [System.IO.File]::ReadAllText($inputs[0]) | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw ".autopilot.json is malformed: $($_.Exception.Message)"
    }
    $safeKeys = @(
        'runtime', 'copilotAuth', 'gitProvider', 'gitAuth', 'model', 'context',
        'reasoningEffort', 'maxIterationsPerStep', 'build', 'test'
    )
    $result.EffectiveValues = [ordered]@{}
    foreach ($key in $safeKeys) {
        if ($config.ContainsKey($key)) { $result.EffectiveValues[$key] = $config[$key] }
    }
}
if ($Action -eq 'show' -and $Category -eq 'models-reviews' -and $sourceLayout -and $inputs) {
    try {
        $policy = Import-PowerShellDataFile -LiteralPath $inputs[0]
    }
    catch {
        throw "tools/model-allowlist.psd1 is malformed: $($_.Exception.Message)"
    }
    $result.EffectiveValues = [ordered]@{
        Aliases = $policy.Aliases
        Roles = $policy.Roles
        Fallback = $policy.Fallback
    }
}
if ($Action -eq 'diff') {
    $result.CurrentDiff = if ($sourceLayout -and $inputs) {
        (& git -C $root diff --no-ext-diff -- @($inputs | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_) })) -join "`n"
    }
    else {
        'No source Git diff is available for this category.'
    }
}
if ($Action -eq 'preview') {
    $result.Proposal = 'No requested changes. Mutation preview is read-only; phase 2 supplies closed edits.'
    $result.Redaction = 'Credential values are never read, rendered, or included in the digest.'
}
if ($Action -eq 'validate') {
    $result.Validation = if ($layout -eq 'installed-consumer' -and -not $entry.Installed) {
        'Unavailable: this advanced category requires maintainer source and tools.'
    }
    else {
        "Available focused validator: $($entry.Validator)"
    }
}

$result | ConvertTo-Json -Depth 5
