#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Epic,

    [string]$Target = 'HEAD',

    [string]$RepoRoot,

    [string]$StatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'EpicAutopilot.psm1') -Force

$parameters = @{
    Epic = $Epic
    Target = $Target
}
if ($RepoRoot) {
    $parameters.RepoRoot = $RepoRoot
}
if ($StatePath) {
    $parameters.StatePath = $StatePath
}

$result = Invoke-EpicAutopilotHostLoop @parameters
if ($result.State) {
    Write-Output ($result.State | ConvertTo-Json -Compress)
    if ($result.State.outcome -ceq 'invocation-failed') {
        Write-Error "Epic autopilot run '$($result.State.run)' has terminal outcome 'invocation-failed'."
        exit 1
    }
    if ($result.State.outcome.StartsWith('exit:', [System.StringComparison]::Ordinal)) {
        exit ([int]$result.ExitCode)
    }
}

Write-Output "Epic '$Epic' has no eligible NextChild; no state was written."
