#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Fail-closed guards for the shipped design-notes waza convention. waza fails OPEN — a
# misplaced or misspelled field is warned-and-ignored, so a silently-dropped grader would read
# as a false PASS. These tests assert EXACT field placement offline. All three ported
# design-notes cases are describe-only REASONING scenarios graded on the response (bootstrap
# scaffold, create a design note, update notes), so — like cip/autopilot — each task pairs a
# resume-session judge with a deterministic text pre-check and NO tool_constraint / code grader.
#
# 5.1 live-sweep refinement: the deterministic text pre-check is graded at the DRAFT turn via a
# `checkpoints: after_turn: 1` block, NOT against final_output. The structured draft names the
# graded concepts verbatim, but the terse follow-up confirmation paraphrases them ("eval" ->
# "harness", "transcript" -> "capture"), which made a final_output text grader flake run-to-run.
# Grading the draft turn is deterministic; the judge still runs (continue_session) at the final
# turn. The update task also copies an EXISTING note fixture into the workspace so its Update
# workflow has a real file to edit (otherwise the empty workspace makes the judge flake).

Describe 'design-notes waza convention' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:dnDir = Join-Path $repoDir 'plugins/design-notes/evals/waza'
        $script:evalYaml = Get-Content -LiteralPath (Join-Path $script:dnDir 'eval.yaml') -Raw
        $script:taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:dnDir 'tasks') -Filter '*.yaml' | Sort-Object Name)
        $script:repoDir = $repoDir
    }

    Context 'test:waza-spec-shape — eval.yaml declares the pinned schema and executor' {
        It 'test:waza-spec-shape pins schemaVersion 1.2' {
            $script:evalYaml | Should -Match '(?m)^schemaVersion:\s*"1\.2"'
        }

        It 'test:waza-spec-shape targets the design-notes skill via copilot-sdk with pinned model + judge_model' {
            $script:evalYaml | Should -Match '(?m)^skill:\s*design-notes\s*$'
            $script:evalYaml | Should -Match '(?m)^\s+executor:\s*copilot-sdk'
            $script:evalYaml | Should -Match '(?m)^\s+model:\s*gpt-5\.6-luna'
            $script:evalYaml | Should -Match '(?m)^\s+judge_model:\s*gpt-5\.6-terra'
            $script:evalYaml | Should -Match '(?m)^\s+skill_directories:'
        }

        It 'test:waza-spec-shape resolves the real skill bundle via ../../skills' {
            $script:evalYaml | Should -Match '(?m)^\s+-\s*\.\./\.\./skills\s*$'
        }

        It 'test:waza-spec-shape declares three tasks covering init/create/update' {
            @($script:taskFiles).Count | Should -Be 3
            $names = @($script:taskFiles | ForEach-Object { $_.BaseName })
            $names | Should -Contain 'bootstrap-scaffold'
            $names | Should -Contain 'create-design-note'
            $names | Should -Contain 'update-design-note'
        }

        It 'test:waza-spec-shape declares NO adversarial block (all cases are functional)' {
            $script:evalYaml | Should -Not -Match '(?m)^adversarial:'
        }

        It 'test:waza-spec-shape declares NO spec-level graders/tool_constraint (SKILL.md has no tools: frontmatter)' {
            $script:evalYaml | Should -Not -Match '(?m)^graders:'
        }
    }

    Context 'test:waza-spec-shape — each task separates inputs from graders and uses a resume-session judge' {
        # Fail-open defence: split each task at the col-0 `inputs:`/`graders:` keys and assert the
        # forced-turn lives in the inputs block and graders live in the graders block, so a
        # misspelled/mis-nested parent key cannot silently drop graders and pass green.
        It 'test:waza-spec-shape each task has inputs and an explicit disposition' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Match '(?m)^inputs:'
                $raw | Should -Match '(?m)^# ai-credit-disposition: (deterministic|subjective)$'
            }
        }

        It 'test:waza-spec-shape the forced turn is nested inside the inputs block' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $m = [regex]::Match($raw, '(?ms)^inputs:\s*\n(?<inputs>.*?)(?:^checkpoints:|^graders:)')
                $m.Success | Should -BeTrue
                $m.Groups['inputs'].Value | Should -Match '(?m)^\s+follow_up_prompts:'
            }
        }

        It 'test:waza-spec-shape uses Terra judgment only for subjective tasks' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                if ($raw -match '(?m)^# ai-credit-disposition: subjective$') {
                    $graders | Should -Match '(?m)^\s+-\s*type:\s*prompt'
                    $graders | Should -Match '(?m)^\s+continue_session:\s*true'
                    $graders | Should -Match '(?m)^\s+model:\s*gpt-5\.6-terra'
                }
                else {
                    $raw | Should -Not -Match '(?m)^\s+-\s*type:\s*prompt'
                }
            }
        }

        It 'test:waza-spec-shape each task grades a deterministic text pre-check at the draft turn (checkpoints after_turn: 1)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                # The checkpoints block sits between the inputs and the (final-turn) graders block.
                $cp = [regex]::Match($raw, '(?ms)^checkpoints:\s*\n(?<cp>.*?)(?:^graders:\s*\n|\z)')
                $cp.Success | Should -BeTrue
                $cpBlock = $cp.Groups['cp'].Value
                # Assert the exact nesting after_turn -> graders -> text -> regex_match in sequence.
                # waza fails OPEN on a misplaced/misspelled field, so a dropped nested `graders:`
                # key would silently drop the pre-check yet still leave `- type: text` textually
                # present; anchoring on the nested `graders:` key guards that false-PASS mode.
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

        It 'test:waza-spec-shape all tasks are reasoning-only (no tool_constraint / code graders — design-notes produces no tool calls to assert)' {
            foreach ($f in $script:taskFiles) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $graders = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<graders>.*)$').Groups['graders'].Value
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*tool_constraint'
                $graders | Should -Not -Match '(?m)^\s+-\s*type:\s*code'
            }
        }

        It 'test:waza-spec-shape the update task copies an existing-note fixture so its Update workflow has a real file to edit' {
            $updateFile = @($script:taskFiles | Where-Object { $_.BaseName -eq 'update-design-note' })[0]
            $updateFile | Should -Not -BeNullOrEmpty
            $raw = Get-Content -LiteralPath $updateFile.FullName -Raw
            $raw | Should -Match '(?m)^\s+context:'
            $raw | Should -Match '(?m)^\s+fixture:\s*fixtures/existing-eval-note\.design\.md'
            $fixture = Join-Path $script:dnDir 'fixtures/existing-eval-note.design.md'
            Test-Path -LiteralPath $fixture | Should -BeTrue
        }
    }

    Context 'test:live-tree-clean — the convention cannot write outside a disposable workspace' {
        It 'test:live-tree-clean no spec/task references an absolute or UNC path (gate-a escape vector)' {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:dnDir -Recurse -File)) {
                $raw = Get-Content -LiteralPath $f.FullName -Raw
                $raw | Should -Not -Match '[A-Za-z]:\\'
                $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
            }
        }
    }

    Context 'test:no-legacy-design-notes-llm — the bespoke design-notes LLM cases are gone after cutover' {
        It 'test:no-legacy-design-notes-llm leaves no plugins/design-notes/evals/llm/*.eval.json' {
            $legacyDir = Join-Path $script:repoDir 'plugins/design-notes/evals/llm'
            $remaining = @()
            if (Test-Path -LiteralPath $legacyDir) {
                $remaining = @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.eval.json' -ErrorAction SilentlyContinue)
            }
            $remaining.Count | Should -Be 0
        }
    }
}
