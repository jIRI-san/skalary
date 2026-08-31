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

$selection = Invoke-EpicAutopilotHostLoop @parameters
if ($selection.State) {
    return ($selection.State | ConvertTo-Json -Compress)
}

Write-Output "Epic '$Epic' has no eligible NextChild; no state was written."
