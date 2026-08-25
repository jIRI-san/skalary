#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$Receipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force
$stateContract = Get-SiStateContract

function Resolve-ReceiptPhysicalPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $root
    foreach ($segment in @($fullPath.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $segment
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $target = $item.ResolveLinkTarget($true)
                if ($null -eq $target) { throw "Cannot resolve receipt link '$candidate'." }
                $current = [System.IO.Path]::GetFullPath($target.FullName)
                continue
            }
        }
        $current = [System.IO.Path]::GetFullPath($candidate)
    }
    return $current
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
$path = Resolve-SiStatePath -RepoRoot $root `
    -Segments (@($stateContract.Topology.ResolverReceiptSegments) + "$Receipt.json")
$physicalRoot = Resolve-ReceiptPhysicalPath -Path $root
$physicalPath = Resolve-ReceiptPhysicalPath -Path $path
$prefix = $physicalRoot.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )) + [System.IO.Path]::DirectorySeparatorChar
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
if (-not $physicalPath.StartsWith($prefix, $comparison)) {
    throw "Resolver receipt '$Receipt' escapes the physical repository root."
}
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Resolver receipt '$Receipt' not found."
}
$bytes = [System.IO.File]::ReadAllBytes($path)
if ($bytes.Length -gt $stateContract.Limits.RunBytes) {
    throw "Resolver receipt '$Receipt' exceeds its byte limit."
}
try {
    $json = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $envelope = $json | ConvertFrom-Json -Depth 100
}
catch {
    throw "Resolver receipt '$Receipt' is not valid UTF-8 JSON: $($_.Exception.Message)"
}
$schemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../schemas/resolver-receipt.schema.json'))
$errors = @()
if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorVariable errors)) {
    throw "Resolver receipt '$Receipt' failed closed-schema validation."
}
$candidateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($candidateId in @($envelope.payload.candidates)) {
    if (-not $candidateIds.Add([string]$candidateId)) {
        throw "Resolver receipt '$Receipt' contains duplicate candidates."
    }
}
$expected = Get-SiResolverReceiptId -Payload $envelope.payload
if ($expected -ne $Receipt -or $envelope.receiptId -ne $Receipt) {
    throw "Resolver receipt '$Receipt' failed its JCS content-address check."
}
return [pscustomobject][ordered]@{
    Status    = 'complete'
    ReceiptId = $Receipt
    Path      = $path
    Payload   = $envelope.payload
}
