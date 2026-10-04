#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'factory-loop waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoRoot = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:wazaRoot = Join-Path $repoRoot 'plugins/factory-loop/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:wazaRoot 'eval.yaml') -Raw
        $script:tasks = @(Get-ChildItem -LiteralPath (Join-Path $script:wazaRoot 'tasks') `
                -Filter '*.yaml' | Sort-Object Name)
    }

    It 'test:waza-spec-shape targets the factory-loop skill with the pinned schema and executor' {
        $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        $script:evalYaml | Should -Match '(?m)^skill:\s*factory-loop\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+model:\s*gpt-5\.6-luna\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*gpt-5\.6-terra\s*$'
        $script:evalYaml | Should -Match '(?m)^\s+-\s+\.\./\.\./skills\s*$'
        $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
    }

    It 'test:waza-spec-shape contains two describe-only tasks with deterministic graders' {
        @($script:tasks).Count | Should -Be 2
        foreach ($task in $script:tasks) {
            $raw = Get-Content -LiteralPath $task.FullName -Raw
            $raw | Should -Match '(?m)^# ai-credit-disposition: deterministic\r?$'
            $raw | Should -Match '(?ms)^inputs:\s*\n.*?^graders:\s*\n'
            $raw | Should -Match '(?m)^\s+-\s+type:\s*text\s*$'
            $raw | Should -Not -Match '(?m)^\s+-\s+type:\s*(tool_constraint|code|prompt)\s*$'
            $raw | Should -Not -Match 'set_waza_grade_(pass|fail)'
            $raw | Should -Match '(?i)Do not run tools'
        }
    }

    It 'test:live-tree-clean keeps eval inputs independent of repository and absolute paths' {
        foreach ($file in @(Get-ChildItem -LiteralPath $script:wazaRoot -Recurse -File)) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            $raw | Should -Not -Match '[A-Za-z]:\\'
            $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
        }
    }
}
