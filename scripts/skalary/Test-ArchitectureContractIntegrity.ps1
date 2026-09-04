#requires -Version 7.0
<#
.SYNOPSIS
Runs the architecture-notes write gate over every repository architecture contract.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$contractRoot = Join-Path $root 'schemas/architecture'
$contractGate = Join-Path $root 'plugins/architecture-notes/scripts/Test-ArchContract.ps1'
if (-not (Test-Path -LiteralPath $contractGate -PathType Leaf)) {
    throw "Architecture contract write gate is missing: $contractGate"
}

$contractFiles = @(
    Get-ChildItem -LiteralPath $contractRoot -File -Filter '*.json' |
        Sort-Object Name
)
$errors = [System.Collections.Generic.List[string]]::new()
if ($contractFiles.Count -eq 0) {
    $errors.Add('No architecture contracts were found; the integrity sweep asserted nothing.')
}

foreach ($contractFile in $contractFiles) {
    try {
        $contractResult = & $contractGate -ContractPath $contractFile.FullName -NoExit
        if (-not $contractResult.Valid) {
            $errors.Add("$($contractFile.FullName): $($contractResult.Errors -join '; ')")
        }
    }
    catch {
        $errors.Add("$($contractFile.FullName): $($_.Exception.Message)")
    }
}

$result = [pscustomobject]@{
    Valid  = $errors.Count -eq 0
    Count  = $contractFiles.Count
    Errors = @($errors)
}
$result

if (-not $result.Valid -and -not $NoExit) {
    foreach ($message in $result.Errors) {
        [Console]::Error.WriteLine($message)
    }
    exit 1
}
