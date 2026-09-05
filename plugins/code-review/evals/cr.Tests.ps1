#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'cr direct structural evals' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:plugin = Join-Path $root 'plugins/code-review'
        $script:manifest = Get-Content (Join-Path $script:plugin 'plugin.json') -Raw |
            ConvertFrom-Json
        $script:skill = Get-Content (Join-Path $script:plugin 'skills/cr/SKILL.md') -Raw
    }

    It 'eval:DirectWorkflow.CR.ConsumerContract uses bounded risk-selected direct review' {
        foreach ($token in @('no fixed concern matrix', 'five maximum', 'read-only',
                'Write-DirectReviewReport', 'incomplete', 'attacker/input')) {
            $script:skill | Should -Match ([regex]::Escape($token))
        }
    }

    It 'ships only direct review scripts and one orchestrator agent' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest })
        foreach ($path in @(
                'skills/cr/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'skills/cr/scripts/DirectWorkflow.psm1',
                'skills/cr/scripts/PlanState.psm1',
                'skills/cr/scripts/SecretGuard.psm1',
                'agents/cr.agent.md',
                'agents/scripts/Get-ReviewScope.ps1'
            )) {
            $dest | Should -Contain $path
        }
        ($dest -join "`n") | Should -Not -Match 'ReviewRun|Fleet|receipt|cr-(?:security|performance)'
    }
}
