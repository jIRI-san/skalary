#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'ci direct structural evals' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $plugin = Join-Path $root 'plugins/continue-implementation'
        $script:manifest = Get-Content (Join-Path $plugin 'plugin.json') -Raw | ConvertFrom-Json
        $script:skill = Get-Content (Join-Path $plugin 'skills/ci/SKILL.md') -Raw
    }

    It 'eval:DirectWorkflow.CI.ConsumerContract protects criteria and evaluates current evidence directly' {
        $script:skill | Should -Match 'Before any checklist, branch,\s*worktree, log, or source mutation'
        $script:skill | Should -Match 'Test-PlanCriteriaBaseline'
        $script:skill | Should -Match 'Invoke-DirectEvidence'
        $script:skill | Should -Match 'terminal phase skips post-phase review'
        $script:skill | Should -Match 'recent-learning\.md'
    }

    It 'ships no scheduler receipt or repair payload' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest }) -join "`n"
        $dest | Should -Match 'DirectWorkflow\.psm1'
        $dest | Should -Not -Match 'Fleet|Receipt|Harvest|Ledger|Repair|ReviewCycle'
    }
}
