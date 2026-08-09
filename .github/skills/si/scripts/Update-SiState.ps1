#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)]
    [ValidateSet('Begin', 'RecordRanking', 'RecordChoices', 'ProposalPending', 'Complete')]
    [string]$Operation,
    [Parameter(Mandatory)][string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Assert-SiStateImplementationAvailable -CommandName $MyInvocation.MyCommand.Name
