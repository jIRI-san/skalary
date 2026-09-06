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

    It 'test:RecentLearning.BoundedRead reads only the bounded recent-learning handoff' {
        foreach ($path in @($script:sourceSkill, $script:installedSkill, $script:sourceGuide, $script:installedGuide)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match 'docs/feedback/recent-learning\.md'
        }
    }

    It 'test:RecentLearning.InvalidInputRefusal defines closed states and visible invalid-input refusal' {
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

    It 'ships only the retained reader and guard closures' {
        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 50
        $destinations = @($manifest.files | ForEach-Object { [string]$_.dest })
        $destinations | Should -Contain 'skills/si/scripts/Get-SiHarvest.ps1'
        $destinations | Should -Contain 'skills/si/scripts/SecretGuard.psm1'
        $destinations | Should -Contain 'skills/si/scripts/Test-SiWriteScope.ps1'
        @($manifest.scaffolds | Where-Object { $null -ne $_ }).Count | Should -Be 0
    }

    It 'test:SelfImprovement.DirectSelection keeps selection informed, individual, and local' {
        foreach ($path in @($script:sourceSkill, $script:installedSkill)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match 'at most five'
            $text | Should -Match 'effort: 1-10'
            $text | Should -Match 'complexity: 1-10'
            $text | Should -Match 'individual choices'
            $text | Should -Match 'No selection means no mutation'
            $text | Should -Match 'current worktree'
            $text | Should -Not -Match '(?i)worktree/branch|draft PR|auto-merge'
        }
    }

    It 'test:SelfImprovement.VisibleFailure retains direct failure and diff behavior' {
        foreach ($path in @(
                'plugins/self-improvement/skills/si/assets/propose-guide.md',
                '.github/skills/si/assets/propose-guide.md'
            )) {
            $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $path) -Raw
            $text | Should -Match 'Test-SiWriteScope\.ps1'
            $text | Should -Match '(?i)complete Git diff'
            $text | Should -Match '(?i)leaves the local diff visible'
            $text | Should -Match '(?i)Do not claim rollback'
        }
    }

    It 'test:SelfImprovement.RetiredStateResidue has no lifecycle payload or scaffold' {
        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 50
        $json = $manifest | ConvertTo-Json -Depth 20
        $json | Should -Not -Match 'Enqueue-SiDue|Invoke-SiLifecycle|Invoke-SiProposalSync|Complete-SiProposal'
        $json | Should -Not -Match 'Repair-SiState|SiStateStore|resolver-receipt|docs/self-improvement|feedback/queue'
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'docs/feedback/queue.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'docs/self-improvement/state.json') | Should -BeFalse
    }

    It 'test:SelfImprovement.Distribution keeps source and installed SI boundary files byte-identical' {
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
