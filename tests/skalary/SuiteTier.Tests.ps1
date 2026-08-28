#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite tiers' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:manifestPath = Join-Path $script:repoRoot 'tools/suite-tier.psd1'
        $script:manifest = Import-PowerShellDataFile -LiteralPath $script:manifestPath
    }

    It 'test:SuiteTier.PartitionContract keeps the manifest valid, disjoint, and complete by complement' {
        [string]$script:manifest.Schema | Should -Be 'skalary/suite-tier@1'
        [double]$script:manifest.FastFocusedHardCeilingSeconds | Should -Be 60
        [double]$script:manifest.SlowHardCeilingSeconds | Should -BeGreaterThan 0
        [double]$script:manifest.CiSetupAllowanceSeconds | Should -BeGreaterThan 0
        [string]$script:manifest.SlowMeasurementRecord | Should -Be 'tools/suite-slow-runtime.json'

        $slow = @($script:manifest.SlowFiles)
        $dedicated = @($script:manifest.DedicatedFiles)
        $slow.Count | Should -BeGreaterThan 0
        $dedicated |
            Should -Be @('tests/skalary/ReviewConsumerInstall.Tests.ps1') -Because 'every dedicated exclusion needs an explicit blocking owner; this schema has exactly one'

        $declared = @($slow) + @($dedicated)
        @($declared | Sort-Object -Unique).Count |
            Should -Be $declared.Count -Because 'slow and dedicated ownership must be disjoint'

        foreach ($relativePath in $declared) {
            $relativePath | Should -Match '^tests/.+\.Tests\.ps1$'
            Test-Path -LiteralPath (Join-Path $script:repoRoot $relativePath) -PathType Leaf |
                Should -BeTrue -Because "tier path '$relativePath' must exist"
        }

        $all = @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'tests') -Recurse -File -Filter '*.Tests.ps1' |
                ForEach-Object { [System.IO.Path]::GetRelativePath($script:repoRoot, $_.FullName).Replace('\', '/') })
        $fast = @($all | Where-Object { $_ -notin $slow -and $_ -notin $dedicated })

        $fast.Count | Should -BeGreaterThan 0
        @($fast + $slow + $dedicated | Sort-Object -Unique) |
            Should -Be @($all | Sort-Object) -Because 'Fast is the complete derived complement of Slow and dedicated files'
    }
}