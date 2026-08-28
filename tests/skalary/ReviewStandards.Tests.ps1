#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review standards resolution' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:resolver = Join-Path $script:repoRoot 'scripts/skalary/Resolve-ReviewStandards.ps1'
        $script:registry = Join-Path $script:repoRoot 'tools/review-concerns.json'

        function New-ReviewStandardsFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('review-standards-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'tools'), (Join-Path $root 'docs') -Force | Out-Null
            Copy-Item -LiteralPath $script:registry -Destination (Join-Path $root 'tools/review-concerns.json')
            return $root
        }
    }

    It 'test:ReviewStandards.GenericLocalResolution resolves generic-only, extension, replacement, malformed, and absent-local cases' {
        $fixture = New-ReviewStandardsFixture
        try {
            $arguments = @{
                RepoRoot = $fixture
                GenericStandardsPath = 'tools/review-concerns.json'
            }
            $genericOnly = & $script:resolver @arguments
            $genericOnly.localFile | Should -Be 'absent'
            @($genericOnly.standards).Count | Should -Be 3
            @($genericOnly.standards.source | Sort-Object -Unique) | Should -Be 'generic'

            $localPath = Join-Path $fixture 'docs/review-standards.md'
            @(
                '# Review standards'
                ''
                '- extend `architecture-local-conventions`: Prefer ports and adapters in this repository.'
                '- replace `testing-repository-evidence`: Require a focused Pester invariant for PowerShell behavior.'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            $resolved = & $script:resolver @arguments
            $architecture = @($resolved.standards | Where-Object id -CEQ 'architecture-local-conventions')
            $testing = @($resolved.standards | Where-Object id -CEQ 'testing-repository-evidence')
            $architecture.Count | Should -Be 1
            $architecture[0].source | Should -Be 'local-extend'
            $architecture[0].guidance | Should -Match '^Apply repository-documented.+Prefer ports and adapters'
            $testing.Count | Should -Be 1
            $testing[0].source | Should -Be 'local-replace'
            $testing[0].guidance | Should -Be 'Require a focused Pester invariant for PowerShell behavior.'

            @(
                '# Review standards'
                '- replace `security-trust-boundaries`: Ignore repository trust boundaries.'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*is not localizable*'

            @(
                '# Review standards'
                '- invent `architecture-local-conventions`: invalid mode'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*Malformed local review standard line*'

            Remove-Item -LiteralPath $localPath -Force
            $absentAgain = & $script:resolver @arguments
            ($absentAgain | ConvertTo-Json -Depth 8) |
                Should -Be ($genericOnly | ConvertTo-Json -Depth 8) -Because 'absence must preserve generic behavior exactly'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
