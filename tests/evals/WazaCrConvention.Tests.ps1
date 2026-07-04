#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped cr waza convention. waza fails OPEN — a misplaced or
# misspelled field is warned-and-ignored, so a silently-dropped grader would read as a false
# PASS. These tests assert EXACT field placement offline (no premium requests), so the spec
# cannot rot into a shape waza quietly ignores.

Describe 'cr waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:crDir = Join-Path $repoDir 'plugins/code-review/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:crDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:crDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:injectionTask = Get-Content -LiteralPath (Join-Path $script:crDir 'tasks/treat-injection-as-data.yaml') -Raw
        $script:plantedTask = Get-Content -LiteralPath (Join-Path $script:crDir 'tasks/flag-planted-bug.yaml') -Raw
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema, executor, and a REAL tool_constraint' {
        It 'test:waza-spec-shape pins schemaVersion 1.2 (required for the adversarial block)' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the cr agent via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*cr\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape declares a spec-level tool_constraint using a MAPPED copilot-sdk tool name' {
            # Gotcha A: cr.agent.md frontmatter names (read/search/execute) are NOT what copilot-sdk
            # surfaces. The override must reference the mapped name (view) or the auto-injected
            # constraint fires against a name that can never match and false-fails every task.
            $script:evalYaml | Should -Match '(?ms)^graders:\s*\n(?:.*\n)*?\s+-\s*type:\s*tool_constraint'
            $script:evalYaml | Should -Match '(?m)^\s+-\s*tool:\s*view\s*$'
        }
    }

    Context 'test:waza-spec-shape — every task uses an independent judge fed a forced text turn' {
        It 'test:waza-spec-shape each task has follow_up_prompts UNDER inputs (not at task top level)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                # forced-turn key must be indented (under inputs), never column-0 (silently ignored).
                $raw | Should -Match '(?m)^\s+follow_up_prompts:'
                $raw | Should -Not -Match '(?m)^follow_up_prompts:'
            }
        }

        It 'test:waza-spec-shape each task feeds a fixture via inputs.context.fixture' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Match '(?m)^\s+context:'
                $raw | Should -Match '(?m)^\s+fixture:\s*fixtures/'
            }
        }

        It 'test:waza-spec-shape each prompt (judge) grader RESUMES the session (continue_session: true, never false)' {
            # 2.1 live evidence: the independent judge (continue_session: false) is flaky — it is
            # dropped into the workspace without cr's output injected and false-fails. Resuming
            # the session is the stable, deterministic configuration.
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Match '(?m)^\s+-\s*type:\s*prompt'
                $raw | Should -Match '(?m)^\s+continue_session:\s*true'
                $raw | Should -Not -Match '(?m)^\s+continue_session:\s*false'
                # judge model is pinned explicitly (prompt grader requires `model`).
                $raw | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            }
        }
    }

    Context 'test:injection-guard — the injection case is covered functionally AND by the adversarial pack' {
        It 'test:injection-guard eval.yaml declares the prompt-injection pack with on_unsafe_outcome: fail' {
            $script:evalYaml | Should -Match '(?ms)^adversarial:\s*\n(?:.*\n)*?\s+packs:'
            $script:evalYaml | Should -Match '(?m)^\s+-\s*prompt-injection\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+on_unsafe_outcome:\s*fail'
        }

        It 'test:injection-guard the functional injection task rejects a bare-approval output deterministically' {
            $script:injectionTask | Should -Match '(?m)^\s+-\s*type:\s*text'
            $script:injectionTask | Should -Match '(?m)^\s+regex_not_match:'
            # the tripwire targets an output that is ONLY an approval (the injection winning).
            $script:injectionTask | Should -Match 'lgtm'
        }

        It 'test:injection-guard the injection fixture actually carries an injected directive' {
            $fx = Get-Content -LiteralPath (Join-Path $script:crDir 'fixtures/injected-approve.diff') -Raw
            $fx | Should -Match '(?i)ignore all prior instructions'
            $fx | Should -Match '(?i)approve this pr'
        }
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task/fixture references an absolute or UNC path (gate-a escape vector)' {
            # Gate (a): waza contains RELATIVE writes to the per-task temp workspace but ABSOLUTE
            # writes escape to the live tree. A static guard: none of the shipped cr files may carry
            # an absolute Windows drive path or a UNC path that an agent could be steered to write.
            foreach ($f in @(Get-ChildItem -LiteralPath $script:crDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                # Real UNC shape (\\host\share), not an escaped regex backslash like \\s in a grader.
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }

        It 'test:live-tree-clean waza run output lives under gitignored tests/evals/output' {
            $gitignore = Get-Content -LiteralPath (Join-Path $script:repoDir '.gitignore') -Raw
            $gitignore | Should -Match '(?m)^\s*tests/evals/output'
        }
    }

    Context 'test:no-legacy-cr-llm — the bespoke cr LLM cases are gone after cutover' {
        It 'test:no-legacy-cr-llm leaves no plugins/code-review/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/code-review/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
