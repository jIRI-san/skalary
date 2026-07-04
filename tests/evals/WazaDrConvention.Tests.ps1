#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped dr waza convention. waza fails OPEN — a misplaced or
# misspelled field is warned-and-ignored, so a silently-dropped grader would read as a false
# PASS. These tests assert EXACT field placement offline (no premium requests), so the spec
# cannot rot into a shape waza quietly ignores. dr's two cases are functional (no adversarial
# block), so this mirrors WazaCrConvention.Tests.ps1 minus the injection-pack guard.

Describe 'dr waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:drDir = Join-Path $repoDir 'plugins/design-review/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:drDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:drDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema, executor, and a REAL tool_constraint' {
        It 'test:waza-spec-shape pins schemaVersion 1.2' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the dr agent via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*dr\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape declares a spec-level tool_constraint using a MAPPED copilot-sdk tool name' {
            # Gotcha A: dr.agent.md frontmatter names (read/search) are NOT what copilot-sdk
            # surfaces. The override must reference the mapped name (view) or the auto-injected
            # constraint fires against a name that can never match and false-fails every task.
            $script:evalYaml | Should -Match '(?ms)^graders:\s*\n(?:.*\n)*?\s+-\s*type:\s*tool_constraint'
            $script:evalYaml | Should -Match '(?m)^\s+-\s*tool:\s*view\s*$'
        }

        It 'test:waza-spec-shape declares NO adversarial block (both dr cases are functional)' {
            $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
        }
    }

    Context 'test:waza-spec-shape — every task uses a resume-session judge fed a forced text turn' {
        # Fail-open defence: split each task at the col-0 `inputs:`/`graders:` keys and assert the
        # forced-turn/fixture live in the inputs block and the graders live in the graders block.
        # Anchoring only nested content (as an earlier revision did) would pass green even if a
        # task's `graders:` key were misspelled or mis-nested, silently dropping every grader.
        It 'test:waza-spec-shape each task has col-0 inputs: and graders: keys in order' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Match '(?m)^inputs:'
                $raw | Should -Match '(?m)^graders:'
                # inputs: must precede graders: (canonical task shape).
                $raw | Should -Match '(?ms)^inputs:\s*\n.*?^graders:\s*\n'
            }
        }

        It 'test:waza-spec-shape forced-turn + fixture are nested inside the inputs block (not the graders block)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $m = [regex]::Match($raw, '(?ms)^inputs:\s*\n(?<inputs>.*?)^graders:\s*\n(?<graders>.*)$')
                $m.Success | Should -BeTrue
                $inputs = $m.Groups['inputs'].Value
                $inputs | Should -Match '(?m)^\s+follow_up_prompts:'
                $inputs | Should -Match '(?m)^\s+context:'
                $inputs | Should -Match '(?m)^\s+fixture:\s*fixtures/'
                # the forced turn must NOT leak into the graders block.
                $m.Groups['graders'].Value | Should -Not -Match '(?m)^\s+follow_up_prompts:'
            }
        }

        It 'test:waza-spec-shape each prompt (judge) grader RESUMES the session (continue_session: true, never false)' {
            # 2.1 live evidence: the independent judge (continue_session: false) is flaky — it is
            # dropped into the workspace without the agent output injected and false-fails. Resuming
            # the session is the stable, deterministic configuration.
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
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task/fixture references an absolute or UNC path (gate-a escape vector)' {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:drDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }
    }

    Context 'test:no-legacy-dr-llm — the bespoke dr LLM cases are gone after cutover' {
        It 'test:no-legacy-dr-llm leaves no plugins/design-review/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/design-review/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
