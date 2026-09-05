#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Self-improvement recent-learning boundary' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:sourceSkill = Join-Path $script:repoRoot 'plugins/self-improvement/skills/si/SKILL.md'
        $script:installedSkill = Join-Path $script:repoRoot '.github/skills/si/SKILL.md'
        $script:sourceGuide = Join-Path $script:repoRoot 'plugins/self-improvement/skills/si/assets/harvest-guide.md'
        $script:installedGuide = Join-Path $script:repoRoot '.github/skills/si/assets/harvest-guide.md'
    }

    It 'reads only the bounded recent-learning handoff' {
        foreach ($path in @($script:sourceSkill, $script:installedSkill, $script:sourceGuide, $script:installedGuide)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match 'docs/feedback/recent-learning\.md'
        }
    }

    It 'defines closed states and visible invalid-input refusal' {
        foreach ($path in @($script:sourceSkill, $script:installedSkill)) {
            $text = Get-Content -LiteralPath $path -Raw
            foreach ($state in @('missing', 'empty', 'valid', 'stale')) {
                $text | Should -Match $state
            }
            $text | Should -Match '(?i)must stop'
        }
        foreach ($path in @($script:sourceGuide, $script:installedGuide)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match '(?is)malformed.*fails visibly'
            $text | Should -Match '(?i)secret-containing'
        }
    }

    It 'keeps collision-safe untrusted treatment at the SI read boundary' {
        foreach ($path in @($script:sourceSkill, $script:installedSkill, $script:sourceGuide, $script:installedGuide)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match '(?i)collision-safe|fresh delimiter'
            $text | Should -Match '(?i)never execute|never.*follow'
            $text | Should -Match '(?i)data'
        }
    }

    It 'ships the reader closure without claiming the producer scaffold' {
        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 50
        $destinations = @($manifest.files | ForEach-Object { [string]$_.dest })
        $destinations | Should -Contain 'skills/si/scripts/Get-SiHarvest.ps1'
        $destinations | Should -Contain 'skills/si/scripts/SecretGuard.psm1'
        @($manifest.scaffolds | ForEach-Object { [string]$_.path }) |
            Should -Not -Contain 'docs/feedback/recent-learning.md'
    }

    It 'preserves existing proposal lifecycle state for child 3a4498' {
        foreach ($required in @(
                'skills/si/scripts/Invoke-SiLifecycle.ps1',
                'skills/si/scripts/Invoke-SiProposalSync.ps1',
                'skills/si/scripts/Complete-SiProposal.ps1'
            )) {
            $manifest = Get-Content -LiteralPath (
                Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
            ) -Raw | ConvertFrom-Json -Depth 50
            @($manifest.files.dest) | Should -Contain $required
        }
    }

    It 'keeps source and installed SI boundary files byte-identical' {
        foreach ($pair in @(
                @($script:sourceSkill, $script:installedSkill),
                @($script:sourceGuide, $script:installedGuide),
                @(
                    (Join-Path $script:repoRoot 'plugins/self-improvement/scripts/Get-SiHarvest.ps1'),
                    (Join-Path $script:repoRoot '.github/skills/si/scripts/Get-SiHarvest.ps1')
                )
            )) {
            (Get-FileHash -LiteralPath $pair[0]).Hash |
                Should -Be (Get-FileHash -LiteralPath $pair[1]).Hash
        }
    }
}
