#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [ValidateRange(1, 64)][int]$PageSize = 32,
    [string]$Cursor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force

$inspection = Get-SiStoreInspection -RepoRoot $RepoRoot
$manifest = $null
try {
    $manifest = Read-SiManifest -RepoRoot $RepoRoot -AllowAbsent
}
catch {
    if ($inspection.Status -notin @(
            'repairable-corrupt', 'migration-required', 'forward-readonly',
            'forward-blocked', 'capacity-blocked', 'apply-incomplete'
        )) {
        throw
    }
}
$pending = @(if ($null -ne $manifest) { $manifest.pending })
$inFlight = @(if ($null -ne $manifest) { $manifest.inFlight })
$recent = @(if ($null -ne $manifest) { $manifest.recentRuns })
$offset = 0
if ($Cursor) {
    if ($Cursor -notmatch '^[0-9]+$') { throw 'Cursor must be a non-negative integer offset.' }
    $offset = [int]$Cursor
}
$items = @($pending + $inFlight + $recent | Select-Object -Skip $offset -First $PageSize |
        ForEach-Object {
            [pscustomobject]@{
                dueId = [string]$_.dueId
                runId = if ($_.PSObject.Properties.Name -contains 'runId') { $_.runId } else { $null }
                status = [string]$_.status
            }
        })
$total = $pending.Count + $inFlight.Count + $recent.Count
return [pscustomobject]@{
    Status = $inspection.Status
    ExitCode = $inspection.ExitCode
    Generation = if ($null -eq $manifest) { $null } else { [int]$manifest.generation }
    PendingCount = $pending.Count
    InFlightCount = $inFlight.Count
    RecentCount = $recent.Count
    Items = $items
    NextCursor = if ($offset + $items.Count -lt $total) { [string]($offset + $items.Count) } else { $null }
}
