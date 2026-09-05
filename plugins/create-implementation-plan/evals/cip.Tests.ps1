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
    }

    It 'eval:DirectWorkflow.CIP.ConsumerContract uses decision-ready native planning with a normal judge' {
        foreach ($text in @($script:cip, $script:cep)) {
            $text | Should -Match 'combined design/requirements'
            $text | Should -Match 'Judge'
            $text | Should -Match 'five maximum'
            $text | Should -Match 'effort 1-10'
            $text | Should -Match 'complexity 1-10'
            $text | Should -Not -Match 'Fleet'
        }
    }

    It 'ships direct historical context without legacy receipt adapters' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest }) -join "`n"
        $dest | Should -Match 'Get-DirectPlanArtifactConsumerContext\.ps1'
        $dest | Should -Match 'DirectWorkflow\.psm1'
        $dest | Should -Not -Match 'Get-PlanArtifactConsumerContext|Fleet|ReviewResultReceipt|Repair'
    }
}
