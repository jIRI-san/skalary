#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][string]$RepoId,
    [Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-f]{6}|[0-9]{3})$')][string]$PlanId,
    [Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')][string]$SourceCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force

$result = Add-SiDue -RepoRoot $RepoRoot -RepoId $RepoId -PlanId $PlanId -SourceCommit $SourceCommit
if ($result.Status -ne 'complete') {
    Write-Error "Enqueue-SiDue failed with status '$($result.Status)'."
}
return $result
