#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Invoke-WazaEvals' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $scriptFile = Join-Path $repoDir 'scripts/skalary/Invoke-WazaEvals.ps1'
        . $scriptFile
        $script:repoDir = $repoDir
    }

    Context 'test:executed-count-invariant — zero executed is a distinct non-green outcome' {
        It 'test:executed-count-invariant treats zero executed as red exit 3, not green' {
            $o = Get-ExecutedOutcome -Executed 0 -Failed 0 -Skipped 2
            $o.Outcome | Should -Be 'red'
            $o.ExitCode | Should -Be 3
        }

        It 'test:executed-count-invariant treats zero executed with empty discovery as red exit 3' {
            $o = Get-ExecutedOutcome -Executed 0 -Failed 0 -Skipped 0
            $o.ExitCode | Should -Be 3
            $o.Reason | Should -Match 'discovery'
        }

        It 'test:executed-count-invariant is red exit 1 when an executed eval fails' {
            $o = Get-ExecutedOutcome -Executed 3 -Failed 1
            $o.Outcome | Should -Be 'red'
            $o.ExitCode | Should -Be 1
        }

        It 'test:executed-count-invariant is green exit 0 when all executed evals pass' {
            $o = Get-ExecutedOutcome -Executed 3 -Failed 0
            $o.Outcome | Should -Be 'green'
            $o.ExitCode | Should -Be 0
        }
    }

    Context 'test:token-segregation — durable PATs never reach adversarial specs' {
        It 'test:token-segregation runs a normal spec with any source (including a credmanager PAT)' {
            $c = Resolve-SpecTokenSource -IsAdversarial $false -BaseSource 'credmanager:copilot-eval' -BaseToken 'pat-123'
            $c.ShouldSkip | Should -BeFalse
            $c.Token | Should -Be 'pat-123'
        }

        It 'test:token-segregation excludes a credmanager PAT from an adversarial spec' {
            $c = Resolve-SpecTokenSource -IsAdversarial $true -BaseSource 'credmanager:copilot-eval' -BaseToken 'pat-123'
            $c.ShouldSkip | Should -BeTrue
            $c.Token | Should -BeNullOrEmpty
            $c.Reason | Should -Match 'REQ-22'
        }

        It 'test:token-segregation excludes an ambient env PAT from an adversarial spec' {
            $c = Resolve-SpecTokenSource -IsAdversarial $true -BaseSource 'ambient' -BaseToken 'pat-abc'
            $c.ShouldSkip | Should -BeTrue
            $c.Token | Should -BeNullOrEmpty
            $c.Reason | Should -Match 'REQ-22'
        }

        It 'test:token-segregation allows a short-lived gh token on an adversarial spec' {
            $c = Resolve-SpecTokenSource -IsAdversarial $true -BaseSource 'gh' -BaseToken 'gh-tok'
            $c.ShouldSkip | Should -BeFalse
            $c.Token | Should -Be 'gh-tok'
        }

        It 'test:token-segregation skips when no token is available' {
            $c = Resolve-SpecTokenSource -IsAdversarial $false -BaseSource 'gh' -BaseToken ''
            $c.ShouldSkip | Should -BeTrue
        }
    }

    Context 'test:runner-selectors — discovery filters and argument building' {
        BeforeAll {
            $script:fakeRoot = Join-Path $TestDrive 'plugins'
            foreach ($p in @('code-review', 'design-review')) {
                $dir = Join-Path $script:fakeRoot (Join-Path $p 'evals/waza')
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $dir 'eval.yaml') -Value "skill: $p" -Encoding utf8NoBOM
            }
            # A stray eval.yaml NOT under evals/waza must be ignored.
            $stray = Join-Path $script:fakeRoot 'other/eval.yaml'
            New-Item -ItemType Directory -Path (Split-Path -Parent $stray) -Force | Out-Null
            Set-Content -LiteralPath $stray -Value 'skill: nope' -Encoding utf8NoBOM
        }

        It 'test:runner-selectors discovers only plugins NAME evals waza eval.yaml' {
            $specs = @(Get-WazaEvalSpec -PluginsRoot $script:fakeRoot)
            $specs.Count | Should -Be 2
            $hasStray = $false
            foreach ($s in $specs) {
                if ($s.Replace('\', '/') -match '/other/') { $hasStray = $true }
            }
            $hasStray | Should -BeFalse
        }

        It 'test:runner-selectors filters discovery by -Plugin' {
            $specs = @(Get-WazaEvalSpec -PluginsRoot $script:fakeRoot -Plugin 'code-review')
            $specs.Count | Should -Be 1
            $specs[0].Replace('\', '/') | Should -Match '/code-review/evals/waza/eval\.yaml$'
        }

        It 'test:runner-selectors builds a normal run with --trials 1 under -Quick and --task under -Case' {
            $a = New-WazaRunArgument -SpecPath 'e.yaml' -OutputDir 'out' -Quick -Case 'my-case'
            $a[0] | Should -Be 'run'
            ($a -join ' ') | Should -Match '--trials 1'
            ($a -join ' ') | Should -Match '--task my-case'
        }

        It 'test:runner-selectors builds an adversarial run with --on-unsafe-outcome fail (no trials/task)' {
            $a = New-WazaRunArgument -SpecPath 'e.yaml' -OutputDir 'out' -IsAdversarial -Quick -Case 'x'
            $a[0] | Should -Be 'adversarial'
            ($a -join ' ') | Should -Match '--on-unsafe-outcome fail'
            ($a -join ' ') | Should -Not -Match '--trials'
            ($a -join ' ') | Should -Not -Match '--task'
        }

        It 'test:runner-selectors extracts changed plugin names from git paths' {
            $names = Select-ChangedPlugin -ChangedPaths @('plugins/code-review/agents/cr.agent.md', 'scripts/x.ps1', 'plugins/code-review/evals/waza/eval.yaml')
            $names | Should -Be @('code-review')
        }

        It 'test:runner-selectors detects a top-level adversarial block' {
            $adv = Join-Path $TestDrive 'adv.yaml'
            "skill: cr`nadversarial:`n  packs:`n    - prompt-injection" | Set-Content -LiteralPath $adv -Encoding utf8NoBOM
            Test-WazaSpecIsAdversarial -Path $adv | Should -BeTrue

            $plain = Join-Path $TestDrive 'plain.yaml'
            "skill: cr`n# adversarial: commented`ntasks: []" | Set-Content -LiteralPath $plain -Encoding utf8NoBOM
            Test-WazaSpecIsAdversarial -Path $plain | Should -BeFalse
        }
    }

    Context 'test:runner-both-modes — a spec with tasks AND an adversarial block runs both' {
        BeforeAll {
            $script:bothSpec = Join-Path $TestDrive 'both.yaml'
            @(
                'skill: cr'
                'config:'
                '  executor: copilot-sdk'
                '  model: claude-sonnet-4.6'
                '  judge_model: claude-sonnet-4.6'
                'tasks:'
                '  - tasks/*.yaml'
                'adversarial:'
                '  packs:'
                '    - prompt-injection'
                '  on_unsafe_outcome: fail'
            ) -join "`n" | Set-Content -LiteralPath $script:bothSpec -Encoding utf8NoBOM
        }

        It 'test:runner-both-modes detects functional tasks and the adversarial block' {
            Test-WazaSpecHasTasks -Path $script:bothSpec | Should -BeTrue
            Test-WazaSpecIsAdversarial -Path $script:bothSpec | Should -BeTrue
        }

        It 'test:runner-both-modes plans run THEN adversarial for a both-signal spec' {
            $plan = @(Get-WazaSpecExecutionPlan -HasTasks $true -HasAdversarial $true)
            $plan | Should -Be @('run', 'adversarial')
        }

        It 'test:runner-both-modes plans run-only when there is no adversarial block' {
            (@(Get-WazaSpecExecutionPlan -HasTasks $true -HasAdversarial $false)) | Should -Be @('run')
        }

        It 'test:runner-both-modes plans adversarial-only when there are no tasks' {
            (@(Get-WazaSpecExecutionPlan -HasTasks $false -HasAdversarial $true)) | Should -Be @('adversarial')
        }

        It 'test:runner-both-modes plans nothing for an empty spec' {
            (@(Get-WazaSpecExecutionPlan -HasTasks $false -HasAdversarial $false)).Count | Should -Be 0
        }

        It 'test:runner-both-modes parses skill and model for the adversarial forward-flags' {
            Get-WazaSpecSkill -Path $script:bothSpec | Should -Be 'cr'
            # config.model, not judge_model
            Get-WazaSpecModel -Path $script:bothSpec | Should -Be 'claude-sonnet-4.6'
        }

        It 'test:runner-both-modes builds adversarial args with --spec/--skill/--model and a file --output' {
            $a = New-WazaRunArgument -SpecPath 'e.yaml' -OutputDir 'out' -IsAdversarial -Skill 'cr' -Model 'claude-sonnet-4.6'
            $joined = $a -join ' '
            $joined | Should -Match '--spec e\.yaml'
            $joined | Should -Match '--skill cr'
            $joined | Should -Match '--model claude-sonnet-4\.6'
            $joined | Should -Match '--on-unsafe-outcome fail'
            $joined | Should -Match '--output '
            $joined | Should -Not -Match '--output-dir'
        }

        It 'test:runner-both-modes omits --skill/--model when they cannot be resolved' {
            $a = New-WazaRunArgument -SpecPath 'e.yaml' -OutputDir 'out' -IsAdversarial
            ($a -join ' ') | Should -Not -Match '--skill'
            ($a -join ' ') | Should -Not -Match '--model'
        }
    }

    Context 'test:gate-isolation — the waza runner is never wired into always-on gates' {
        BeforeAll {
            $script:pkg = Get-Content -LiteralPath (Join-Path $script:repoDir 'package.json') -Raw | ConvertFrom-Json
            $script:validate = Get-Content -LiteralPath (Join-Path $script:repoDir 'scripts/validate.ps1') -Raw
        }

        It 'test:gate-isolation keeps Invoke-WazaEvals/eval:llm out of build, test, and eval scripts' {
            foreach ($name in @('build', 'test', 'eval')) {
                $script:pkg.scripts.$name | Should -Not -Match 'Invoke-WazaEvals'
                $script:pkg.scripts.$name | Should -Not -Match 'eval:llm'
            }
        }

        It 'test:gate-isolation keeps waza out of scripts/validate.ps1' {
            $script:validate | Should -Not -Match 'waza'
            $script:validate | Should -Not -Match 'Invoke-WazaEvals'
        }
    }
}
