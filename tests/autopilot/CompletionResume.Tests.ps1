Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container completion resume' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:helperPath = Join-Path $repoRoot 'plugins/autopilot/scripts/plan-dispatch.sh'
        $script:reviewGatePath = Join-Path $repoRoot 'scripts/skalary/ReviewCycleGate.ps1'
        $script:entrypoint = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/autopilot/scripts/container-entrypoint.sh'
        ) -Raw
        $script:containerLauncher = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/autopilot/scripts/launch-container.ps1'
        ) -Raw
        $script:agent = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/autopilot/agents/autopilot.agent.md'
        ) -Raw
        $script:dockerfile = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/autopilot/devcontainer/Dockerfile'
        ) -Raw
        $script:manifest = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/autopilot/plugin.json'
        ) -Raw | ConvertFrom-Json
        $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
            'skalary-autopilot-resume-' + [guid]::NewGuid().ToString('N')
        )
        [void](New-Item -ItemType Directory -Path $fixtureRoot)

        function ConvertTo-BashPath {
            param([Parameter(Mandatory)][string]$Path)
            if (-not $IsWindows) { return $Path }
            $converted = & bash -c 'cygpath -u "$1"' -- $Path
            if ($LASTEXITCODE -ne 0) { throw "Unable to convert bash path '$Path'." }
            return ($converted | Select-Object -Last 1).Trim()
        }

        function Get-ExecutionTargets {
            param(
                [Parameter(Mandatory)][string]$PlanText,
                [Parameter(Mandatory)][ValidateSet('whole-plan', 'next-phase')][string]$Mode,
                [string]$CrLogText,
                [string]$GatePath,
                [switch]$AllowFailure
            )
            $planDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
            $assetsDir = Join-Path $planDir 'assets'
            $logsDir = Join-Path $assetsDir 'logs'
            [void](New-Item -ItemType Directory -Path $logsDir -Force)
            Set-Content -LiteralPath (Join-Path $assetsDir 'requirements.md') `
                -Value '# Requirements' -Encoding utf8NoBOM
            if ($CrLogText) {
                Set-Content -LiteralPath (Join-Path $logsDir 'cr-log.md') `
                    -Value ($CrLogText -replace "`r`n?", "`n") -Encoding utf8NoBOM -NoNewline
            }
            $planPath = Join-Path $planDir 'plan.md'
            Set-Content -LiteralPath $planPath -Value $PlanText -Encoding utf8NoBOM
            $helper = ConvertTo-BashPath -Path $helperPath
            $plan = ConvertTo-BashPath -Path $planPath
            $selectedGatePath = if ($GatePath) { $GatePath } else { $reviewGatePath }
            $gate = ConvertTo-BashPath -Path $selectedGatePath
            $output = @(
                & bash -c 'source "$1"; autopilot_execution_targets "$2" "$3" "$4"' `
                    -- $helper $plan $Mode $gate
            )
            $exitCode = $LASTEXITCODE
            if ($AllowFailure) {
                return [pscustomobject]@{ ExitCode = $exitCode; Targets = @($output) }
            }
            if ($exitCode -ne 0) { throw "Target selection failed with exit code $exitCode." }
            return @($output)
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force
    }

    It 'test:AutopilotCompletionResume.PostGateAllComplete emits only completion-only' {
        $plan = @'
## Phase 1
- [x] 1.1 completed

## Phase 2
<!-- ReviewCycleGate phase-2 operator decision persisted -->
- [x] 2.1 completed
'@
        $crLog = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=phase-1 after=3 action=wrap
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-2 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-2 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-2 cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=phase-2 after=3 action=wrap
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $crLog)

        $targets | Should -HaveCount 1
        $targets[0] | Should -Be 'completion-only'
        $targets | Should -Not -Contain 'phase:1'
        $targets | Should -Not -Contain 'phase:2'
    }

    It 'test:AutopilotCompletionResume.CompletedPhasesAreNotReplayed selects only pending phases' {
        $plan = @'
## Phase 1
- [x] 1.1 completed

## Phase 2
- [ ] 2.1 pending
'@
        $crLog = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=clean
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $crLog)

        $targets | Should -Be @('phase:2')
        $targets | Should -Not -Contain 'phase:1'
        $targets | Should -Not -Contain 'phase-completion:1'
    }

    It 'finishes an earlier phase before starting a later pending phase' {
        $plan = @'
## Phase 1
- [x] 1.1 completed

## Phase 2
- [ ] 2.1 pending
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan)

        $targets | Should -Be @('phase-completion:1', 'phase:2')
        $targets | Should -Not -Contain 'phase:1'
    }

    It 'adds confined completion when selected work ends before a terminal final phase' {
        $plan = @'
## Phase 1
- [ ] 1.1 pending

## Phase 2
- [x] 2.1 completed
'@
        $crLog = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-2 cycle=1 outcome=clean
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $crLog)

        $targets | Should -Be @('phase:1', 'completion-only')
        $targets | Should -Not -Contain 'phase:2'
    }

    It 'resumes unfinished phase completion without replaying implementation' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan)

        $targets | Should -Be @('phase-completion:1')
    }

    It 'keeps next-phase implementation-only when every step is complete' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        @(Get-ExecutionTargets -PlanText $plan -Mode next-phase) | Should -HaveCount 0
    }

    It 'selects only the first pending implementation phase in next-phase mode' {
        $plan = @'
## Phase 1
- [x] 1.1 completed

## Phase 2
- [ ] 2.1 pending

## Phase 3
- [ ] 3.1 pending
'@
        @(Get-ExecutionTargets -PlanText $plan -Mode next-phase) | Should -Be @('phase:2')
    }

    It 'fails closed on unsupported phase step states' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
- [!] 1.2 invalid

## Known Constraints
- [ ] operator note
'@
        $result = Get-ExecutionTargets -PlanText $plan -Mode whole-plan -AllowFailure

        $result.ExitCode | Should -Not -Be 0
        $result.Targets | Should -HaveCount 0
    }

    It 'fails closed when pending and unsupported step states are mixed' {
        $plan = @'
## Phase 1
- [ ] 1.1 pending
- [!] 1.2 invalid

## Phase 2
- [ ] 2.1 pending
'@
        $result = Get-ExecutionTargets -PlanText $plan -Mode whole-plan -AllowFailure

        $result.ExitCode | Should -Not -Be 0
        $result.Targets | Should -HaveCount 0
    }

    It 'fails target selection when the installed review gate is unavailable' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $missingGate = Join-Path $fixtureRoot 'missing-ReviewCycleGate.ps1'
        $result = Get-ExecutionTargets -PlanText $plan -Mode whole-plan `
            -GatePath $missingGate -AllowFailure

        $result.ExitCode | Should -Not -Be 0
        $result.Targets | Should -HaveCount 0
    }

    It 'preserves an unresolved operator gate without invoking an agent' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $crLog = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=3 outcome=findings
'@
        $targets = @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $crLog)

        $targets | Should -Be @('operator-stop:1')
    }

    It 'distinguishes nonterminal and operator-blocked pre-finalization gates' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $allowDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $allowLogs = Join-Path $allowDir 'assets/logs'
        [void](New-Item -ItemType Directory -Path $allowLogs -Force)
        Set-Content -LiteralPath (Join-Path $allowDir 'assets/requirements.md') `
            -Value '# Requirements' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $allowDir 'plan.md') -Value $plan -Encoding utf8NoBOM
        $operatorDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $operatorLogs = Join-Path $operatorDir 'assets/logs'
        [void](New-Item -ItemType Directory -Path $operatorLogs -Force)
        Set-Content -LiteralPath (Join-Path $operatorDir 'assets/requirements.md') `
            -Value '# Requirements' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $operatorDir 'plan.md') -Value $plan -Encoding utf8NoBOM
        $operatorLog = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=3 outcome=findings
'@
        Set-Content -LiteralPath (Join-Path $operatorDir 'assets/logs/cr-log.md') `
            -Encoding utf8NoBOM -NoNewline -Value ($operatorLog -replace "`r`n?", "`n")
        $helper = ConvertTo-BashPath -Path $helperPath
        $gate = ConvertTo-BashPath -Path $reviewGatePath
        $allowPlan = ConvertTo-BashPath -Path (Join-Path $allowDir 'plan.md')
        $operatorPlan = ConvertTo-BashPath -Path (Join-Path $operatorDir 'plan.md')

        & bash -c 'source "$1"; autopilot_plan_phase_gates_terminal "$2" "$3"' `
            -- $helper $allowPlan $gate
        $LASTEXITCODE | Should -Be 1
        & bash -c 'source "$1"; autopilot_plan_phase_gates_terminal "$2" "$3"' `
            -- $helper $operatorPlan $gate
        $LASTEXITCODE | Should -Be 42
    }

    It 'identifies explicit and final-phase targets that own plan finalization' {
        $helper = ConvertTo-BashPath -Path $helperPath

        foreach ($target in @('completion-only', 'phase:3', 'phase-completion:3')) {
            & bash -c 'source "$1"; autopilot_target_owns_finalization "$2" "$3"' `
                -- $helper $target 3
            $LASTEXITCODE | Should -Be 0
        }
        & bash -c 'source "$1"; autopilot_target_owns_finalization "$2" "$3"' `
            -- $helper 'phase:2' 3
        $LASTEXITCODE | Should -Be 1
    }

    It 'wires the confined prompt and helper into the shipped container payload' {
        $entrypoint | Should -Match 'autopilot_execution_targets'
        $entrypoint | Should -Match '\.github/skills/autopilot/scripts/ReviewCycleGate\.ps1'
        $entrypoint | Should -Match 'phase-completion:'
        $entrypoint | Should -Match 'exit 42'
        $entrypoint | Should -Match 'exit "\$\{RUN_EXIT_CODE\}"'
        $entrypoint | Should -Match 'at Plan Completion only'
        $agent | Should -Match 'skip the Execution Loop and \*\*On Phase Completion\*\* in full'
        $dockerfile | Should -Match 'COPY scripts/plan-dispatch\.sh /usr/local/lib/autopilot/plan-dispatch\.sh'
        $containerLauncher | Should -Match 'session-transcript-completion\.md'
        $containerLauncher | Should -Match 'session-transcript-phase\$\{i\}-completion\.md'
        @($manifest.files | Where-Object src -eq 'scripts/plan-dispatch.sh') | Should -HaveCount 1
        @($manifest.files | Where-Object src -eq 'skills/autopilot/scripts/ReviewCycleGate.ps1') |
            Should -HaveCount 1
        @($manifest.files | Where-Object src -eq 'skills/autopilot/scripts/Add-WorkflowNote.ps1') |
            Should -HaveCount 1
    }
}
