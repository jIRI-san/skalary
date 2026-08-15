#requires -Version 7.0
<#
.SYNOPSIS
Compares explicit baseline and candidate plugin-retirement files without reading Git.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [string]$CandidatePath,

    [string]$SchemaPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'schemas/registry/plugin-retirement.schema.json')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

function Read-RetirementCatalog {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Schema
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Plugin-retirement catalog not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not ($raw | Test-Json -SchemaFile $Schema -ErrorAction SilentlyContinue)) {
        throw "Plugin-retirement catalog is invalid: $Path"
    }
    return $raw | ConvertFrom-Json -Depth 100
}

function Get-RetirementMap {
    param([Parameter(Mandatory)]$Catalog)

    $map = @{}
    foreach ($record in @($Catalog.retiredPlugins)) {
        $name = [string]$record.name
        if ($map.ContainsKey($name)) {
            throw "Plugin-retirement catalog contains duplicate name '$name'."
        }
        $map[$name] = $record
    }
    return $map
}

$baseline = Read-RetirementCatalog -Path $BaselinePath -Schema $SchemaPath
$candidate = Read-RetirementCatalog -Path $CandidatePath -Schema $SchemaPath
$baselineByName = Get-RetirementMap -Catalog $baseline
$candidateByName = Get-RetirementMap -Catalog $candidate

foreach ($name in $baselineByName.Keys) {
    if (-not $candidateByName.ContainsKey($name)) {
        throw "Published plugin-retirement record '$name' was removed."
    }
    $before = ConvertTo-SortedObject -InputObject $baselineByName[$name] | ConvertTo-Json -Depth 100 -Compress
    $after = ConvertTo-SortedObject -InputObject $candidateByName[$name] | ConvertTo-Json -Depth 100 -Compress
    if (-not [string]::Equals($before, $after, [System.StringComparison]::Ordinal)) {
        throw "Published plugin-retirement record '$name' was changed."
    }
}

[pscustomobject]@{
    BaselineCount = $baselineByName.Count
    CandidateCount = $candidateByName.Count
    AddedCount = $candidateByName.Count - $baselineByName.Count
}
