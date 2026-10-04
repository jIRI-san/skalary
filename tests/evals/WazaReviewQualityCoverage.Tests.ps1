#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Review quality Waza catalog' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:catalogPath = Join-Path $script:repoRoot 'docs/design-notes/architecture/plugin-evals.design.md'
        $script:suites = [ordered]@{
            cip       = 'plugins/create-implementation-plan/evals/waza/tasks'
            cr        = 'plugins/code-review/evals/waza/tasks'
            dr        = 'plugins/design-review/evals/waza/tasks'
            ci        = 'plugins/continue-implementation/evals/waza/tasks'
            autopilot = 'plugins/autopilot/evals/waza/tasks'
        }
        $script:taskFiles = @(
            foreach ($plugin in $script:suites.Keys) {
                Get-ChildItem -LiteralPath (Join-Path $script:repoRoot $script:suites[$plugin]) -File -Filter '*.yaml' |
                    Sort-Object Name
            }
        )
        $script:catalogRows = @(
            [regex]::Matches(
                [System.IO.File]::ReadAllText($script:catalogPath),
                '(?m)^\| (?<plugin>cip|cr|dr|ci|autopilot) \| `(?<id>[a-z0-9-]+)` \|'
            ) | ForEach-Object {
                '{0}/{1}' -f $_.Groups['plugin'].Value, $_.Groups['id'].Value
            }
        )
    }

    It 'test:ReviewQuality.EvalCoverage includes exactly 16 declared task YAMLs' {
        $script:taskFiles.Count | Should -Be 16
        $actualRows = @(
            foreach ($file in $script:taskFiles) {
                $raw = [System.IO.File]::ReadAllText($file.FullName)
                $id = [regex]::Match($raw, '(?m)^id:\s*(?<id>[a-z0-9-]+)\s*$').Groups['id'].Value
                $relative = $file.FullName.Substring($script:repoRoot.Length).TrimStart('\', '/')
                $plugin = ($relative -split '[\\/]', 4)[1]
                $plugin = switch ($plugin) {
                    'create-implementation-plan' { 'cip' }
                    'code-review' { 'cr' }
                    'design-review' { 'dr' }
                    'continue-implementation' { 'ci' }
                    default { $plugin }
                }
                '{0}/{1}' -f $plugin, $id
            }
        )
        $actualRows.Count | Should -Be 16
        $script:catalogRows.Count | Should -Be 16
        (($actualRows | Sort-Object) -join "`n") | Should -Be (($script:catalogRows | Sort-Object) -join "`n")
        @($actualRows | Sort-Object -Unique).Count | Should -Be 16
    }

    It 'test:ReviewQuality.EvalCoverage classifies every case and uses only calibrated subjective graders' {
        foreach ($file in $script:taskFiles) {
            $raw = [System.IO.File]::ReadAllText($file.FullName)
            $raw | Should -Match '(?m)^# ai-credit-disposition: (deterministic|subjective)\r?$' -Because $file.Name
            $graderBlock = [regex]::Match($raw, '(?ms)^graders:\s*\n(?<block>.*)$').Groups['block'].Value
            $graderBlock | Should -Match '(?m)^\s+-\s*type:\s*text' -Because $file.Name
            $promptCount = [regex]::Matches($graderBlock, '(?m)^\s+-\s*type:\s*prompt\s*$').Count
            if ($raw -match '(?m)^# ai-credit-disposition: subjective\r?$') {
                $promptCount | Should -Be 1 -Because $file.Name
                $graderBlock | Should -Match '(?m)^\s+continue_session:\s*true' -Because $file.Name
                $graderBlock | Should -Match '(?m)^\s+model:\s*gpt-5\.6-terra' -Because $file.Name
                $graderBlock | Should -Match '(?i)set_waza_grade_pass ONLY' -Because $file.Name
                $graderBlock | Should -Match '(?i)set_waza_grade_fail' -Because $file.Name
            }
            else {
                $promptCount | Should -Be 0 -Because $file.Name
            }
        }
    }

    It 'test:ReviewQuality.EvalCoverage asserts paired semantic outcomes instead of keywords alone' {
        $pairedAssertions = [ordered]@{
            'plugins/create-implementation-plan/evals/waza/tasks/capture-consequential-ambiguity.yaml' = @(
                'two materially different meanings', 'authorized bounded discretion', 'must not', 'claim either refresh meaning'
            )
            'plugins/create-implementation-plan/evals/waza/tasks/reconcile-history-without-veto.yaml' = @(
                'relevant active migration plan', 'billing-notification plan', 'unindexed legacy location', 'does not veto'
            )
            'plugins/code-review/evals/waza/tasks/cross-file-guarded-null-review.yaml' = @(
                'real defect', 'ProfileCard.RenderAvatar', 'explicit null check'
            )
            'plugins/design-review/evals/waza/tasks/intent-drift-vs-open-choice.yaml' = @(
                'video/document preview expansion', 'maximum image size as intentionally open'
            )
            'plugins/design-review/evals/waza/tasks/versioned-docs-and-local-contract.yaml' = @(
                '3.1.0', '2.4.2', 'untrusted data', 'chunk size of 200 as a defect', 'excluded legacy script'
            )
            'plugins/continue-implementation/evals/waza/tasks/stop-for-runtime-intent-choice.yaml' = @(
                '42', 'external guest', 'authorized bounded discretion'
            )
        }

        foreach ($relativePath in $pairedAssertions.Keys) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $relativePath))
            foreach ($assertion in $pairedAssertions[$relativePath]) {
                $raw | Should -Match ([regex]::Escape($assertion)) -Because "$relativePath must encode both intended and rejected outcomes"
            }
        }
    }

    It 'test:ReviewQuality.EvalCoverage keeps fixtures local, bounded, and free of absolute paths' {
        foreach ($file in $script:taskFiles) {
            $raw = [System.IO.File]::ReadAllText($file.FullName)
            $inputs = [regex]::Match($raw, '(?ms)^inputs:\s*\n(?<inputs>.*?)^graders:\s*\n').Groups['inputs'].Value
            if ($inputs -match '(?m)^\s+context:') {
                $fixture = [regex]::Match($inputs, '(?m)^\s+fixture:\s*(?<path>fixtures/[^\s]+)').Groups['path'].Value
                $fixture | Should -Not -BeNullOrEmpty -Because $file.Name
                $suiteDirectory = Split-Path -Parent $file.DirectoryName
                Test-Path -LiteralPath (Join-Path $suiteDirectory $fixture) | Should -BeTrue -Because $file.Name
            }
            $raw | Should -Not -Match '[A-Za-z]:\\'
            $raw | Should -Not -Match '\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9]'
        }
    }
}
