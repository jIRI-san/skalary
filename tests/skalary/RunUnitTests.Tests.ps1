#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'focused unit test runner' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'

        function New-RunnerFixture {
            $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('n'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tests') -Force)
            return $root
        }

        function Invoke-Runner {
            param([Parameter(Mandatory)][string[]]$Arguments)

            $output = & pwsh -NoProfile -File $script:runner @Arguments 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String)
            }
        }
    }

    It 'test:RunUnitTests.FocusedSelection runs only named files and rejects broad ambiguity' {
        $fixture = New-RunnerFixture
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Pass.Tests.ps1') -Value @'
Describe 'selected' { It 'passes' { $true | Should -BeTrue } }
'@
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Fail.Tests.ps1') -Value @'
Describe 'unselected' { It 'fails' { $false | Should -BeTrue } }
'@

        $selected = Invoke-Runner -Arguments @(
            '-RepoRoot', $fixture, '-TestPath', 'tests/Pass.Tests.ps1')
        $selected.ExitCode | Should -Be 0 -Because $selected.Output
        $selected.Output | Should -Match 'Unit tests: focused \(1 file\(s\)\)'
        $selected.Output | Should -Not -Match 'unselected'

        (Invoke-Runner -Arguments @('-RepoRoot', $fixture)).ExitCode | Should -Be 12
        (Invoke-Runner -Arguments @(
                '-RepoRoot', $fixture, '-TestPath', 'tests/Pass.Tests.ps1', '-FullRepository'
            )).ExitCode | Should -Be 12
    }

    It 'test:RunUnitTests.ZeroSelectionIsNotGreen rejects unmatched filters and unloadable files' {
        $fixture = New-RunnerFixture
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Pass.Tests.ps1') -Value @'
Describe 'selected' { It 'passes' { $true | Should -BeTrue } }
'@
        $none = Invoke-Runner -Arguments @(
            '-RepoRoot', $fixture,
            '-TestPath', 'tests/Pass.Tests.ps1',
            '-TestName', 'missing test')
        $none.ExitCode | Should -Be 3 -Because $none.Output
        $none.Output | Should -Match 'NoTestsDiscovered'

        Set-Content -LiteralPath (Join-Path $fixture 'tests/Broken.Tests.ps1') -Value 'this is not powershell {'
        $broken = Invoke-Runner -Arguments @(
            '-RepoRoot', $fixture, '-TestPath', 'tests/Broken.Tests.ps1')
        $broken.ExitCode | Should -Be 4 -Because $broken.Output
    }

    It 'test:RunUnitTests.EvidenceAndReport writes only explicitly requested confined outputs' {
        $fixture = New-RunnerFixture
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Evidence.Tests.ps1') -Value @'
Describe 'evidence' {
    It 'test:Runner.Sample passes' { $true | Should -BeTrue }
}
'@
        $evidencePath = 'output/evidence.json'
        $reportPath = 'output/report.xml'
        $run = Invoke-Runner -Arguments @(
            '-RepoRoot', $fixture,
            '-TestPath', 'tests/Evidence.Tests.ps1',
            '-EvidenceTestId', 'Runner.Sample',
            '-EvidenceResultPath', $evidencePath,
            '-TestResultPath', $reportPath)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        (Get-Content -LiteralPath (Join-Path $fixture $evidencePath) -Raw |
            ConvertFrom-Json).results[0].status | Should -Be 'passed'
        Test-Path -LiteralPath (Join-Path $fixture $reportPath) -PathType Leaf | Should -BeTrue
    }

    It 'test:RunUnitTests.EnvironmentLeak rejects a passing test that mutates process state' {
        $fixture = New-RunnerFixture
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Leak.Tests.ps1') -Value @'
Describe 'leak' {
    It 'changes the environment' {
        $env:SKALARY_TEST_LEAK = 'leaked'
        $true | Should -BeTrue
    }
}
'@
        $run = Invoke-Runner -Arguments @(
            '-RepoRoot', $fixture, '-TestPath', 'tests/Leak.Tests.ps1')
        $run.ExitCode | Should -Be 7 -Because $run.Output
        $run.Output | Should -Match 'EnvironmentLeaked'
    }
}
