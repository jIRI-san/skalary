#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Resolve-EvalToken' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $scriptFile = Join-Path $repoDir 'scripts/skalary/Resolve-EvalToken.ps1'
        . $scriptFile

        # These tests blanked the token vars rather than restoring them, so running the suite in a
        # shell that had GH_TOKEN set left gh unauthenticated afterwards.
        $script:envSnapshot = @{}
        foreach ($name in @('COPILOT_GITHUB_TOKEN', 'GH_TOKEN')) {
            $script:envSnapshot[$name] = [Environment]::GetEnvironmentVariable($name)
        }
    }

    AfterAll {
        foreach ($name in @($script:envSnapshot.Keys)) {
            $value = $script:envSnapshot[$name]
            # $null binds to SetEnvironmentVariable's string parameter as '', which creates the
            # variable empty rather than removing it.
            if ($null -eq $value) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $value)
            }
        }
    }

    Context 'test:resolvetoken-precedence — pure source selection' {
        It 'test:resolvetoken-precedence prefers gh over ambient and credential manager' {
            $d = Resolve-EvalTokenSource -GhToken 'gh-tok' -AmbientToken 'amb-tok' -StoreToken 'cred-tok' -StoreTarget 'copilot-eval'
            $d.Source | Should -Be 'gh'
            $d.Token | Should -Be 'gh-tok'
            $d.ShouldSkip | Should -BeFalse
        }

        It 'test:resolvetoken-precedence falls back to ambient when gh is empty' {
            $d = Resolve-EvalTokenSource -GhToken '' -AmbientToken 'amb-tok' -StoreToken 'cred-tok' -StoreTarget 'copilot-eval'
            $d.Source | Should -Be 'ambient'
            $d.Token | Should -Be 'amb-tok'
        }

        It 'test:resolvetoken-precedence falls back to credential manager when gh and ambient are empty' {
            $d = Resolve-EvalTokenSource -GhToken '' -AmbientToken '' -StoreToken 'cred-tok' -StoreTarget 'copilot-autopilot'
            $d.Source | Should -Be 'credmanager:copilot-autopilot'
            $d.Token | Should -Be 'cred-tok'
        }

        It 'test:resolvetoken-precedence skips with an actionable reason when nothing resolves' {
            $d = Resolve-EvalTokenSource -GhToken '' -AmbientToken '' -StoreToken ''
            $d.ShouldSkip | Should -BeTrue
            $d.Source | Should -BeNullOrEmpty
            $d.Token | Should -BeNullOrEmpty
            $d.Reason | Should -Match 'gh auth login'
        }

        It 'test:resolvetoken-precedence trims surrounding whitespace on the winning token' {
            $d = Resolve-EvalTokenSource -GhToken "  spaced-tok`n" -AmbientToken ''
            $d.Token | Should -Be 'spaced-tok'
        }
    }

    Context 'test:resolvetoken-precedence — ambient env reader' {
        It 'test:resolvetoken-precedence reads COPILOT_GITHUB_TOKEN first' {
            $env:COPILOT_GITHUB_TOKEN = 'copilot-env'
            $env:GH_TOKEN = 'gh-env'
            try {
                Get-EvalAmbientToken | Should -Be 'copilot-env'
            }
            finally {
                $env:COPILOT_GITHUB_TOKEN = ''
                $env:GH_TOKEN = ''
            }
        }

        It 'test:resolvetoken-precedence falls back to GH_TOKEN' {
            $env:COPILOT_GITHUB_TOKEN = ''
            $env:GH_TOKEN = 'gh-env'
            try {
                Get-EvalAmbientToken | Should -Be 'gh-env'
            }
            finally {
                $env:GH_TOKEN = ''
            }
        }

        It 'test:resolvetoken-precedence returns empty when neither env var is set' {
            $env:COPILOT_GITHUB_TOKEN = ''
            $env:GH_TOKEN = ''
            Get-EvalAmbientToken | Should -Be ''
        }
    }

    Context 'test:resolvetoken-precedence — credential-target config resolution' {
        It 'test:resolvetoken-precedence defaults to copilot-eval then copilot-autopilot when config is absent' {
            $missing = Join-Path $TestDrive 'nope.json'
            $targets = Get-EvalTokenTargets -ConfigPath $missing
            $targets | Should -Be @('copilot-eval', 'copilot-autopilot')
        }

        It 'test:resolvetoken-precedence honours an explicit credentialTargets array' {
            $cfg = Join-Path $TestDrive 'multi.json'
            '{ "credentialTargets": ["a-target", "b-target"] }' | Set-Content -LiteralPath $cfg -Encoding utf8NoBOM
            $targets = Get-EvalTokenTargets -ConfigPath $cfg
            $targets | Should -Be @('a-target', 'b-target')
        }

        It 'test:resolvetoken-precedence honours a single legacy credentialTarget' {
            $cfg = Join-Path $TestDrive 'single.json'
            '{ "credentialTarget": "solo-target" }' | Set-Content -LiteralPath $cfg -Encoding utf8NoBOM
            $targets = Get-EvalTokenTargets -ConfigPath $cfg
            $targets | Should -Be @('solo-target')
        }
    }

    Context 'test:resolvetoken-precedence — gh source helper' {
        It 'test:resolvetoken-precedence returns empty when gh is not installed' {
            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'gh' }
            Get-EvalGhToken | Should -Be ''
        }
    }

    Context 'test:resolvetoken-precedence — orchestrator wiring and env export' {
        It 'test:resolvetoken-precedence exports the resolved token to the process env' {
            $env:COPILOT_GITHUB_TOKEN = ''
            $env:GH_TOKEN = ''
            Mock -CommandName Get-EvalGhToken -MockWith { '' }
            Mock -CommandName Get-EvalCredManagerToken -MockWith { [pscustomobject]@{ Token = 'cred-win'; Target = 'copilot-eval' } }
            Mock -CommandName Get-EvalTokenTargets -MockWith { @('copilot-eval') }

            $d = Resolve-EvalToken -RepoRoot $TestDrive
            try {
                $d.Source | Should -Be 'credmanager:copilot-eval'
                $env:COPILOT_GITHUB_TOKEN | Should -Be 'cred-win'
                $env:GH_TOKEN | Should -Be 'cred-win'
            }
            finally {
                $env:COPILOT_GITHUB_TOKEN = ''
                $env:GH_TOKEN = ''
            }
        }

        It 'test:resolvetoken-precedence leaves env untouched and skips when no source resolves' {
            $env:COPILOT_GITHUB_TOKEN = ''
            $env:GH_TOKEN = ''
            Mock -CommandName Get-EvalGhToken -MockWith { '' }
            Mock -CommandName Get-EvalCredManagerToken -MockWith { [pscustomobject]@{ Token = ''; Target = $null } }
            Mock -CommandName Get-EvalTokenTargets -MockWith { @('copilot-eval') }

            $d = Resolve-EvalToken -RepoRoot $TestDrive
            $d.ShouldSkip | Should -BeTrue
            $env:COPILOT_GITHUB_TOKEN | Should -Be ''
        }
    }
}

