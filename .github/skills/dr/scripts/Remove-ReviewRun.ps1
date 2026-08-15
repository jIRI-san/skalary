#requires -Version 7.0
<#
.SYNOPSIS
    Removes a verified generic run or finalizes a plan run into compact durable evidence.
.DESCRIPTION
    Plan c21cdc D14/D20/REQ-10. Live plan runs under `assets/reviews/<run-id>/` are transient and
    gitignored. With `-PlanDir` and `-Verdict`, this script verifies the published bundle, writes a
    bounded `<run-id>.review.md` plus digest-bound `<run-id>.receipt.json` beside it, then removes the
    live directory. Generic runs under `.github/.skalary/review-runs/<run-id>/` are removed after
    verified delivery without writing a durable result.

    It is deliberately narrow: it resolves the generic store from this script's installed location,
    refuses any id that is not a lowercase UUID, refuses to remove anything outside that store, and
    (by default) verifies the run's manifest before deleting so a corrupt or partial run is a loud
    failure rather than a silent discard. Pass `-Force` to remove an unpublished (frozen-only) run
    directory during cleanup of an abandoned run.
.EXAMPLE
    & Remove-ReviewRun.ps1 -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35
.EXAMPLE
    & Remove-ReviewRun.ps1 -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35 -PlanDir docs/implementation-plans/example -Verdict blocked
#>
[CmdletBinding(DefaultParameterSetName = 'Generic')]
param(
    [Parameter(Mandatory)]
    [string]$RunId,

    [Parameter(Mandatory, ParameterSetName = 'Plan')]
    [string]$PlanDir,

    [Parameter(Mandatory, ParameterSetName = 'Plan')]
    [ValidateSet('approved', 'blocked')]
    [string]$Verdict,

    # Remove without requiring a valid published manifest — used to clear an abandoned frozen run.
    [Parameter(ParameterSetName = 'Generic')]
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
    $message = if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        $finalized = Finalize-ReviewPlanRun -RunId $RunId -PlanDir $PlanDir -Verdict $Verdict
        "finalized plan review run $($finalized.RunId) as $($finalized.Verdict); report=$($finalized.Report); receipt=$($finalized.Receipt)"
    }
    else {
        $removed = Remove-ReviewRunDirectory -RunId $RunId -RequirePublished:(-not $Force)
        "removed generic review run $removed"
    }
    $bytes = $utf8.GetBytes($message + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit 0
}
catch {
    Write-EncodedStderr -Text "Cannot remove run '$RunId': $($_.Exception.Message)"
    exit 2
}
