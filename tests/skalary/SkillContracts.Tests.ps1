#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Direct workflow skill contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        function Get-SkillText {
            param([Parameter(Mandatory)][string]$Path)
            Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw
        }
    }

    It 'test:ci-skill-retains-judgment protects criteria and visible outcomes' {
        $text = Get-SkillText 'plugins/continue-implementation/skills/ci/SKILL.md'
        $text | Should -Match 'Test-PlanCriteriaBaseline'
        $text | Should -Match 'Before any checklist, branch,\s*worktree, log, or source mutation'
        $text | Should -Match 'completed/refused/blocked/stuck/interrupted'
        $text | Should -Match 'operator-action stops retain `42`'
    }

    It 'test:ci-skill-planstate uses direct current-run evidence' {
        $text = Get-SkillText 'plugins/continue-implementation/skills/ci/SKILL.md'
        $text | Should -Match 'Invoke-DirectEvidence'
        $text | Should -Match 'active in-memory review result'
        $text | Should -Match 'persisted\s+Markdown is not authority'
    }

    It 'test:cip-skill-scripts confirms all four criteria before drafting' {
        $text = Get-SkillText 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $text | Should -Match 'current intent, requirements, risks, and decisions'
        $text | Should -Match 'planning-confirmed'
        $text | Should -Match 'Get-DirectPlanArtifactConsumerContext'
        $text | Should -Match 'Judge'
    }

    It 'test:autopilot-plan-id protects criteria in every launched agent' {
        $skill = Get-SkillText 'plugins/autopilot/skills/autopilot/SKILL.md'
        $agent = Get-SkillText 'plugins/autopilot/agents/autopilot.agent.md'
        $skill | Should -Match 'Test-PlanCriteriaBaseline'
        $agent | Should -Match 'Test-PlanCriteriaBaseline'
        $agent | Should -Match 'Invoke-DirectEvidence'
    }

    It 'test:single-terminal-review prevents overlapping terminal review' {
        foreach ($path in @(
                'plugins/continue-implementation/skills/ci/SKILL.md',
                'plugins/autopilot/agents/autopilot.agent.md'
            )) {
            $text = Get-SkillText $path
            $text | Should -Match 'terminal phase skips post-phase'
            $text | Should -Match 'one whole-plan\s+direct CR'
            $text | Should -Match 'If scope is unchanged, do not rerun'
        }
    }

    It 'test:review-direct-contract retains read-only and concrete threat guards' {
        foreach ($path in @(
                'plugins/code-review/skills/cr/SKILL.md',
                'plugins/design-review/skills/dr/SKILL.md'
            )) {
            $text = Get-SkillText $path
            $text | Should -Match 'read-only'
            $text | Should -Match 'Write-DirectReviewReport'
            $text | Should -Match 'attacker/input, reachable capability'
            $text | Should -Match 'clean`, `findings`, or `incomplete'
        }
    }

    It 'test:native-budget-contract bounds roles context and recovery' {
        foreach ($path in @(
                'plugins/create-implementation-plan/skills/cip/SKILL.md',
                'plugins/continue-implementation/skills/ci/SKILL.md',
                'plugins/autopilot/agents/autopilot.agent.md'
            )) {
            $text = Get-SkillText $path
            $text | Should -Match 'five maximum|hard task maximum'
            $text | Should -Match 'at most five'
            $text | Should -Match '600/1,200|target 600 words'
            $text | Should -Match 'Judge'
        }
    }

    It 'test:no-elapsed-agent-kill retains deterministic command timeouts' {
        $text = Get-SkillText 'plugins/autopilot/agents/autopilot.agent.md'
        $text | Should -Match 'Never cancel because elapsed agent time'
        $text | Should -Match 'deterministic\s+build/test/command timeouts'
        $text | Should -Match 'Synchronous opaque calls'
    }
}
