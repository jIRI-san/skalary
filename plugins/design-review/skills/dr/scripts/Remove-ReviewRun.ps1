#requires -Version 7.0
<#
.SYNOPSIS
    Removes a published generic review run after verifying it, once its summary has been delivered.
.DESCRIPTION
    Plan c21cdc D14/D20/REQ-10, step 1.2. Plan-associated runs live under a plan's committed
    `assets/reviews/<run-id>/` and are removed through ordinary version control, never by this
    script. Generic runs live under the gitignored `.github/.skalary/review-runs/<run-id>/` store and
    are transient: once the caller has read and delivered the verified summary, this script removes
    the whole run directory.

    It is deliberately narrow: it resolves the generic store from this script's installed location,
    refuses any id that is not a lowercase UUID, refuses to remove anything outside that store, and
    (by default) verifies the run's manifest before deleting so a corrupt or partial run is a loud
    failure rather than a silent discard. Pass `-Force` to remove an unpublished (frozen-only) run
    directory during cleanup of an abandoned run.
.EXAMPLE
    & Remove-ReviewRun.ps1 -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RunId,

    # Remove without requiring a valid published manifest — used to clear an abandoned frozen run.
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-EncodedStderr {
    param([Parameter(Mandatory)][string]$Text)
    $flat = ([string]$Text) -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]', ' '
    $bytes = $utf8.GetBytes($flat + [Environment]::NewLine)
    if ($bytes.Length -gt 16384) { $bytes = $bytes[0..16383] }
    $stderr = [Console]::OpenStandardError()
    $stderr.Write($bytes, 0, $bytes.Length)
    $stderr.Flush()
}

try {
    Import-Module (Join-Path $PSScriptRoot 'ReviewRun.psm1') -Force -DisableNameChecking
}
catch {
    Write-EncodedStderr -Text "Cannot load the review-run engine: $($_.Exception.Message)"
    exit 4
}

try {
    $removed = Remove-ReviewRunDirectory -RunId $RunId -RequirePublished:(-not $Force)
    $bytes = $utf8.GetBytes("removed generic review run $removed`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit 0
}
catch {
    Write-EncodedStderr -Text "Cannot remove run '$RunId': $($_.Exception.Message)"
    exit 2
}
