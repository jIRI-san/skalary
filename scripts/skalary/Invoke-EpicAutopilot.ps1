#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Epic,

    [string]$Target = 'HEAD',

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'EpicAutopilot.psm1') -Force

$parameters = @{
    Epic   = $Epic
    Target = $Target
}
if ($RepoRoot) {
    $parameters.RepoRoot = $RepoRoot
}
$result = Invoke-EpicAutopilotHostLoop @parameters
if ($result.State) {
    Write-Output ($result.State | ConvertTo-Json -Compress)
    if ($result.Failed) {
        Write-Error $result.Message -ErrorAction Continue
        exit 1
    }
    if ($result.State.outcome -ceq 'awaiting-merge') {
        Write-Output "Child '$($result.State.currentChild)' passed launcher close proof and is awaiting operator merge."
        exit 0
    }
    if ($result.State.outcome.StartsWith('exit:', [System.StringComparison]::Ordinal)) {
        if ([int]$result.ExitCode -eq 0) {
            Write-Output "Child '$($result.State.currentChild)' has legacy exit:0 close proof and is awaiting operator merge."
        }
        exit ([int]$result.ExitCode)
    }
}

Write-Output "Epic '$Epic' has no eligible NextChild; no state was written."
