#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped architecture-notes waza convention. waza fails OPEN — a
# misplaced or misspelled field is warned-and-ignored, so a silently-dropped grader would read
# as a false PASS. These tests assert EXACT field placement offline. All three cases are
# describe-only REASONING / safety-discipline scenarios graded on the response (author a draft
# contract, review the tier, refuse an autonomous lock), so — like design-notes/cip/autopilot —
# each task pairs a resume-session judge with a deterministic text pre-check graded at the draft
# turn (checkpoints after_turn: 1) and NO tool_constraint / code grader (the architecture-notes
# SKILL.md frontmatter declares no `tools:` field, so waza auto-injects nothing to assert).

Describe 'architecture-notes waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:anDir = Join-Path $repoDir 'plugins/architecture-notes/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:anDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:anDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema and executor' {
        It 'test:waza-spec-shape pins schemaVersion 1.2' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the architecture-notes skill via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*architecture-notes\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*claude-sonnet-4\.6'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape resolves the real skill bundle via ../../skills' {
            $script:evalYaml | Should -Match '(?m)^\s+-\s*\.\./\.\./skills\s*$'
        }

        It 'test:waza-spec-shape declares three tasks covering create/review/lock-refusal' {
            @($script:taskFiles).Count | Should -Be 3
            $names = @($script:taskFiles | ForEach-Object { $_.BaseName })
            $names | Should -Contain 'author-draft-contract'
            $names | Should -Contain 'review-tier-drift'
            $names | Should -Contain 'refuse-autonomous-lock'
        }

        It 'test:waza-spec-shape declares NO adversarial block (all cases are functional)' {
            $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
        }

        It 'test:waza-spec-shape declares NO spec-level graders/tool_constraint (SKILL.md has no tools: frontmatter)' {
            $script:evalYaml | Should -Not -Match '(?m)^graders:'
        }
    }

    Context 'test:waza-spec-shape — each task separates inputs from graders and uses a resume-session judge' {
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

        It 'test:waza-spec-shape each task grades a deterministic text pre-check at the draft turn (checkpoints after_turn: 1)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $cp = [regex]::Match($raw, '(?ms)^checkpoints:\s*\n(?<cp>.*?)^graders:\s*\n')
                $cp.Success | Should -BeTrue
                $cpBlock = $cp.Groups['cp'].Value
                $cpBlock | Should -Match '(?ms)^\s+-\s*after_turn:\s*1\s*\n.*?^\s+graders:\s*$.*?^\s+-\s*type:\s*text\b.*?^\s+regex_match:'
            }
        }

        It 'test:waza-spec-shape the final-turn graders block has NO text grader (the pre-check moved to the draft-turn checkpoint)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*text'
            }
        }

        It 'test:waza-spec-shape all tasks are reasoning-only (no tool_constraint / code graders — architecture-notes produces no tool calls to assert)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*tool_constraint'
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*code'
            }
        }
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task references an absolute or UNC path (gate-a escape vector)' {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:anDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }
    }

    Context 'test:no-legacy-architecture-notes-llm — the tier ships waza, never legacy llm JSON' {
        It 'test:no-legacy-architecture-notes-llm leaves no plugins/architecture-notes/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/architecture-notes/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
