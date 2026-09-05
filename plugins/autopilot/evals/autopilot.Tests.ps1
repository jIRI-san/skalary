#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'autopilot direct structural evals' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $plugin = Join-Path $root 'plugins/autopilot'
        $script:manifest = Get-Content (Join-Path $plugin 'plugin.json') -Raw | ConvertFrom-Json
        $script:agent = Get-Content (Join-Path $plugin 'agents/autopilot.agent.md') -Raw
        $script:runtime = @(
            'scripts/launch-host.ps1'
            'scripts/launch-container.ps1'
            'scripts/launch-sandbox.ps1'
            'scripts/container-entrypoint.sh'
        ) | ForEach-Object { Get-Content (Join-Path $plugin $_) -Raw }
    }

    It 'eval:DirectWorkflow.Autopilot.ConsumerContract uses direct evidence and one terminal review' {
        foreach ($token in @('Test-PlanCriteriaBaseline', 'Invoke-DirectEvidence',
                'one whole-plan direct CR', 'Never cancel because elapsed agent time',
                'recent-learning.md')) {
            $script:agent | Should -Match ([regex]::Escape($token))
        }
    }

    It 'ships no legacy scheduler or receipt closure' {
        $dest = @($script:manifest.files | ForEach-Object { [string]$_.dest }) -join "`n"
        $dest | Should -Match 'DirectWorkflow\.psm1'
        $dest | Should -Not -Match 'Fleet|Receipt|Harvest|Ledger|ReviewCycle'
    }

    It 'uses a synchronous host boundary without elapsed agent kills' {
        ($script:runtime -join "`n") |
            Should -Not -Match 'planTimeout|PHASE_TIMEOUT|timed out after|docker kill'
    }
}
