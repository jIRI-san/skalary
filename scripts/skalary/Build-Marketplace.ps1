#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$MarketplaceName = 'skalary',

    [string]$Owner = 'jIRI-san'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

# REQ-7/D8: marketplace.json is compared byte for byte by the drift gate below, so its
# ordering is fixed by this comparer rather than by the building host's culture.
$script:CatalogComparer = [System.StringComparer]::Ordinal

$repoRootPath = Resolve-RepoRoot -StartPath $RepoRoot
$pluginsRoot = Join-Path $repoRootPath 'plugins'
$marketplacePath = Join-Path $repoRootPath '.github/plugin/marketplace.json'

if (-not (Test-Path -LiteralPath $pluginsRoot -PathType Container)) {
    throw "Plugins directory not found: $pluginsRoot"
}

$manifestPaths = @(
    Sort-Ordinal `
        -InputObject @(Get-ChildItem -LiteralPath $pluginsRoot -Recurse -File -Filter 'plugin.json') `
        -Property 'FullName' `
        -Comparer $script:CatalogComparer
)
if ($manifestPaths.Count -eq 0) {
    throw "No plugin manifests found under '$pluginsRoot'."
}

$pluginEntries = @()
foreach ($manifestPath in $manifestPaths) {
    $manifest = Read-JsonFile -Path $manifestPath.FullName
    $pluginName = [string]$manifest.name

    # Copilot CLI reads the plugin's own plugin.json from `source`; that shared
    # manifest carries skalary-specific fields, so mark the entry strict:false to
    # keep native install/validation relaxed (proven acceptable by the 3.1 spike).
    $pluginEntries += [pscustomobject]([ordered]@{
            name = $pluginName
            source = "plugins/$pluginName"
            description = [string]$manifest.description
            version = [string]$manifest.version
            license = [string]$manifest.license
            tags = @(Sort-Ordinal -InputObject @($manifest.tags) -Comparer $script:CatalogComparer)
            strict = $false
        })
}
$pluginEntries = @(Sort-Ordinal -InputObject $pluginEntries -Property 'name' -Comparer $script:CatalogComparer)

$marketplace = [pscustomobject]@{
    name = $MarketplaceName
    owner = [pscustomobject]@{ name = $Owner }
    metadata = [pscustomobject]@{
        description = 'skalary plugins for GitHub Copilot CLI. Add with `copilot plugin marketplace add jIRI-san/skalary`, then `copilot plugin install <name>@skalary`.'
    }
    plugins = $pluginEntries
}

# Drift check: compare the semantic content (formatting/newline agnostic), never write.
if ($WhatIfPreference) {
    if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
        throw "Marketplace drift: '.github/plugin/marketplace.json' is missing. Run scripts/skalary/Build-Marketplace.ps1."
    }
    $existing = Read-JsonFile -Path $marketplacePath
    $existingComparable = ConvertTo-SortedObject -InputObject $existing | ConvertTo-Json -Depth 100 -Compress
    $expectedComparable = ConvertTo-SortedObject -InputObject $marketplace | ConvertTo-Json -Depth 100 -Compress
    if (-not [string]::Equals($existingComparable, $expectedComparable, [System.StringComparison]::Ordinal)) {
        throw 'Marketplace drift: .github/plugin/marketplace.json differs from plugins/ sources. Run scripts/skalary/Build-Marketplace.ps1.'
    }
    Write-Host 'Marketplace up to date (no drift).'
    return
}

$marketplaceDir = Split-Path -Parent $marketplacePath
if (-not (Test-Path -LiteralPath $marketplaceDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $marketplaceDir -Force)
}

Write-JsonFileStable -Path $marketplacePath -InputObject $marketplace
Write-Host "Generated marketplace at '$marketplacePath' with $($pluginEntries.Count) plugin(s)."
