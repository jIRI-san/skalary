#requires -Version 7.0
<#
.SYNOPSIS
    Freezes or publishes one validated review run.
.DESCRIPTION
    Fixed installed CLI for the skalary/review-run@1 contract. The caller chooses only a lowercase
    UUID and an optional plan directory; the bundled ReviewRun module derives every schema, repository,
    input, and output path. Reviewer-authored text enters only through the fixed JSON handshakes.

    The synchronizer follows the literal sidecar references below so every installed review skill has
    the same writer, reader, cleanup helper, module, and schemas:
      Join-Path $PSScriptRoot 'Get-ReviewRun.ps1'
      Join-Path $PSScriptRoot 'Remove-ReviewRun.ps1'
.EXAMPLE
    & Build-ReviewReport.ps1 -Mode Freeze -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35
.EXAMPLE
    & Build-ReviewReport.ps1 -Mode Publish -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35 -PlanDir docs/implementation-plans/2026-08-02-c21cdc-review-report-as-data
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Freeze', 'Publish')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$RunId,

    [string]$PlanDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'ReviewRun.psm1'

try {
    Import-Module $modulePath -Force -DisableNameChecking
    $result = if ($Mode -eq 'Freeze') {
        Invoke-ReviewFreeze -RunId $RunId -PlanDir $PlanDir
    }
    else {
        Invoke-ReviewPublish -RunId $RunId -PlanDir $PlanDir
    }
    $exit = Write-ReviewTerminalStatus -Mode ($Mode.ToLowerInvariant()) -ExitCode $result.ExitCode `
        -State $result.State -Message $result.Message -RunId $result.RunId -Diagnostic $result.Diagnostics
    exit $exit
}
catch {
    $failure = ([string]$_.Exception.Message) -replace '\s+', ' '
    if ($failure.Length -gt 512) { $failure = $failure.Substring(0, 512) }
    $status = [ordered]@{
        diagnostics = @($failure)
        exitCode    = 4
        message     = "$Mode failed unexpectedly before it could report a bounded status."
        mode        = $Mode.ToLowerInvariant()
    }
    if ($RunId -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        $status['runId'] = $RunId
    }
    else {
        $status['runIdRejected'] = $true
        $status['exitCode'] = 2
        $status['message'] = 'Run id must be a lowercase UUID.'
    }
    $status['schema'] = 'skalary/review-terminal-status@1'
    $status['state'] = $(if ($status['exitCode'] -eq 4) { 'failed' } else { 'invalid' })

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (ConvertTo-Json -InputObject $status -Depth 4 -Compress) + "`n"
    )
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit $status['exitCode']
}
