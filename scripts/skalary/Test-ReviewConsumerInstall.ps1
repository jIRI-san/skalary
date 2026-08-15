#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$TestResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testPath = Join-Path $RepoRoot 'tests/skalary/ReviewConsumerInstall.Tests.ps1'
if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
    Write-Error "Review consumer install test not found: $testPath"
    exit 3
}

$pester = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 } |
        Sort-Object Version -Descending | Select-Object -First 1)
if ($pester.Count -ne 1) {
    Write-Error 'Pester 5 or newer is required for the review consumer install gate.'
    exit 2
}

Import-Module Pester -MinimumVersion $pester[0].Version -ErrorAction Stop
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testPath
$configuration.Run.PassThru = $true
$configuration.Run.Exit = $false
$configuration.TestResult.Enabled = [bool]$TestResultPath
if ($TestResultPath) {
    $parent = Split-Path -Parent $TestResultPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $configuration.TestResult.OutputPath = $TestResultPath
}

$result = Invoke-Pester -Configuration $configuration
if ($null -eq $result -or [int]$result.TotalCount -le 0) { exit 3 }
if ([int]$result.FailedContainersCount -gt 0) { exit 4 }
if ([int]$result.FailedCount -gt 0 -or [int]$result.FailedBlocksCount -gt 0) { exit 1 }
exit 0