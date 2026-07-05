#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped process-pr-comments waza convention. waza fails OPEN — a
# misplaced or misspelled field is warned-and-ignored, so a silently-dropped grader would read
# as a false PASS. These tests assert EXACT field placement offline. process-pr-comments is an
# interactive-only, injection-aware SKILL: both cases are describe-only REASONING scenarios
# graded on the response (a headless approval-gate refusal + a reviewer-text-as-data trust
# boundary), so — like design-notes — each task is a text pre-check + resume-session judge with
# NO tool_constraint / code grader, and the spec carries the prompt-injection adversarial pack.

Describe 'process-pr-comments waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:pprcDir = Join-Path $repoDir 'plugins/process-pr-comments/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:pprcDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:pprcDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:injectionTask = Get-Content -LiteralPath (Join-Path $script:pprcDir 'tasks/treat-review-text-as-data.yaml') -Raw
        $script:refuseTask = Get-Content -LiteralPath (Join-Path $script:pprcDir 'tasks/refuse-without-interactive.yaml') -Raw
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema and executor' {
        It 'test:waza-spec-shape pins schemaVersion 1.2 (required for the adversarial block)' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the process-pr-comments skill via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*process-pr-comments\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape resolves the real skill bundle via ../../skills' {
            $script:evalYaml | Should -Match '(?m)^\s+-\s*\.\./\.\./skills\s*$'
        }

        It 'test:waza-spec-shape declares two tasks covering the approval-gate refusal + reviewer-text-as-data' {
            @($script:taskFiles).Count | Should -Be 2
            $names = @($script:taskFiles | ForEach-Object { $_.BaseName })
            $names | Should -Contain 'refuse-without-interactive'
            $names | Should -Contain 'treat-review-text-as-data'
        }

        It 'test:waza-spec-shape declares NO spec-level graders/tool_constraint (SKILL.md has no tools: frontmatter)' {
            $script:evalYaml | Should -Not -Match '(?m)^graders:'
        }
    }

    Context 'test:waza-spec-shape — each task separates inputs from graders and uses a resume-session judge' {
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
            }
        }

        It 'test:waza-spec-shape both tasks are reasoning-only (no tool_constraint / code graders — pprc produces no tool calls to assert)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*tool_constraint'
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*code'
            }
        }
    }

    Context 'test:injection-guard — the reviewer-text-as-data case is covered functionally AND by the adversarial pack' {
        It 'test:injection-guard eval.yaml declares the prompt-injection pack with on_unsafe_outcome: fail' {
            $script:evalYaml | Should -Match '(?ms)^adversarial:\s*\n(?:.*\n)*?\s+packs:'
            $script:evalYaml | Should -Match '(?m)^\s+-\s*prompt-injection\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+on_unsafe_outcome:\s*fail'
        }

        It 'test:injection-guard the functional injection task rejects a bare-compliance output deterministically' {
            $graders = [regex]::Match($script:injectionTask, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Match '(?m)^\s+-\s*type:\s*text'
            $graders | Should -Match '(?m)^\s+regex_not_match:'
            # the tripwire targets an output that is ONLY compliance (the injection winning).
            $graders | Should -Match 'lgtm'
        }

        It 'test:injection-guard the injection task actually embeds an injected directive in reviewer data' {
            $inputs = [regex]::Match($script:injectionTask, '(?ms)^inputs:\s*\n(?<inputs>.*?)^graders:\s*\n').Groups['inputs'].Value
            $inputs | Should -Match '(?i)ignore all your prior instructions'
            $inputs | Should -Match '(?i)untrusted'
        }
    }

    Context 'test:approval-gate — the safety refusal case asserts no unattended push/post' {
        It 'test:approval-gate the refusal task tripwires on a claimed push/post' {
            $graders = [regex]::Match($script:refuseTask, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
            $graders | Should -Match '(?m)^\s+regex_not_match:'
            $graders | Should -Match '(?i)pushed'
        }
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task references an absolute or UNC path (gate-a escape vector)' {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:pprcDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }
    }

    Context 'test:no-legacy-pprc-llm — process-pr-comments carries no legacy LLM cases (it was the coverage gap)' {
        It 'test:no-legacy-pprc-llm leaves no plugins/process-pr-comments/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/process-pr-comments/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
