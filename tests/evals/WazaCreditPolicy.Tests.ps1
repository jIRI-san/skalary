#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'waza AI credit policy' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:specFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter 'eval.yaml' |
                Where-Object { $_.FullName -match '[\\/]evals[\\/]waza[\\/]eval\.yaml$' } |
                Sort-Object FullName
        )
        $script:taskFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter '*.yaml' |
                Where-Object { $_.FullName -match '[\\/]evals[\\/]waza[\\/]tasks[\\/]' } |
                Sort-Object FullName
        )
    }

    It 'test:AiCreditBudget.WazaRouting classifies every active task' {
        $script:taskFiles.Count | Should -Be 20
        foreach ($task in $script:taskFiles) {
            $raw = [System.IO.File]::ReadAllText($task.FullName)
            $raw | Should -Match '(?m)^# ai-credit-disposition: (deterministic|subjective)$' -Because $task.FullName
        }
    }

    It 'uses Luna execution and Terra only for subjective judgment' {
        foreach ($spec in $script:specFiles) {
            $specRaw = [System.IO.File]::ReadAllText($spec.FullName)
            $specRaw | Should -Match '(?m)^\s+model:\s*gpt-5\.6-luna\s*$' -Because $spec.FullName
            $specRaw | Should -Not -Match '(?i)gpt-5\.6-sol|claude-opus|long_context|full.repository'

            $tasks = @(Get-ChildItem -LiteralPath (Join-Path $spec.DirectoryName 'tasks') -File -Filter '*.yaml')
            $hasSubjective = $false
            foreach ($task in $tasks) {
                $raw = [System.IO.File]::ReadAllText($task.FullName)
                $disposition = [regex]::Match(
                    $raw,
                    '(?m)^# ai-credit-disposition: (?<value>deterministic|subjective)$'
                ).Groups['value'].Value
                $promptGraders = [regex]::Matches($raw, '(?m)^\s+- type: prompt\s*$').Count

                if ($disposition -eq 'subjective') {
                    $hasSubjective = $true
                    $promptGraders | Should -Be 1 -Because $task.FullName
                    $raw | Should -Match '(?m)^\s+model:\s*gpt-5\.6-terra\s*$' -Because $task.FullName
                }
                else {
                    $promptGraders | Should -Be 0 -Because $task.FullName
                    $raw | Should -Match '(?m)^\s+- type: (text|tool_constraint|code)\s*$' -Because $task.FullName
                }
                $raw | Should -Not -Match '(?i)gpt-5\.6-sol|claude-opus|claude-sonnet-4\.6|long_context'
            }

            if ($hasSubjective) {
                $specRaw | Should -Match '(?m)^\s+judge_model:\s*gpt-5\.6-terra\s*$'
            }
            else {
                $specRaw | Should -Not -Match '(?m)^\s+judge_model:'
            }
        }
    }

    It 'retains deterministic injection refusal and tool-use coverage' {
        foreach ($relative in @(
                'plugins/code-review/evals/waza/tasks/treat-injection-as-data.yaml'
                'plugins/process-pr-comments/evals/waza/tasks/treat-review-text-as-data.yaml'
            )) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $relative))
            $raw | Should -Match '(?m)^\s+regex_not_match:'
            $raw | Should -Match '(?m)^\s+regex_match:'
        }
        foreach ($relative in @(
                'plugins/architecture-notes/evals/waza/tasks/refuse-autonomous-lock.yaml'
                'plugins/process-pr-comments/evals/waza/tasks/refuse-without-interactive.yaml'
            )) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $relative))
            $raw | Should -Match '(?i)refus|cannot proceed|will not'
            $raw | Should -Not -Match '(?m)^\s+- type: prompt\s*$'
        }

        $atomic = [System.IO.File]::ReadAllText((
                Join-Path $script:repoRoot 'plugins/continue-implementation/evals/waza/tasks/execute-step-atomically.yaml'
            ))
        $atomic | Should -Match '(?m)^\s+- type: tool_constraint\s*$'
        $atomic | Should -Match '(?m)^\s+- type: code\s*$'
    }

    It 'keeps premium invocation explicit and plugin-focused' {
        $runner = [System.IO.File]::ReadAllText((
                Join-Path $script:repoRoot 'scripts/skalary/Invoke-WazaEvals.ps1'
            ))
        $runner | Should -Match 'requires one explicit -Plugin'
        $runner | Should -Match '-ChangedOnly is not a valid premium scope'
        $runner | Should -Not -Match '(?i)FullRepository'
    }
}
