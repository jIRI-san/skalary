#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)]
    [ValidateSet('Inspect', 'Snapshot', 'Apply', 'Rollback')]
    [string]$Mode,
    [string]$Observation,
    [string]$Receipt,
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$PinnedBaseOid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
return Invoke-SiRepair -RepoRoot $RepoRoot -Mode $Mode -PinnedBaseOid $PinnedBaseOid `
    -Observation $Observation -Receipt $Receipt
