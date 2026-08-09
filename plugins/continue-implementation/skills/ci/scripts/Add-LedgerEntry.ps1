#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('security', 'performance', 'error-handling', 'consistency', 'plan-structure', 'testing', 'observability')]
    [string]$Category,

    [Parameter(Mandatory)]
    [ValidatePattern('^(\d{4}-\d{2}-\d{2}|[0-9a-f]{4,6}|\d{3})$')]
    [string]$Plan,

    [Parameter(Mandatory)]
    [ValidateSet('cip', 'dr', 'cr', 'code-review', 'ci', 'autopilot')]
    [string]$Src,

    [Parameter(Mandatory)]
    [ValidateSet('Critical', 'High', 'Med', 'Low')]
    [string]$Severity,

    [Parameter(Mandatory)]
    [string]$Entry,

    [string[]]$Tags = @(),
    [string]$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LedgerStore.psm1') -Force

$result = Invoke-LedgerScalar -Category $Category -Plan $Plan -Src $Src -Severity $Severity `
    -Entry $Entry -Tags $Tags -Date $Date -RepoRoot $RepoRoot

if ($result.Status -eq 'capacity-blocked') {
    Write-Error "Ledger write blocked: $($result.Reason)"
    exit 4
}
if ($result.Status -ne 'complete') {
    Write-Error "Ledger write failed with status '$($result.Status)'."
    exit 5
}
if ($result.Added -eq 0) {
    Write-Host "Skipped duplicate ledger entry for category '$Category' (idempotence-key match)." -ForegroundColor Yellow
    exit 0
}

$line = @($result.Results | Where-Object Added)[0].Line
Write-Host "Added ledger entry to '$Category': $line" -ForegroundColor Green
exit 0
