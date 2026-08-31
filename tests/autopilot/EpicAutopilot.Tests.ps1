#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Epic autopilot child launcher state machine' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:modulePath = Join-Path $repoRoot 'scripts/skalary/EpicAutopilot.psm1'
        $script:originalContainerFlag = $env:AUTOPILOT_CONTAINER
        $env:AUTOPILOT_CONTAINER = $null
        $script:fixtureRoot = Join-Path $repoRoot (
            'artifacts/epic-autopilot-' + [guid]::NewGuid().ToString('N')
        )
        [void](New-Item -ItemType Directory -Path $fixtureRoot -Force)
        Import-Module $modulePath -Force

        $script:targetA = 'a' * 40
        $script:targetB = 'b' * 40
        $script:runA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $script:childA = [ordered]@{
            Id = '111111'
            Slug = 'first-child'
            FolderName = '2026-08-31-111111-first-child'
            PlanFile = 'unused'
            NextStepId = '1.1'
        }
        $script:childB = [ordered]@{
            Id = '222222'
            Slug = 'second-child'
            FolderName = '2026-08-31-222222-second-child'
            PlanFile = 'unused'
            NextStepId = '1.1'
        }

        function New-RollupJson {
            param(
                [string]$EpicId = 'abc123',
                [AllowNull()]$NextChild = $script:childA,
                [string]$Kind = 'epic'
            )
            return [ordered]@{
                Kind = $Kind
                EpicId = $EpicId
                NextChild = $NextChild
            } | ConvertTo-Json -Depth 5 -Compress
        }

        function New-StatePath {
            param([string]$Name)
            return Join-Path $script:fixtureRoot "$Name.json"
        }

        function New-StateJson {
            param(
                [string]$Epic = 'abc123',
                [string]$Target = $script:targetA,
                [string]$Child = $script:childA.Id,
                [string]$Branch = "feature/$($script:childA.FolderName)",
                [string]$Run = $script:runA,
                [string]$Outcome = 'selected'
            )
            return [ordered]@{
                epic = $Epic
                target = $Target
                currentChild = $Child
                branch = $Branch
                run = $Run
                outcome = $Outcome
            } | ConvertTo-Json -Compress
        }

        function Assert-ExactState {
            param(
                [Parameter(Mandatory)]$State,
                [Parameter(Mandatory)][string]$Outcome,
                [string]$Run = $script:runA
            )
            @($State.PSObject.Properties.Name) | Should -BeExactly @(
                'epic', 'target', 'currentChild', 'branch', 'run', 'outcome'
            )
            $State.epic | Should -BeExactly 'abc123'
            $State.target | Should -BeExactly $script:targetA
            $State.currentChild | Should -BeExactly $script:childA.Id
            $State.branch | Should -BeExactly "feature/$($script:childA.FolderName)"
            $State.run | Should -BeExactly $Run
            $State.outcome | Should -BeExactly $Outcome
        }
    }

    AfterAll {
        $env:AUTOPILOT_CONTAINER = $script:originalContainerFlag
        Remove-Module EpicAutopilot -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'test:EpicAutopilot.HostLoop launches the exact selected child once and preserves every terminal code' {
        $rollupA = New-RollupJson -NextChild $script:childA
        $planCalls = [System.Collections.Generic.List[object]]::new()
        $invoker = {
            param($EpicReference, $Root, $ScriptPath)
            [void]$planCalls.Add([pscustomobject]@{
                    Epic = $EpicReference
                    Root = $Root
                    ScriptPath = $ScriptPath
                })
            $rollupA
        }.GetNewClosure()
        $resolveTarget = { param($Reference, $Root) $script:targetA }

        foreach ($exitCode in @(0, 1, 42, 43, 124, 143, 255)) {
            $statePath = New-StatePath -Name "exit-$($exitCode.ToString().Replace('-', 'minus'))"
            $launchCalls = [System.Collections.Generic.List[object]]::new()
            $launcher = {
                param($LaunchScript, $Argument, $Root)
                $during = Read-EpicAutopilotState -Path $statePath
                [void]$launchCalls.Add([pscustomobject]@{
                        Script = $LaunchScript
                        Argument = @($Argument)
                        Root = $Root
                        During = $during
                    })
                return $exitCode
            }.GetNewClosure()

            $result = Invoke-EpicAutopilotHostLoop -Epic 'abc123' `
                -Target 'refs/heads/main' -RepoRoot $script:repoRoot -StatePath $statePath `
                -PlanStateInvoker $invoker -TargetResolver $resolveTarget `
                -RunFactory { $script:runA } -LauncherInvoker $launcher

            $launchCalls | Should -HaveCount 1
            $launchCalls[0].Script | Should -BeExactly (
                Join-Path $script:repoRoot '.github/skills/autopilot/scripts/launch.ps1'
            )
            $launchCalls[0].Root | Should -BeExactly $script:repoRoot
            Assert-ExactState -State $launchCalls[0].During -Outcome 'running'
            $launchCalls[0].Argument | Should -BeExactly @(
                '-PlanSlug', $script:childA.FolderName,
                '-Mode', 'whole-plan',
                '-Runtime', 'container',
                '-Branch', 'refs/heads/main'
            )
            $result.ExitCode | Should -Be $exitCode
            $result.Launch | Should -BeTrue
            Assert-ExactState -State $result.State -Outcome "exit:$exitCode"
            Assert-ExactState -State (Read-EpicAutopilotState -Path $statePath) `
                -Outcome "exit:$exitCode"

            $persisted = [System.IO.File]::ReadAllText($statePath)
            $replay = Invoke-EpicAutopilotHostLoop -Epic 'abc123' `
                -Target 'refs/heads/main' -RepoRoot $script:repoRoot -StatePath $statePath `
                -PlanStateInvoker $invoker -TargetResolver $resolveTarget `
                -LauncherInvoker { throw 'terminal status must not relaunch' }
            $replay.Replayed | Should -BeTrue
            $replay.Launch | Should -BeFalse
            $replay.ExitCode | Should -Be $exitCode
            Assert-ExactState -State $replay.State -Outcome "exit:$exitCode"
            [System.IO.File]::ReadAllText($statePath) | Should -BeExactly $persisted
            $launchCalls | Should -HaveCount 1
        }
        $planCalls | Should -HaveCount 14

        $nonePath = New-StatePath -Name 'no-child'
        $noneRollup = New-RollupJson -NextChild $null
        $none = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
            -StatePath $nonePath -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $noneRollup
        } -TargetResolver $resolveTarget -LauncherInvoker {
            throw 'no child must not launch'
        }
        $none.State | Should -BeNullOrEmpty
        Test-Path -LiteralPath $nonePath | Should -BeFalse

        $boundaryLaunches = [System.Collections.Generic.List[object]]::new()
        $planRollup = New-RollupJson -Kind 'plan'
        foreach ($badInvoker in @(
                { param($EpicReference, $Root, $ScriptPath) '{bad' },
                { param($EpicReference, $Root, $ScriptPath) $planRollup },
                { param($EpicReference, $Root, $ScriptPath) throw 'process exited 7' }
            )) {
            $failurePath = New-StatePath -Name ([guid]::NewGuid().ToString('N'))
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
                    -StatePath $failurePath -PlanStateInvoker $badInvoker `
                    -TargetResolver $resolveTarget -LauncherInvoker {
                    [void]$boundaryLaunches.Add($null)
                    return 0
                }
            } | Should -Throw
            Test-Path -LiteralPath $failurePath | Should -BeFalse
        }
        $boundaryLaunches | Should -HaveCount 0

        $env:AUTOPILOT_CONTAINER = 'true'
        try {
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
                    -StatePath (New-StatePath -Name 'container-refusal') `
                    -PlanStateInvoker { throw 'must not inspect plans in a container' } `
                    -TargetResolver $resolveTarget -LauncherInvoker {
                    throw 'must not launch in a container'
                }
            } | Should -Throw '*host-owned*'
        }
        finally {
            $env:AUTOPILOT_CONTAINER = $null
        }

        $moduleText = [System.IO.File]::ReadAllText($script:modulePath)
        $moduleText | Should -Match ([regex]::Escape(
                '.github/skills/autopilot/scripts/launch.ps1'
            ))
        $moduleText | Should -Match 'ProcessStartInfo'
        $moduleText | Should -Match 'ArgumentList'
        $moduleText | Should -Not -Match (
            '(?i)\b(?:docker|launch-container|launch-host|launch-sandbox|' +
            'validate-auth|prepare-packages|autopilot-dispatch)\b'
        )
        $wrapperTokens = $null
        $wrapperErrors = $null
        $wrapperAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:repoRoot 'scripts/skalary/Invoke-EpicAutopilot.ps1'),
            [ref]$wrapperTokens,
            [ref]$wrapperErrors
        )
        $wrapperErrors | Should -BeNullOrEmpty
        $wrapperText = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'scripts/skalary/Invoke-EpicAutopilot.ps1')
        )
        $wrapperText | Should -Match 'exit \(\[int\]\$result\.ExitCode\)'
        $wrapperText | Should -Not -Match 'outcome\.Substring'
        $wrapperParameters = @(
            $wrapperAst.ParamBlock.Parameters.Name.VariablePath.UserPath
        )
        $wrapperParameters | Should -Not -Contain 'Mode'
        $wrapperParameters | Should -Not -Contain 'Runtime'
    }

    It 'test:EpicAutopilot.ProcessBoundary observes exit 255 from a real pwsh child' {
        $childScript = Join-Path $TestDrive 'exit-255.ps1'
        [System.IO.File]::WriteAllText($childScript, "exit 255`n")

        $observed = & (Get-Module EpicAutopilot) {
            param($ScriptPath, $WorkingDirectory)
            Invoke-EpicChildLauncher -LaunchScript $ScriptPath -Argument @('unused') `
                -WorkingDirectory $WorkingDirectory
        } $childScript $TestDrive

        $observed | Should -Be 255
    }

    It 'test:EpicAutopilot.ResumeState resumes selected, refuses active or stale state, and fails closed on launch errors' {
        $invokerA = {
            param($EpicReference, $Root, $ScriptPath)
            New-RollupJson -NextChild $script:childA
        }
        $resolveA = { param($Reference, $Root) $script:targetA }

        $selectedPath = New-StatePath -Name 'selected-restart'
        [System.IO.File]::WriteAllText($selectedPath, (New-StateJson))
        $selectedRaw = [System.IO.File]::ReadAllText($selectedPath)
        $selectedLaunches = [System.Collections.Generic.List[object]]::new()
        $resumed = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $selectedPath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -RunFactory { throw 'resume must not allocate another run' } `
            -LauncherInvoker {
            param($LaunchScript, $Argument, $Root)
            [void]$selectedLaunches.Add(
                (Read-EpicAutopilotState -Path $selectedPath)
            )
            return 42
        }
        $selectedRaw | Should -BeExactly (New-StateJson)
        $selectedLaunches | Should -HaveCount 1
        Assert-ExactState -State $selectedLaunches[0] -Outcome 'running'
        $resumed.Resumed | Should -BeTrue
        Assert-ExactState -State $resumed.State -Outcome 'exit:42'

        $runningPath = New-StatePath -Name 'already-running'
        [System.IO.File]::WriteAllText($runningPath, (New-StateJson -Outcome 'running'))
        $runningRaw = [System.IO.File]::ReadAllText($runningPath)
        $blockedLaunches = [System.Collections.Generic.List[object]]::new()
        {
            Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $runningPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -LauncherInvoker {
                [void]$blockedLaunches.Add($null)
                return 0
            }
        } | Should -Throw '*already running*'
        $blockedLaunches | Should -HaveCount 0
        [System.IO.File]::ReadAllText($runningPath) | Should -BeExactly $runningRaw

        foreach ($terminalOutcome in @('exit:43', 'invocation-failed')) {
            $terminalPath = New-StatePath -Name (
                'terminal-' + $terminalOutcome.Replace(':', '-')
            )
            [System.IO.File]::WriteAllText(
                $terminalPath,
                (New-StateJson -Outcome $terminalOutcome)
            )
            $terminalRaw = [System.IO.File]::ReadAllText($terminalPath)
            $replay = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $terminalPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -LauncherInvoker { throw 'terminal state must not relaunch' }
            $replay.Replayed | Should -BeTrue
            $replay.Launch | Should -BeFalse
            $replay.State.outcome | Should -BeExactly $terminalOutcome
            [System.IO.File]::ReadAllText($terminalPath) | Should -BeExactly $terminalRaw
        }

        $throwPath = New-StatePath -Name 'launcher-throw'
        {
            Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $throwPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -RunFactory { $script:runA } -LauncherInvoker {
                throw 'synthetic start failure'
            }
        } | Should -Throw '*launcher invocation failed*synthetic start failure*'
        Assert-ExactState -State (Read-EpicAutopilotState -Path $throwPath) `
            -Outcome 'invocation-failed'
        $throwRaw = [System.IO.File]::ReadAllText($throwPath)
        $throwReplay = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $throwPath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -LauncherInvoker { throw 'stored failure must not relaunch' }
        $throwReplay.Replayed | Should -BeTrue
        [System.IO.File]::ReadAllText($throwPath) | Should -BeExactly $throwRaw

        foreach ($invalidExitCode in @(
                -1,
                256,
                [int]::MinValue,
                [int]::MaxValue
            )) {
            $invalidResultPath = New-StatePath -Name (
                'invalid-result-' + [guid]::NewGuid().ToString('N')
            )
            $invalidLauncher = {
                param($LaunchScript, $Argument, $Root)
                return $invalidExitCode
            }.GetNewClosure()
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $invalidResultPath `
                    -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                    -RunFactory { $script:runA } -LauncherInvoker $invalidLauncher
            } | Should -Throw '*invalid exit code*'
            Assert-ExactState -State (
                Read-EpicAutopilotState -Path $invalidResultPath
            ) -Outcome 'invocation-failed'
            [System.IO.File]::ReadAllText($invalidResultPath) |
                Should -Not -Match '"outcome":"exit:0"'
        }

        $casPath = New-StatePath -Name 'terminal-cas-conflict'
        {
            Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $casPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -RunFactory { $script:runA } -LauncherInvoker {
                param($LaunchScript, $Argument, $Root)
                [System.IO.File]::WriteAllText(
                    $casPath,
                    (New-StateJson -Outcome 'selected')
                )
                return 0
            }
        } | Should -Throw '*changed before its terminal result*'
        [System.IO.File]::ReadAllText($casPath) |
            Should -BeExactly (New-StateJson -Outcome 'selected')

        $conflictPath = New-StatePath -Name 'identity-conflicts'
        [System.IO.File]::WriteAllText($conflictPath, (New-StateJson))
        $conflictRaw = [System.IO.File]::ReadAllText($conflictPath)
        $conflicts = @(
            @{
                Name = 'stale epic'
                Invoker = {
                    param($EpicReference, $Root, $ScriptPath)
                    New-RollupJson -EpicId 'def456' -NextChild $script:childA
                }
                Resolver = $resolveA
            },
            @{
                Name = 'stale target'
                Invoker = $invokerA
                Resolver = { param($Reference, $Root) $script:targetB }
            },
            @{
                Name = 'second active child'
                Invoker = {
                    param($EpicReference, $Root, $ScriptPath)
                    New-RollupJson -NextChild $script:childB
                }
                Resolver = $resolveA
            },
            @{
                Name = 'missing active child'
                Invoker = {
                    param($EpicReference, $Root, $ScriptPath)
                    New-RollupJson -NextChild $null
                }
                Resolver = $resolveA
            }
        )
        foreach ($conflict in $conflicts) {
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $conflictPath `
                    -PlanStateInvoker $conflict.Invoker `
                    -TargetResolver $conflict.Resolver `
                    -LauncherInvoker { throw 'conflict must not launch' }
            } | Should -Throw -Because $conflict.Name
            [System.IO.File]::ReadAllText($conflictPath) | Should -BeExactly $conflictRaw
        }

        $malformedPath = New-StatePath -Name 'malformed'
        [System.IO.File]::WriteAllText($malformedPath, '{"epic":"abc123"}')
        $malformedRaw = [System.IO.File]::ReadAllBytes($malformedPath)
        {
            Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
                -StatePath $malformedPath -PlanStateInvoker $invokerA `
                -TargetResolver $resolveA -LauncherInvoker {
                throw 'malformed state must not launch'
            }
        } | Should -Throw
        [System.IO.File]::ReadAllBytes($malformedPath) | Should -Be $malformedRaw

        foreach ($invalidOutcome in @(
                'exit:-1',
                'exit:256',
                "exit:$([int]::MinValue)",
                "exit:$([int]::MaxValue)"
            )) {
            $invalidStatePath = New-StatePath -Name (
                'invalid-state-' + [guid]::NewGuid().ToString('N')
            )
            [System.IO.File]::WriteAllText(
                $invalidStatePath,
                (New-StateJson -Outcome $invalidOutcome)
            )
            $invalidStateRaw = [System.IO.File]::ReadAllBytes($invalidStatePath)
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' `
                    -RepoRoot $script:repoRoot -StatePath $invalidStatePath `
                    -PlanStateInvoker { throw 'invalid state must fail first' } `
                    -TargetResolver $resolveA -LauncherInvoker {
                    throw 'invalid state must not launch'
                }
            } | Should -Throw "*field 'outcome' is invalid*"
            [System.IO.File]::ReadAllBytes($invalidStatePath) |
                Should -Be $invalidStateRaw
        }

        foreach ($name in @('EpicAutopilot.psm1', 'Get-PlanState.ps1', 'Invoke-EpicAutopilot.ps1')) {
            $canonical = Join-Path $script:repoRoot "scripts/skalary/$name"
            $bundled = Join-Path $script:repoRoot "plugins/autopilot/skills/autopilot/scripts/$name"
            (Get-FileHash -LiteralPath $bundled -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
        }
    }
}
