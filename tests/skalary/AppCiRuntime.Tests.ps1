#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'App CI retained runtime contracts' {
    BeforeAll {
        $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:container = Get-Content (Join-Path $script:repo 'plugins\autopilot\scripts\container-entrypoint.sh') -Raw
        $script:sandbox = Get-Content (Join-Path $script:repo 'plugins\autopilot\scripts\launch-sandbox.ps1') -Raw
        $script:containerLaunch = Get-Content (Join-Path $script:repo 'plugins\autopilot\scripts\launch-container.ps1') -Raw
    }
    It 'test:AppCi.EnvironmentDispatch binds one isolated target without legacy PR handoff' {
        $container | Should -Match 'TARGET_OUTPUT=\$\(app_worker_target'
        $container | Should -Match 'never enter the legacy PR-close/resume loop'
        $container | Should -Match 'APP_CI_WORKER'
        $sandbox | Should -Match "app-phase' -and .*phase -ne"
        $sandbox | Should -Match 'App CI worker'
        $sandbox | Should -Match 'No worker PR'
    }
    It 'test:AppCi.RetainedIsolatedRuntimes preserves transport and bounded outcome distinctions' {
        $container | Should -Match 'returning operator action'
        $container | Should -Match 'EXIT_CODE=42'
        $containerLaunch | Should -Match "app-phase', 'app-finalization"
        $containerLaunch | Should -Match 'Record-AiCreditUsage.ps1'
        $containerLaunch | Should -Match 'Retaining'
        $sandbox | Should -Match 'App source HEAD mismatch'
        $sandbox | Should -Match 'lost expected-start ancestry'
        $sandbox | Should -Match 'runExitCode = 43'
    }
    It 'refuses altered settings before starting Docker or Windows Sandbox' {
        $config = [pscustomobject]@{ model = 'wrong'; context = 'default'; reasoningEffort = 'high' }
        foreach ($name in @('launch-container.ps1', 'launch-sandbox.ps1')) {
            { & (Join-Path $script:repo "plugins\autopilot\scripts\$name") `
                -PlanSlug fixture -Mode app-phase -Phase 1 -Config $config -Token fixture `
                -ExpectedStartCommit ('a' * 40) } | Should -Throw '*Sol high/default*'
        }
    }
    It 'test:AppCi.EpicLocalExecution retains app local archive proof and the non-app wrapper' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'Get-EpicRollup'
        $guide | Should -Match 'committed archive, not a child PR'
        $guide | Should -Match 'Each child must finalize/archive once'
        $guide | Should -Match 'all-child-archives resume still performs pending epic completion'
        $guide | Should -Match 'Retained VS Code epic wrapper/provider proof remains unchanged'
    }
    It 'test:AppCi.UnattendedDecisions binds the requested log without granting criteria authority' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'assets/unattended-decissions.md'
        $guide | Should -Match 'step/criterion, choice, rationale and consequence'
        $guide | Should -Match 'confinement and\s+secret screening'
        $guide | Should -Match 'only between worker intervals'
        $guide | Should -Match 'cannot\s+override confirmed criteria'
        $guide | Should -Match 'Present decisions/blockers on exhaustion'
    }
}
