#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped ci (continue-implementation) waza convention. waza fails
# OPEN — a misplaced or misspelled field is warned-and-ignored, so a silently-dropped grader
# would read as a false PASS. These tests assert EXACT field placement offline. ci ships TWO
# ported cases: honor-after-dependencies (reasoning, describe-only, judge + text pre-check) and
# execute-step-atomically (bounded real execution: text pre-check + tool_constraint + a code
# ordering grader that asserts build/test ran BEFORE the step commit + resume-session judge).

Describe 'ci waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:ciDir = Join-Path $repoDir 'plugins/continue-implementation/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:ciDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:ciDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:atomicFile = Join-Path $script:ciDir 'tasks/execute-step-atomically.yaml'
        $script:dependsFile = Join-Path $script:ciDir 'tasks/honor-after-dependencies.yaml'
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema and executor' {
        It 'test:waza-spec-shape pins schemaVersion 1.2' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the ci skill via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*ci\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape declares NO adversarial block (both cases are functional)' {
            $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
        }
    }

    Context 'test:waza-spec-shape — both tasks separate inputs from graders and use a resume-session judge' {
        # Fail-open defence: split each task at the col-0 `inputs:`/`graders:` keys and assert the
        # forced-turn lives in the inputs block and graders live in the graders block, so a
        # misspelled/mis-nested parent key cannot silently drop graders and pass green.
        It 'test:waza-spec-shape each task has col-0 inputs: and graders: keys in order' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Match '(?m)^inputs:'
                $raw | Should -Match '(?m)^graders:'
                $raw | Should -Match '(?ms)^inputs:\s*\n.*?^graders:\s*\n'
            }
        }

        It 'test:waza-spec-shape the forced turn is nested inside the inputs block (not the graders block)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $m = [regex]::Match($raw, '(?ms)^inputs:\s*\n(?<inputs>.*?)^graders:\s*\n(?<graders>.*)$')
                $m.Success | Should -BeTrue
                $m.Groups['inputs'].Value | Should -Match '(?m)^\s+follow_up_prompts:'
                $m.Groups['graders'].Value | Should -Not -Match '(?m)^\s+follow_up_prompts:'
            }
        }

        It 'test:waza-spec-shape the prompt (judge) grader RESUMES the session (continue_session: true, never false)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Match '(?m)^\s+-\s*type:\s*prompt'
                $graders | Should -Match '(?m)^\s+continue_session:\s*true'
                $graders | Should -Not -Match '(?m)^\s+continue_session:\s*false'
                $graders | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            }
        }

        It 'test:waza-spec-shape each task has a deterministic text pre-check grader in the graders block' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Match '(?m)^\s+-\s*type:\s*text'
                $graders | Should -Match '(?m)^\s+regex_match:'
            }
        }

        It 'test:waza-spec-shape each task feeds the agent a fixture from the fixtures dir' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $inputs = [regex]::Match($raw, '(?ms)^inputs:\s*\n(?<inputs>.*?)^graders:\s*\n').Groups['inputs'].Value
                $inputs | Should -Match '(?m)^\s+context:'
                $inputs | Should -Match '(?m)^\s+fixture:\s*fixtures/'
            }
        }
    }

    Context 'test:tool-grader-present — execute-step-atomically asserts REAL build/test-before-commit (2.4 headline)' {
        # These graders are the 2.4 upgrade over prose judging: they read the RECORDED tool calls.
        # If waza silently dropped them (fail-open), the rubric judge alone would pass a response
        # that only NARRATES the flow. Assert they live in the graders block, keyed to the shell
        # tool + git/npm argument patterns, so a mis-nest cannot quietly remove them.
        It 'test:tool-grader-present has a tool_constraint expecting the npm build/test AND git commit shell calls' {
            $raw = Get-Content -LiteralPath $script:atomicFile -Raw
            $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Match '(?m)^\s+-\s*type:\s*tool_constraint'
            $graders | Should -Match '(?m)^\s+expect_tools:'
            $graders | Should -Match 'npm \(run \)\?\(build\|test\)'
            $graders | Should -Match 'command:\s*\{\s*regex:\s*"\(\?i\)git'
        }

        It 'test:tool-grader-present has a code ordering grader that runs via javascript (node), not python' {
            $raw = Get-Content -LiteralPath $script:atomicFile -Raw
            $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Match '(?m)^\s+-\s*type:\s*code'
            $graders | Should -Match '(?m)^\s+language:\s*javascript'
            $graders | Should -Not -Match '(?m)^\s+language:\s*python'
            $graders | Should -Match '(?m)^\s+assertions:'
        }

        It 'test:tool-grader-present the ordering assertion matches c.arguments only (never the tool result, which carries diff --git noise)' {
            $raw = Get-Content -LiteralPath $script:atomicFile -Raw
            $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Match 'c\.arguments'
            $graders | Should -Not -Match 'JSON\.stringify\(c\)'
        }

        It 'test:tool-grader-present honor-after-dependencies is reasoning-only (no tool_constraint / code graders)' {
            $raw = Get-Content -LiteralPath $script:dependsFile -Raw
            $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*tool_constraint'
            $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*code'
        }
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task/fixture references an absolute or UNC path (gate-a escape vector)' {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:ciDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }
    }

    Context 'test:no-legacy-ci-llm — the bespoke ci LLM cases are gone after cutover' {
        It 'test:no-legacy-ci-llm leaves no plugins/continue-implementation/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/continue-implementation/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
