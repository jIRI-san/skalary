#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Skalary configuration catalog and read-only adapter' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/skalary-config'
        $script:catalog = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/skalary-config/assets/catalog.md') -Raw
        $script:skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/skalary-config/SKILL.md') -Raw
        $script:reader = Join-Path $script:pluginRoot 'skills/skalary-config/scripts/Read-SkalaryConfig.ps1'
    }

    It 'test:SkalaryConfig.Catalog provides every accepted category and catalog boundary' {
        Test-Path -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -PathType Leaf | Should -BeTrue
        foreach ($category in @(
                'Autopilot', 'Models and reviews', 'Local review standards', 'Terminal approvals',
                'Evals', 'Design and architecture', 'Plugin distribution', 'Repository and toolchain'
            )) {
            $catalog | Should -Match ([regex]::Escape($category))
        }
        $catalog | Should -Match 'Canonical and default paths'
        $catalog | Should -Match 'Generated paths and precedence'
        $catalog | Should -Match 'Installed consumer'
        $catalog | Should -Match 'not executable configuration policy'
    }

    It 'test:SkalaryConfig.ReadOnly discovers source state without exposing credential values' {
        $result = & $script:reader -Action show -Category autopilot -RepoRoot $script:repoRoot | ConvertFrom-Json
        $result.Layout | Should -Be 'source'
        $result.Precedence | Should -Match 'overrides'
        $result.SourceDigest | Should -Match '^[a-f0-9]{64}$'
        $result | ConvertTo-Json -Depth 5 | Should -Not -Match '"pat"'
    }

    It 'test:SkalaryConfig.Preview is category-bounded and detects changed canonical inputs' {
        $preview = & $script:reader -Action preview -Category models-reviews -RepoRoot $script:repoRoot | ConvertFrom-Json
        $preview.Proposal | Should -Match 'No requested changes'
        $preview.Redaction | Should -Match 'never read'

        {
            & $script:reader -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
                -ExpectedDigest ('0' * 64) | Out-Null
        } | Should -Throw '*SourceChanged*'
    }

    It 'reports advanced categories as unavailable in an installed consumer layout' {
        $consumer = Join-Path $TestDrive 'consumer'
        New-Item -ItemType Directory -Path $consumer -Force | Out-Null
        $result = & $script:reader -Action validate -Category models-reviews -RepoRoot $consumer | ConvertFrom-Json
        $result.Layout | Should -Be 'installed-consumer'
        $result.Validation | Should -Match 'requires maintainer source'
    }
}
