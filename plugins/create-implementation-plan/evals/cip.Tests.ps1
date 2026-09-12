#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'planning direct structural evals' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $plugin = Join-Path $root 'plugins/create-implementation-plan'
        $script:manifest = Get-Content (Join-Path $plugin 'plugin.json') -Raw | ConvertFrom-Json
        $script:cip = Get-Content (Join-Path $plugin 'skills/cip/SKILL.md') -Raw
        $script:cep = Get-Content (Join-Path $plugin 'skills/cep/SKILL.md') -Raw
        $script:decision = Get-Content (
            Join-Path $plugin 'skills/cip/assets/decision-protocol.md'
        ) -Raw
        $script:review = Get-Content (
            Join-Path $plugin 'skills/cip/assets/pre-confirmation-review.md'
        ) -Raw
    }

    It 'eval:DirectWorkflow.CIP.ConsumerContract uses decision-ready native planning with a normal judge' {
        foreach ($text in @($script:cip, $script:cep)) {
            $text | Should -Match 'design-and-requirements|design and acceptance criteria'
            $text | Should -Match 'Judge'
            $text | Should -Match 'three-call ceiling'
        }
        $script:decision | Should -Match '`effort: <1-10>`'
        $script:decision | Should -Match '`complexity: <1-10>`'
    }

    It 'ships direct historical context with its direct module' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest }) -join "`n"
        $dest | Should -Match 'Get-DirectPlanArtifactConsumerContext\.ps1'
        $dest | Should -Match 'DirectWorkflow\.psm1'
        @($script:manifest.files | Where-Object {
                [string]$_.dest -match 'Get-DirectPlanArtifactConsumerContext\.ps1$'
            }).Count | Should -Be 2
    }

    It 'eval:PlanningReview.CIP runs the mandatory two-pass review before confirmation' {
        $script:cip | Should -Match '(?s)complete draft.*?pre-confirmation-review'
        $script:cip | Should -Match '(?s)secondary-model-high`/high.*?primary-model-high`/high'
        $script:cip | Should -Match 'one operator choice'
        $script:cip | Should -Match 'never rerun'
        $script:cip | Should -Match '(?s)selected edits.*?planning-confirmed'

        foreach ($token in @(
                'exactly these two calls in this order',
                'If either pass fails, is interrupted',
                'or is incomplete',
                'all evidence-backed design findings',
                'fix`, `simplify`, `defer`, or `ignore',
                'all findings and their recommendations in one consolidated operator selection',
                'not persisted as review state'
            )) {
            $script:review | Should -Match ([regex]::Escape($token))
        }
    }

    It 'eval:PlanningReview.CIP bounds epic coherency to targeted current evidence' {
        foreach ($token in @(
                'resolvable',
                'Resolve-Epic`/`Get-EpicRollup',
                'only sibling intent, owned outcome, interfaces, dependencies, and decisions',
                'current implementation or active contract',
                'scope overlap, ownership, interfaces, necessary acyclic dependencies, sequencing',
                'Do not load every sibling artifact or historical log',
                'mutate the epic or siblings',
                'cannot be established cheaply'
            )) {
            $script:review | Should -Match ([regex]::Escape($token))
        }
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest })
        $dest | Should -Contain 'skills/cip/assets/pre-confirmation-review.md'
    }
}
