#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][datetime]$BeforeUtc,
    [ValidateRange(1, 32)][int]$MaximumRuns = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Assert-SiStateImplementationAvailable -CommandName $MyInvocation.MyCommand.Name
