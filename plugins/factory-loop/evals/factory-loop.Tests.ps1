#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'factory-loop structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/factory-loop'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 50
        $script:evalRoot = Join-Path $script:pluginRoot 'evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:evalRoot 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:evalRoot 'tasks') `
                -Filter '*.yaml' | Sort-Object Name)
    }

    It 'test:FactoryLoop.EvalContract keeps Waza optional, deterministic, and scoped to the installed skill' {
        [string]$script:manifest.evals.path | Should -BeExactly 'evals/'
        $script:evalYaml | Should -Match '(?m)^skill:\s*factory-loop\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+skill_directories:\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+-\s+\.\./\.\./skills\s*$'
        @($script:taskFiles).Count | Should -Be 2
        foreach ($file in $script:taskFiles) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            $raw | Should -Match '(?m)^# ai-credit-disposition: deterministic\r?$'
            $raw | Should -Match '(?ms)^inputs:\s*\n.*?^graders:\s*\n'
            $raw | Should -Match '(?m)^\s+-\s+type:\s*text\s*$'
            $raw | Should -Not -Match '(?m)^\s+-\s+type:\s*(tool_constraint|code|prompt)\s*$'
            $raw | Should -Not -Match 'set_waza_grade_(pass|fail)'
            $raw | Should -Not -Match '[A-Za-z]:\\|\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            $raw | Should -Match '(?i)Do not run tools'
        }
        $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
    }

    It 'test:FactoryLoop.Documentation describes the actual repair, approval, evidence, and offline limits' {
        $skill = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/factory-loop/SKILL.md'
        ) -Raw
        $guide = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/factory-loop/assets/operator-guide.md'
        ) -Raw
        $skill | Should -Match 'Register-FactoryLoopRepairPullRequest\.ps1'
        $skill | Should -Match 'factory-repair/<incident>/<attempt>'
        $guide | Should -Match '(?i)stable build\s+lineage'
        $guide | Should -Match '(?i)artifact-specific production approval'
        $guide | Should -Match '(?i)deployment triggers'
        $guide | Should -Match '(?i)no AI, network, or credentials'
        $guide | Should -Match 'Invoke-WazaEvals\.ps1 -Plugin factory-loop'
        $guide | Should -Match '(?i)do not execute live adapters'

        $destinations = @($script:manifest.files | ForEach-Object { [string]$_.dest })
        $destinations | Should -Contain 'skills/factory-loop/scripts/Register-FactoryLoopRepairPullRequest.ps1'
        $destinations | Should -Contain 'skills/factory-loop/assets/operator-guide.md'
    }
}
