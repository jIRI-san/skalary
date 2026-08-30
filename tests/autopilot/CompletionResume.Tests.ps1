Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container completion resume' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:helperPath = Join-Path $repoRoot 'plugins/autopilot/scripts/plan-dispatch.sh'
        $script:reviewGatePath = Join-Path $repoRoot 'scripts/skalary/ReviewCycleGate.ps1'
        $script:harvestValidatorPath = Join-Path $repoRoot 'scripts/skalary/Invoke-PhaseHarvest.ps1'
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

        function New-WrappedPhaseReviewLog {
            param([Parameter(Mandatory)][int[]]$Phase)

            return @(
                foreach ($phaseNumber in $Phase) {
                    foreach ($cycle in 1..3) {
                        "- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-$phaseNumber cycle=$cycle outcome=findings"
                    }
                    "- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=phase-$phaseNumber after=3 action=wrap"
                }
            ) -join "`n"
        }

        $script:helperBashPath = ConvertTo-BashPath -Path $helperPath
        $script:reviewGateBashPath = ConvertTo-BashPath -Path $reviewGatePath
        $script:harvestValidatorBashPath = ConvertTo-BashPath -Path $harvestValidatorPath

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
            $plan = ConvertTo-BashPath -Path $planPath
            $selectedGatePath = if ($GatePath) { $GatePath } else { $reviewGatePath }
            $gate = if ($selectedGatePath -eq $reviewGatePath) {
                $reviewGateBashPath
            }
            else {
                ConvertTo-BashPath -Path $selectedGatePath
            }
            $output = @(
                & bash -c 'source "$1"; autopilot_execution_targets "$2" "$3" "$4"' `
                    -- $helperBashPath $plan $Mode $gate
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
        $crLog = New-WrappedPhaseReviewLog -Phase 1
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
        $crLog = New-WrappedPhaseReviewLog -Phase 2
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

        $legacyClean = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=clean
'@
        @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $legacyClean) |
            Should -Be @('operator-stop:1')
    }

    It 'stops at wrapped finalization unless a durable Reopen already exists' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $wrapped = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=phase-1 after=3 action=wrap
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=plan-finalization after=3 action=wrap
'@
        @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $wrapped) |
            Should -Be @('operator-stop:plan-finalization')

        $authorized = $wrapped + @'

- [2026-08-29] [src:note] [sev:Low] review-cycle-remediation stage=plan-finalization after=3 action=reopen authorization=operator-ticket-44 reason=run replacement review
'@
        @(Get-ExecutionTargets -PlanText $plan -Mode whole-plan -CrLogText $authorized) |
            Should -Be @('completion-only')
    }

    It 'converts a zero-exit wrapped finalization close into an operator stop' {
        $repoDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $planSlug = '2026-08-30-ca8ba8-wrapped-finalization'
        $planDir = Join-Path $repoDir "docs/implementation-plans/$planSlug"
        $logsDir = Join-Path $planDir 'assets/logs'
        [void](New-Item -ItemType Directory -Path $logsDir -Force)
        Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') `
            -Value '# Requirements' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @'
## Phase 1
- [x] 1.1 completed
'@
        $wrapped = @'
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=phase-1 cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=phase-1 after=3 action=wrap
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=1 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=2 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=3 outcome=findings
- [2026-08-29] [src:note] [sev:Low] review-cycle-decision stage=plan-finalization after=3 action=wrap
'@
        Set-Content -LiteralPath (Join-Path $logsDir 'cr-log.md') `
            -Value $wrapped -Encoding utf8NoBOM
        $stateScript = Join-Path $repoDir 'Get-PhaseExecutionState.ps1'
        Set-Content -LiteralPath $stateScript -Encoding utf8NoBOM -Value @'
param([string]$PlanPath, [int]$Phase, [string]$RepoRoot, [string]$HarvestValidator)
Write-Output closed
'@
        & git -C $repoDir init --quiet
        & git -C $repoDir config user.name fixture
        & git -C $repoDir config user.email fixture@example.invalid
        & git -C $repoDir add --all
        & git -C $repoDir commit --quiet -m initial
        $helper = $helperBashPath
        $bashPlan = ConvertTo-BashPath -Path (Join-Path $planDir 'plan.md')
        $bashRepo = ConvertTo-BashPath -Path $repoDir
        $state = ConvertTo-BashPath -Path $stateScript

        $blocked = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $reviewGateBashPath $bashRepo $state $harvestValidatorBashPath
        $LASTEXITCODE | Should -Be 0
        $blocked | Should -Be 'operator-decision'

        Add-Content -LiteralPath (Join-Path $logsDir 'cr-log.md') -Encoding utf8NoBOM -Value `
            '- [2026-08-29] [src:note] [sev:Low] review-cycle-remediation stage=plan-finalization after=3 action=reopen authorization=operator-ticket-45 reason=run replacement review'
        & git -C $repoDir add --all
        & git -C $repoDir commit --quiet -m 'authorize finalization reopen'
        $authorized = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $reviewGateBashPath $bashRepo $state $harvestValidatorBashPath
        $LASTEXITCODE | Should -Be 0
        $authorized | Should -Be 'close-pending'
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
        $helper = $helperBashPath
        $gate = $reviewGateBashPath
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
        $helper = $helperBashPath

        foreach ($target in @('completion-only', 'phase:3', 'phase-completion:3')) {
            & bash -c 'source "$1"; autopilot_target_owns_finalization "$2" "$3"' `
                -- $helper $target 3
            $LASTEXITCODE | Should -Be 0
        }
        & bash -c 'source "$1"; autopilot_target_owns_finalization "$2" "$3"' `
            -- $helper 'phase:2' 3
        $LASTEXITCODE | Should -Be 1
    }

    It 'test:AutopilotCompletionResume.ZeroExitClosePending never converts pending close to success' {
        $helper = $helperBashPath

        $action = & bash -c 'source "$1"; autopilot_completion_handoff_action 0 close-pending 0 3' `
            -- $helper
        $LASTEXITCODE | Should -Be 0
        $action | Should -Be 'resume'

        $exhausted = & bash -c 'source "$1"; autopilot_completion_handoff_action 0 close-pending 3 3' `
            -- $helper
        $LASTEXITCODE | Should -Be 0
        $exhausted | Should -Be 'pending-failed'

        $closed = & bash -c 'source "$1"; autopilot_completion_handoff_action 0 closed 3 3' `
            -- $helper
        $closed | Should -Be 'complete'
    }

    It 'test:AutopilotCompletionResume.LongRunningFinalValidation keeps one session and timeout budget across handoffs' {
        $plan = @'
## Phase 1
- [x] 1.1 completed
'@
        $crLog = New-WrappedPhaseReviewLog -Phase 1
        $crLog += "`n- [2026-08-29] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=1 outcome=clean run=11111111-1111-1111-1111-111111111111"
        $repoDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $planSlug = '2026-08-29-abc123-long-validation'
        $planDir = Join-Path $repoDir "docs/implementation-plans/$planSlug"
        $logsDir = Join-Path $planDir 'assets/logs'
        [void](New-Item -ItemType Directory -Path $logsDir -Force)
        Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') `
            -Value '# Requirements' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $planDir 'assets/logs/cr-log.md') `
            -Value ($crLog -replace "`r`n?", "`n") -Encoding utf8NoBOM -NoNewline
        $planPath = Join-Path $planDir 'plan.md'
        Set-Content -LiteralPath $planPath -Value $plan -Encoding utf8NoBOM
        & git -C $repoDir init --quiet
        & git -C $repoDir config user.name fixture
        & git -C $repoDir config user.email fixture@example.invalid
        & git -C $repoDir add -- .
        & git -C $repoDir commit --quiet -m initial
        $initialCommit = (& git -C $repoDir rev-parse HEAD).Trim()
        $helper = $helperBashPath
        $bashPlan = ConvertTo-BashPath -Path $planPath
        $gate = $reviewGateBashPath

        $stateScript = Join-Path $fixtureRoot (
            'Get-PhaseExecutionState-' + [guid]::NewGuid().ToString('N') + '.ps1'
        )
        Set-Content -LiteralPath $stateScript -Encoding utf8NoBOM -Value @'
param([string]$PlanPath, [int]$Phase, [string]$RepoRoot, [string]$HarvestValidator)
Write-Output closed
'@
        $bashStateScript = ConvertTo-BashPath -Path $stateScript
        $bashRepo = ConvertTo-BashPath -Path $repoDir
        $openPrProbe = Join-Path $fixtureRoot ('gh-open-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $openPrProbe -Encoding utf8NoBOM -Value @'
#!/bin/bash
printf '%s\n' '1'
'@
        $missingPrProbe = Join-Path $fixtureRoot ('gh-missing-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $missingPrProbe -Encoding utf8NoBOM -Value @'
#!/bin/bash
printf '%s\n' '0'
'@
        $bashOpenPrProbe = ConvertTo-BashPath -Path $openPrProbe
        $bashMissingPrProbe = ConvertTo-BashPath -Path $missingPrProbe
        & bash -c 'chmod +x "$1" "$2"' -- $bashOpenPrProbe $bashMissingPrProbe
        $pending = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $pending | Should -Be 'close-pending'

        $archiveRoot = Join-Path $repoDir 'docs/implementation-plans/archived'
        [void](New-Item -ItemType Directory -Path $archiveRoot -Force)
        Move-Item -LiteralPath $planDir -Destination $archiveRoot
        $uncommitted = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $uncommitted | Should -Be 'close-pending'

        $archivedPlan = Join-Path $archiveRoot "$planSlug/plan.md"
        & git -C $repoDir add -- $archivedPlan
        & git -C $repoDir commit --quiet -m 'partial archive'
        $partialCommit = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $partialCommit | Should -Be 'close-pending'

        & git -C $repoDir add -- .
        & git -C $repoDir commit --quiet -m 'finish partial archive'
        $splitCommit = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $splitCommit | Should -Be 'close-pending'

        & git -C $repoDir checkout --quiet -b atomic-archive $initialCommit
        if (Test-Path -LiteralPath $archiveRoot) {
            Remove-Item -LiteralPath $archiveRoot -Recurse -Force
        }
        [void](New-Item -ItemType Directory -Path $archiveRoot -Force)
        Move-Item -LiteralPath $planDir -Destination $archiveRoot
        & git -C $repoDir add --all
        & git -C $repoDir commit --quiet -m archive
        $missingPr = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashMissingPrProbe
        $LASTEXITCODE | Should -Be 0
        $missingPr | Should -Be 'close-pending'

        $closed = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $closed | Should -Be 'closed'

        Add-Content -LiteralPath $archivedPlan -Value "`n<!-- late committed mutation -->" `
            -Encoding utf8NoBOM
        & git -C $repoDir add --all
        & git -C $repoDir commit --quiet -m 'mutate archived tree'
        $mutated = & bash -c 'source "$1"; AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" AUTOPILOT_GH_BIN="$7" autopilot_target_close_state "$2" completion-only 1 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $bashStateScript $harvestValidatorBashPath $bashOpenPrProbe
        $LASTEXITCODE | Should -Be 0
        $mutated | Should -Be 'close-pending'

        $entrypoint | Should -Match '--session-id "\$\{TARGET_SESSION_ID\}"'
        $entrypoint | Should -Match 'TARGET_STARTED_AT=\$\(date \+%s\)'
        $entrypoint | Should -Match '\$\(date \+%s\) - TARGET_STARTED_AT'
        $entrypoint | Should -Match 'remained ''close-pending'''
        $agent | Should -Match 'Validation is still running\.'
        $agent | Should -Match 'Do not report success until'
    }

    It 'requires a terminal canonical phase-close receipt when its probe is installed' {
        $plan = @'
## Phase 1
- [x] 1.1 completed

## Phase 2
- [x] 2.1 completed
'@
        $crLog = New-WrappedPhaseReviewLog -Phase @(1, 2)
        $planDir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $logsDir = Join-Path $planDir 'assets/logs'
        [void](New-Item -ItemType Directory -Path $logsDir -Force)
        Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') `
            -Value '# Requirements' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $logsDir 'cr-log.md') `
            -Value ($crLog -replace "`r`n?", "`n") -Encoding utf8NoBOM -NoNewline
        $planPath = Join-Path $planDir 'plan.md'
        Set-Content -LiteralPath $planPath -Value $plan -Encoding utf8NoBOM
        $stateScript = Join-Path $planDir 'Get-PhaseExecutionState.ps1'
        Set-Content -LiteralPath $stateScript -Encoding utf8NoBOM -Value @'
param([string]$PlanPath, [int]$Phase, [string]$RepoRoot, [string]$HarvestValidator)
Write-Output $env:FAKE_PHASE_CLOSE_STATE
'@
        & git -C $planDir init --quiet
        & git -C $planDir config user.name fixture
        & git -C $planDir config user.email fixture@example.invalid
        & git -C $planDir add --all
        & git -C $planDir commit --quiet -m initial
        $helper = $helperBashPath
        $bashPlan = ConvertTo-BashPath -Path $planPath
        $bashRepo = ConvertTo-BashPath -Path $planDir
        $gate = $reviewGateBashPath
        $state = ConvertTo-BashPath -Path $stateScript

        $pending = & bash -c 'source "$1"; FAKE_PHASE_CLOSE_STATE=close-pending AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" autopilot_target_close_state "$2" phase-completion:1 2 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $state $harvestValidatorBashPath
        $LASTEXITCODE | Should -Be 0
        $pending | Should -Be 'close-pending'

        $closed = & bash -c 'source "$1"; FAKE_PHASE_CLOSE_STATE=closed AUTOPILOT_REPO_ROOT="$4" AUTOPILOT_PHASE_STATE_SCRIPT="$5" AUTOPILOT_HARVEST_VALIDATOR="$6" autopilot_target_close_state "$2" phase-completion:1 2 "$3"' `
            -- $helper $bashPlan $gate $bashRepo $state $harvestValidatorBashPath
        $LASTEXITCODE | Should -Be 0
        $closed | Should -Be 'closed'
    }

    It 'wires the confined prompt and helper into the shipped container payload' {
        $entrypoint | Should -Match 'autopilot_execution_targets'
        $entrypoint | Should -Match '\.github/skills/autopilot/scripts/ReviewCycleGate\.ps1'
        $entrypoint | Should -Match 'phase-completion:'
        $entrypoint | Should -Match 'exit 42'
        $entrypoint | Should -Match 'This runtime resume is not operator authorization'
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
