#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'AI credit budget contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:entrypoints = [ordered]@{
            autopilot = 'plugins/autopilot/skills/autopilot/SKILL.md'
            cep       = 'plugins/create-implementation-plan/skills/cep/SKILL.md'
            cip       = 'plugins/create-implementation-plan/skills/cip/SKILL.md'
            ci        = 'plugins/continue-implementation/skills/ci/SKILL.md'
            cr        = 'plugins/code-review/skills/cr/SKILL.md'
            dr        = 'plugins/design-review/skills/dr/SKILL.md'
            si        = 'plugins/self-improvement/skills/si/SKILL.md'
        }
        $script:delegationPolicies = @(
            'plugins/create-implementation-plan/skills/cep/SKILL.md'
            'plugins/create-implementation-plan/skills/cip/SKILL.md'
            'plugins/continue-implementation/skills/ci/SKILL.md'
            'plugins/code-review/skills/cr/SKILL.md'
            'plugins/design-review/skills/dr/SKILL.md'
            'plugins/autopilot/agents/autopilot.agent.md'
        )

        function Read-RepoText {
            param([Parameter(Mandatory)][string]$Path)
            [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $Path))
        }
    }

    It 'test:AiCreditBudget.ModelRouting keeps the cheap-first ladder explicit' {
        $policy = $script:delegationPolicies | ForEach-Object { Read-RepoText $_ }
        $joined = $policy -join "`n"

        foreach ($model in @('Luna', 'GPT-5 mini', 'Terra', 'Claude Sonnet 5', 'Sol', 'Opus')) {
            $joined | Should -Match ([regex]::Escape($model))
        }
        $joined | Should -Match 'Luna/medium'
        $joined | Should -Match 'Terra/high'
        $joined | Should -Match 'Sol/high'
        $joined | Should -Match 'Opus/high'
        $joined | Should -Not -Match 'Sol (?:review|work) is normal|Sol for routine'
        $joined | Should -Not -Match 'Opus.*routine fallback'
    }

    It 'test:AiCreditBudget.DelegationLimits defaults direct and removes the automatic Judge' {
        foreach ($path in $script:delegationPolicies) {
            $content = Read-RepoText $path
            $content | Should -Match 'direct'
            $content | Should -Match 'three-call ceiling'
            $content | Should -Match 'fourth\s+requires a new operator\s+decision'
            $content | Should -Match 'No\s+automatic Judge'
            $content | Should -Not -Match 'two calls by default|five (?:calls|maximum)'
        }
    }

    It 'test:AiCreditBudget.ReviewRouting uses one standard review and risk-gated independence' {
        foreach ($path in @(
                'plugins/code-review/skills/cr/SKILL.md'
                'plugins/design-review/skills/dr/SKILL.md'
            )) {
            $content = Read-RepoText $path
            $content | Should -Match 'One combined Terra/high review'
            $content | Should -Match 'one Opus/high independent pass only for a\s+named'
            $content | Should -Match 'security,\s*concurrency,\s*destructive,\s*correctness,\s*or architecture risk'
            $content | Should -Match 'No\s+automatic Judge,\s*model panel,\s*or unchanged-scope rerun'
        }
    }

    It 'test:AiCreditBudget.SkillContext caps recurring skill context and delegated prompts' {
        foreach ($path in $script:entrypoints.Values) {
            $fullPath = Join-Path $script:repoRoot $path
            (Get-Item -LiteralPath $fullPath).Length | Should -BeLessOrEqual 4096 -Because $path
            $content = [System.IO.File]::ReadAllText($fullPath)
            $content | Should -Match '(?s)at most\s+three.*?artifacts' -Because $path
            $content | Should -Match '400' -Because $path
            $content | Should -Match '800' -Because $path
        }
    }

    It 'test:AiCreditBudget.ConsumerInstall keeps dogfood copies and the SI asset complete' {
        foreach ($name in $script:entrypoints.Keys) {
            $sourcePath = Join-Path $script:repoRoot $script:entrypoints[$name]
            $installedPath = Join-Path $script:repoRoot ".github/skills/$name/SKILL.md"
            [System.IO.File]::ReadAllBytes($installedPath) |
                Should -Be ([System.IO.File]::ReadAllBytes($sourcePath)) -Because $name
        }

        $manifest = Read-RepoText 'plugins/self-improvement/plugin.json' | ConvertFrom-Json
        @($manifest.files.src) | Should -Contain 'skills/si/assets/lifecycle-guide.md'
        Test-Path -LiteralPath (
            Join-Path $script:repoRoot '.github/skills/si/assets/lifecycle-guide.md'
        ) -PathType Leaf | Should -BeTrue
    }

    It 'test:AiCreditBudget.RetainedGuards preserves safety, evidence, and premium-run boundaries' {
        foreach ($path in @(
                'plugins/code-review/skills/cr/SKILL.md'
                'plugins/design-review/skills/dr/SKILL.md'
            )) {
            $content = Read-RepoText $path
            foreach ($guardPattern in @(
                    'prompt\s+injection'
                    'secret\s+refusal/redaction'
                    'read-only'
                    'destructive\s*-\s*action\s+approval'
                    'physical/canonical\s+report\s+confinement'
                    'external-format\s+validation'
                )) {
                $content | Should -Match $guardPattern -Because $path
            }
        }

        $ci = Read-RepoText 'plugins/continue-implementation/skills/ci/SKILL.md'
        $ci | Should -Match 'Test-PlanCriteriaBaseline'
        $ci | Should -Match 'test:.*file:.*review:'
        $ci | Should -Match 'completed/refused/blocked/stuck/interrupted'

        $waza = Read-RepoText 'scripts/skalary/Invoke-WazaEvals.ps1'
        $waza | Should -Match 'Waza requires one explicit -Plugin'
        $waza | Should -Match 'executed ZERO evals'
    }
}
