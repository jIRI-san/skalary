#requires -Version 7.0
<#
.SYNOPSIS
Validates an architecture contract file against architecture-contract.schema.json.

.DESCRIPTION
The single mutation guard the architecture-notes skill calls after writing or editing a
contract. It resolves the contract schema (scaffolded copy first, shipped asset as fallback),
validates the contract JSON against it, and reports the outcome as an object:
{ Path, Valid, SchemaPath, Errors[] }. Exit code is 0 when valid, 1 otherwise, so it doubles as
a CLI gate.

It never mutates the contract; it only reports. Lock promotion (draft -> locked) is deliberately
NOT granted here — that is a human-commit-bound step enforced by the runner, not a self-service
schema check.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ContractPath,

    # Explicit schema path. Auto-resolved when omitted.
    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Contract file not found: $ContractPath"
}

if (-not $SchemaPath) {
    # 1) Prefer a scaffolded schema found by walking up from the contract toward the repo root.
    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $ContractPath).Path
    while ($dir) {
        $candidate = Join-Path $dir 'schemas/architecture-contract.schema.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $SchemaPath = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
        # Stop at the repo/worktree boundary so an unrelated ancestor schemas/ can't bind.
        if ((Test-Path -LiteralPath (Join-Path $dir '.git')) -or
            (Test-Path -LiteralPath (Join-Path $dir 'docs/architecture-notes'))) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

if (-not $SchemaPath) {
    # 2) Fall back to the shipped asset, across authored and installed layouts.
    $candidates = @(
        (Join-Path $PSScriptRoot '..' 'skills' 'architecture-notes' 'assets' 'schemas' 'architecture-contract.schema.json'),
        (Join-Path $PSScriptRoot '..' 'assets' 'schemas' 'architecture-contract.schema.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $SchemaPath = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
}

if (-not $SchemaPath -or -not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    throw "Could not locate architecture-contract.schema.json; pass -SchemaPath explicitly."
}

$raw = Get-Content -LiteralPath $ContractPath -Raw
$errors = [System.Collections.Generic.List[string]]::new()
$valid = $false

try {
    $valid = [bool]($raw | Test-Json -SchemaFile $SchemaPath -ErrorVariable jsonErrors -ErrorAction SilentlyContinue)
    if (-not $valid -and $jsonErrors) {
        foreach ($e in $jsonErrors) { $errors.Add([string]$e) }
    }
}
catch {
    $errors.Add($_.Exception.Message)
}

$result = [pscustomobject]@{
    Path       = (Resolve-Path -LiteralPath $ContractPath).Path
    Valid      = $valid
    SchemaPath = $SchemaPath
    Errors     = @($errors)
}

# Emit the object for in-process (& script) consumers, e.g. evals.
$result

if (-not $valid) {
    # `exit` tears down the runspace before the default formatter flushes buffered
    # pipeline output, so stdout can be empty on the CLI gate path. Write diagnostics
    # synchronously to stderr so the caller always receives the schema errors.
    [Console]::Error.WriteLine("Architecture contract invalid: $($result.Path)")
    foreach ($e in $result.Errors) { [Console]::Error.WriteLine("  - $e") }
    exit 1
}
