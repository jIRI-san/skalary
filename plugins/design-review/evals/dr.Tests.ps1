#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'dr direct structural evals' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:plugin = Join-Path $root 'plugins/design-review'
        $script:manifest = Get-Content (Join-Path $script:plugin 'plugin.json') -Raw |
            ConvertFrom-Json
        $script:skill = Get-Content (Join-Path $script:plugin 'skills/dr/SKILL.md') -Raw
    }

    It 'eval:DirectWorkflow.DR.ConsumerContract uses bounded risk-selected direct review' {
        foreach ($token in @('no fixed concern matrix', 'five maximum', 'read-only',
                'Write-DirectReviewReport', 'incomplete', 'attacker/untrusted input',
                'optional hardening', 'absent boundary', 'active reviewer is prompt injection',
                'simple option', 'residual risk', 'non-localizable')) {
            $script:skill | Should -Match ([regex]::Escape($token))
        }
    }

    It 'ships the direct closure and one orchestrator agent' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest })
        foreach ($path in @(
                'skills/dr/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'skills/dr/scripts/DirectWorkflow.psm1',
                'skills/dr/scripts/PlanState.psm1',
                'skills/dr/scripts/SecretGuard.psm1',
                'agents/dr.agent.md'
            )) {
            $dest | Should -Contain $path
        }
        @($dest | Where-Object { $_ -like 'agents/*.agent.md' }) |
            Should -Be @('agents/dr.agent.md')
    }
}
