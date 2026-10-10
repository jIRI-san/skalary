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
    It 'test:AppCi.ConsumerMigration retains legacy consumers and private app recovery' {
        $container | Should -Match 'no automatic staging/publication'
        $container | Should -Match 'SHARE_PATH="/tmp/autopilot-transcripts/'
        $containerLaunch | Should -Match 'NewGuid'
        $sandbox | Should -Match 'worker-result.bundle'
        $sandbox | Should -Match 'worker-recovery'
        $sandbox | Should -Match 'not auto-staged or published'
        $sandbox | Should -Match 'sharePath = if .*appWorker'
        Test-Path (Join-Path $script:repo 'plugins\autopilot\scripts\launch-host.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:repo '.github\skills\autopilot\scripts\Invoke-EpicAutopilot.ps1') | Should -BeTrue
        $containerLaunch | Should -Match 'import after checking out the verified worker head'
        $sandbox | Should -Match 'import after checking out the verified worker head'
    }
    It 'test:AppCi.SessionRetention preserves app sessions and retained cleanup semantics for <Mode>' -ForEach @(
        @{ Mode = 'app-phase'; RetainOld = $true }
        @{ Mode = 'app-finalization'; RetainOld = $true }
        @{ Mode = 'next-phase'; RetainOld = $false }
        @{ Mode = 'whole-plan'; RetainOld = $false }
    ) {
        foreach ($path in @('plugins\autopilot\scripts\launch.ps1', '.github\skills\autopilot\scripts\launch.ps1')) {
            $source = Get-Content (Join-Path $script:repo $path) -Raw
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
            $assignment = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$appWorker'
            }, $true)
            $assignment | Should -Not -BeNullOrEmpty
            $sweep = [regex]::Match($source, '(?s)# --- Sweep stale env files ---\s*(?<body>.*?)\s*# --- Get credentials ---')
            $sweep.Success | Should -BeTrue
            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $old = Join-Path $fixtureRoot 'autopilot-sessions\old-session'
            $recent = Join-Path $fixtureRoot 'autopilot-sessions\recent-session'
            New-Item -ItemType Directory -Path $old, $recent -Force | Out-Null
            Set-Content (Join-Path $old 'retained.txt') 'retained output'
            (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddHours(-48)
            $previousLocalAppData = $env:LOCALAPPDATA
            try {
                $env:LOCALAPPDATA = $fixtureRoot
                & ([scriptblock]::Create($assignment.Extent.Text + "`n" + $sweep.Groups['body'].Value))
                Test-Path -LiteralPath $old | Should -Be $RetainOld
                Test-Path -LiteralPath $recent | Should -BeTrue
                if ($RetainOld) {
                    Get-Content (Join-Path $old 'retained.txt') | Should -Be 'retained output'
                }
            }
            finally {
                $env:LOCALAPPDATA = $previousLocalAppData
            }
        }
    }
    It 'test:AppCi.RetainedIsolatedRuntimes parses the generated Sandbox bootstrap for each app target' {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($sandbox, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $assignment = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$bootstrapContent'
        }, $true)
        $assignment | Should -Not -BeNullOrEmpty
        $Config = [pscustomobject]@{
            model = 'gpt-6.1-sol'; context = 'default'; reasoningEffort = 'high'
            git = [pscustomobject]@{ name = 'Fixture'; email = 'fixture@example.invalid' }
        }
        $PlanSlug = 'standalone-2026-01-01-abc123-fixture'
        $Branch = 'app-worker'; $StartBranch = 'main'
        $ExpectedStartCommit = 'a' * 40; $TrustedInternalRetry = $false; $Phase = 1
        foreach ($Mode in @('app-phase', 'app-finalization')) {
            $generated = & ([scriptblock]::Create($assignment.Extent.Text + '; $bootstrapContent'))
            [System.Management.Automation.Language.Parser]::ParseInput($generated, [ref]$null, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
            $generated | Should -Match '-AllowIndependentAi 2>&1'
            $generated | Should -Match 'worker-recovery.patch'
        }
    }
    It 'test:AppCi.LocalHostReplacement keeps app local orchestration out of host and epic launchers' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'legacy `host` selection means native local'
        $guide | Should -Match 'do not change VS Code'
        $guide | Should -Match 'Do not invoke the competing host-only epic wrapper'
        $guide | Should -Not -Match 'launch-host\.ps1'
        $guide | Should -Match 'Only the coordinator owns delivery'
        $guide | Should -Match 'inspect an existing exact-run PR'
    }
    It 'test:AppCi.PreservationBoundaries keeps completion guards and explicit usage coverage' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'Human compaction,\s+deletion or push gates stop visibly'
        $guide | Should -Match 'Headless skips PFB'
        $guide | Should -Match 'run the required focused evidence locally'
        $guide | Should -Match 'Never fabricate native app usage'
        $guide | Should -Match 'Retain sidecars until accepted'
        $guide | Should -Match 'already finalized archived plans do not'
    }
    It 'test:AppCi.ClientCapabilityBoundary preserves version-pinned VS Code limits without an inheritance claim' {
        $note = Get-Content (Join-Path $script:repo 'docs\design-notes\architecture\autopilot-execution.design.md') -Raw
        $note | Should -Match '1.141'
        $note | Should -Match 'cannot prove exact worker settings'
        $note | Should -Match 'existing direct/host/epic/factory routes'
        $note | Should -Match 'human gates, not results inferred from static tests'
    }
    It 'test:AppCi.SingleCoordinator binds serial ownership and refuses recursive workers' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $skill = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\SKILL.md') -Raw
        $guide | Should -Match 'Use only one worker at a time'
        $guide | Should -Match 'If ownership is\s+ambiguous, stop with `42`'
        $skill | Should -Match 'Never recursively coordinate'
    }
    It 'test:AppCi.UnsupportedHost refuses missing native capability rather than silently changing isolation' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'require available native `create_session`, `get_session`'
        $guide | Should -Match 'Missing creation/observation'
        $guide | Should -Match 'stops with `42` before dispatch'
        $guide | Should -Match 'never simulate a full session'
        $guide | Should -Match 'do not turn selected isolation into a local fallback'
    }
    It 'test:AppCi.MaterialChoiceStop preserves criteria and routes consequential choices to reconfirmation' {
        $guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $guide | Should -Match 'Material choices stop affected work through CIP reconfirmation'
        $guide | Should -Match 'only\s+independently admitted unaffected work may continue'
        $guide | Should -Match 'cannot\s+override confirmed criteria'
    }
    It 'test:AppCi.DistributionConvergence composes existing read-only distribution gates' {
        Import-Module (Join-Path $script:repo 'tests\ConsumerInstallFixture.psm1') -Force -DisableNameChecking
        $result = Test-ConsumerDistributionDrift -SourceRepoRoot $script:repo
        $result.Unchanged | Should -BeTrue
        foreach ($check in $result.Checks) {
            $check.ExitCode | Should -Be 0 -Because "$($check.Name): $($check.Output)"
        }
    }
}
