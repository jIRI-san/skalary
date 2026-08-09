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
Assert-SiStateImplementationAvailable -CommandName $MyInvocation.MyCommand.Name
