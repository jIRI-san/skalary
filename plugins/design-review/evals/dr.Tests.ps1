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
        $script:agent = Get-Content (Join-Path $script:plugin 'agents/dr.agent.md') -Raw
    }

    It 'eval:DirectWorkflow.DR.ConsumerContract uses bounded risk-selected direct review' {
        foreach ($token in @('no fixed matrix', 'three-call ceiling', 'read-only',
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

    It 'eval:PlanningReview.DR keeps the caller-selected planning role advisory and read-only' {
        foreach ($token in @(
                'When `/cip` explicitly selects the pre-confirmation reviewer role',
                'secondary-model-high`/high',
                'Do not edit, require clean, choose applicability',
                'caller role does not alter standalone `/dr` routing'
            )) {
            $script:skill | Should -Match ([regex]::Escape($token))
        }
        $script:skill | Should -Match '(?s)every evidence-backed design and supplied\s+epic-coherency finding'
        $script:skill | Should -Match 'report rule below does not apply to this caller role'
        $script:agent | Should -Match 'never for CIP''s\s+pre-confirmation reviewer role'
    }
}
