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
        $script:epicModule = Get-Module EpicAutopilot

        function Invoke-TestEpicHostLoop {
            param(
                [Parameter(Mandatory)][string]$Epic,
                [string]$Target = 'HEAD',
                [string]$RepoRoot,
                [string]$StatePath,
                [string]$PlanStateScript,
                [scriptblock]$PlanStateInvoker,
                [scriptblock]$TargetResolver,
                [scriptblock]$RunFactory,
                [scriptblock]$LauncherInvoker
            )

            $parameters = @{}
            foreach ($entry in $PSBoundParameters.GetEnumerator()) {
                $parameters[$entry.Key] = $entry.Value
            }
            return & $script:epicModule {
                param($CoreParameters)
                Invoke-EpicAutopilotHostLoopCore @CoreParameters
            } $parameters
        }

        function Read-TestEpicState {
            param([Parameter(Mandatory)][string]$Path)
            return & $script:epicModule {
                param($StatePath)
                Read-EpicAutopilotState -Path $StatePath
            } $Path
        }

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
                $during = [System.IO.File]::ReadAllText($statePath) |
                    ConvertFrom-Json
                [void]$launchCalls.Add([pscustomobject]@{
                        Script = $LaunchScript
                        Argument = @($Argument)
                        Root = $Root
                        During = $during
                    })
                return $exitCode
            }.GetNewClosure()

            $result = Invoke-TestEpicHostLoop -Epic 'abc123' `
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
                '-Branch', 'main',
                '-ExpectedStartCommit', $script:targetA
            )
            $result.ExitCode | Should -Be $exitCode
            $result.Launch | Should -BeTrue
            Assert-ExactState -State $result.State -Outcome "exit:$exitCode"
            Assert-ExactState -State (Read-TestEpicState -Path $statePath) `
                -Outcome "exit:$exitCode"

            $persisted = [System.IO.File]::ReadAllText($statePath)
            $replay = Invoke-TestEpicHostLoop -Epic 'abc123' `
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
        $none = Invoke-TestEpicHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
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
                Invoke-TestEpicHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
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
                Invoke-TestEpicHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
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
        @(Get-Command -Module EpicAutopilot).Name |
            Should -BeExactly @('Invoke-EpicAutopilotHostLoop')
        $publicParameters = (Get-Command Invoke-EpicAutopilotHostLoop).Parameters.Keys
        foreach ($parameter in @('Epic', 'Target', 'RepoRoot', 'StatePath')) {
            $publicParameters | Should -Contain $parameter
        }
        foreach ($privateParameter in @(
                'PlanStateScript', 'PlanStateInvoker', 'TargetResolver',
                'RunFactory', 'LauncherInvoker'
            )) {
            $publicParameters | Should -Not -Contain $privateParameter
        }
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
        $resumed = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $selectedPath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -RunFactory { throw 'resume must not allocate another run' } `
            -LauncherInvoker {
            param($LaunchScript, $Argument, $Root)
            [void]$selectedLaunches.Add(
                ([System.IO.File]::ReadAllText($selectedPath) | ConvertFrom-Json)
            )
            return 42
        }
        $selectedLaunches | Should -HaveCount 1
        Assert-ExactState -State $selectedLaunches[0] -Outcome 'running'
        $resumed.Resumed | Should -BeTrue
        Assert-ExactState -State $resumed.State -Outcome 'exit:42'
        [System.IO.File]::ReadAllText($selectedPath) |
            Should -Not -BeExactly $selectedRaw

        $runningPath = New-StatePath -Name 'already-running'
        [System.IO.File]::WriteAllText($runningPath, (New-StateJson -Outcome 'running'))
        $runningRaw = [System.IO.File]::ReadAllText($runningPath)
        $blockedLaunches = [System.Collections.Generic.List[object]]::new()
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
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
            $replay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
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
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $throwPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -RunFactory { $script:runA } -LauncherInvoker {
                throw 'synthetic start failure'
            }
        } | Should -Throw '*launcher invocation failed*synthetic start failure*'
        Assert-ExactState -State (Read-TestEpicState -Path $throwPath) `
            -Outcome 'invocation-failed'
        $throwRaw = [System.IO.File]::ReadAllText($throwPath)
        $throwReplay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
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
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $invalidResultPath `
                    -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                    -RunFactory { $script:runA } -LauncherInvoker $invalidLauncher
            } | Should -Throw '*invalid exit code*'
            Assert-ExactState -State (
                Read-TestEpicState -Path $invalidResultPath
            ) -Outcome 'invocation-failed'
            [System.IO.File]::ReadAllText($invalidResultPath) |
                Should -Not -Match '"outcome":"exit:0"'
        }

        $casPath = New-StatePath -Name 'terminal-cas-conflict'
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
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
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
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
            Invoke-TestEpicHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
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
                Invoke-TestEpicHostLoop -Epic 'abc123' `
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

    It 'test:EpicAutopilot.DefaultAdapters select the real rollup child and exact Git target' {
        $root = Join-Path $script:fixtureRoot 'default-adapters'
        $plans = Join-Path $root 'docs/implementation-plans'
        $childFolder = '2026-08-31-111111-first-child'
        $childDir = Join-Path $plans $childFolder
        $epicDir = Join-Path $plans 'epics/2026-08-31-abc123-fixture-epic'
        [void](New-Item -ItemType Directory -Path $childDir -Force)
        [void](New-Item -ItemType Directory -Path $epicDir -Force)
        [System.IO.File]::WriteAllText(
            (Join-Path $epicDir 'epic.md'),
            "# abc123: Fixture epic`n<!-- epic-id: abc123 -->`n"
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $childDir 'plan.md'),
            @(
                '# 111111: First child'
                '<!-- plan-id: 111111 -->'
                '<!-- epic: abc123 -->'
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Fixture | `test:fixture` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 Execute fixture (REQ-1) `S`'
            ) -join "`n"
        )
        & git -C $root init -q -b main
        & git -C $root config user.name fixture
        & git -C $root config user.email fixture@example.invalid
        & git -C $root add .
        & git -C $root commit -q -m fixture
        $targetCommit = (& git -C $root rev-parse HEAD).Trim()

        $statePath = Join-Path $root 'state.json'
        $launches = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'refs/heads/main' `
            -RepoRoot $root -StatePath $statePath -RunFactory { $script:runA } `
            -LauncherInvoker {
            param($LaunchScript, $Argument, $WorkingDirectory)
            [void]$launches.Add([pscustomobject]@{
                    Script = $LaunchScript
                    Argument = @($Argument)
                    Root = $WorkingDirectory
                })
            return 0
        }

        $result.NextChild.Id | Should -BeExactly '111111'
        $result.NextChild.FolderName | Should -BeExactly $childFolder
        $result.State.target | Should -BeExactly $targetCommit
        $launches | Should -HaveCount 1
        $launches[0].Argument | Should -BeExactly @(
            '-PlanSlug', $childFolder,
            '-Mode', 'whole-plan',
            '-Runtime', 'container',
            '-Branch', 'main',
            '-ExpectedStartCommit', $targetCommit
        )

        foreach ($failure in @(
                @{ Epic = 'ffffff'; Target = 'main'; Match = '*Get-PlanState epic rollup failed*' },
                @{ Epic = 'abc123'; Target = 'missing'; Match = "*Unable to resolve target branch 'missing'*" },
                @{ Epic = 'abc123'; Target = '../main'; Match = '*must name a valid local branch*' }
            )) {
            $failurePath = Join-Path $root (
                'failure-' + [guid]::NewGuid().ToString('N') + '.json'
            )
            {
                Invoke-TestEpicHostLoop -Epic $failure.Epic -Target $failure.Target `
                    -RepoRoot $root -StatePath $failurePath -LauncherInvoker {
                    throw 'failed admission must not launch'
                }
            } | Should -Throw $failure.Match
            Test-Path -LiteralPath $failurePath | Should -BeFalse
        }
        $launches | Should -HaveCount 1
    }

    It 'test:EpicAutopilot.StateSchema rejects every noncanonical six-field record without mutation' {
        $base = New-StateJson
        $cases = [System.Collections.Generic.List[object]]::new()
        $cases.Add(@{ Name = 'extra field'; Json = $base.TrimEnd('}') + ',"extra":"x"}' })
        $cases.Add(@{
                Name = 'duplicate field'
                Json = '{"epic":"abc123","epic":"abc123","target":"' + $script:targetA +
                    '","currentChild":"111111","branch":"feature/2026-08-31-111111-first-child",' +
                    '"run":"' + $script:runA + '","outcome":"selected"}'
            })
        $cases.Add(@{ Name = 'wrong-case field'; Json = $base.Replace('"epic"', '"Epic"') })
        foreach ($field in @('epic', 'target', 'currentChild', 'branch', 'run', 'outcome')) {
            $cases.Add(@{
                    Name = "non-string $field"
                    Json = ([regex]::new('"' + $field + '":"[^"]*"')).Replace(
                        $base, ('"' + $field + '":1'), 1
                    )
                })
        }
        foreach ($invalid in @(
                @{ Name = 'malformed epic'; Field = 'epic'; Value = 'abc12g' },
                @{ Name = 'malformed child'; Field = 'currentChild'; Value = '11111G' },
                @{ Name = 'short target'; Field = 'target'; Value = ('a' * 39) },
                @{ Name = 'long target'; Field = 'target'; Value = ('a' * 41) },
                @{ Name = 'invalid branch'; Field = 'branch'; Value = 'Feature/child' },
                @{ Name = 'noncanonical guid'; Field = 'run'; Value = $script:runA.ToUpperInvariant() },
                @{ Name = 'invalid outcome'; Field = 'outcome'; Value = 'complete' }
            )) {
            $cases.Add(@{
                    Name = $invalid.Name
                    Json = ([regex]::new(
                            '"' + $invalid.Field + '":"[^"]*"'
                        )).Replace(
                        $base,
                        ('"' + $invalid.Field + '":"' + $invalid.Value + '"'),
                        1
                    )
                })
        }

        $schemaLaunches = [System.Collections.Generic.List[object]]::new()
        foreach ($case in $cases) {
            $path = New-StatePath -Name ('schema-' + [guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText($path, $case.Json)
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $path `
                    -PlanStateInvoker { throw 'state validation must run first' } `
                    -TargetResolver { throw 'state validation must run first' } `
                    -LauncherInvoker {
                    [void]$schemaLaunches.Add($null)
                    return 0
                }
            } | Should -Throw -Because $case.Name
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path)) |
                Should -BeExactly $before -Because $case.Name
        }
        $schemaLaunches | Should -HaveCount 0
    }

    It 'test:EpicAutopilot.Wrapper exposes terminal and no-child process outcomes' {
        $layout = Join-Path $script:fixtureRoot 'installed-wrapper'
        [void](New-Item -ItemType Directory -Path $layout -Force)
        Copy-Item -LiteralPath (
            Join-Path $script:repoRoot 'scripts/skalary/Invoke-EpicAutopilot.ps1'
        ) -Destination (Join-Path $layout 'Invoke-EpicAutopilot.ps1')
        [System.IO.File]::WriteAllText(
            (Join-Path $layout 'EpicAutopilot.psm1'),
            @'
function Invoke-EpicAutopilotHostLoop {
    param(
        [Parameter(Mandatory)][string]$Epic,
        [string]$Target = 'HEAD',
        [string]$RepoRoot,
        [string]$StatePath
    )
    if ($env:EPIC_WRAPPER_SCENARIO -ceq 'none') {
        return [pscustomobject]@{ State = $null }
    }
    $outcome = if ($env:EPIC_WRAPPER_SCENARIO -ceq 'failed') {
        'invocation-failed'
    }
    else {
        "exit:$($env:EPIC_WRAPPER_SCENARIO)"
    }
    return [pscustomobject]@{
        State = [pscustomobject]@{
            epic = 'abc123'
            target = ('a' * 40)
            currentChild = '111111'
            branch = 'feature/child'
            run = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            outcome = $outcome
        }
        ExitCode = if ($outcome -like 'exit:*') {
            [int]$env:EPIC_WRAPPER_SCENARIO
        } else { $null }
    }
}
Export-ModuleMember -Function Invoke-EpicAutopilotHostLoop
'@
        )
        $wrapper = Join-Path $layout 'Invoke-EpicAutopilot.ps1'
        $originalScenario = $env:EPIC_WRAPPER_SCENARIO
        try {
            foreach ($case in @(
                    @{ Scenario = '0'; Exit = 0; Match = '"outcome":"exit:0"' },
                    @{ Scenario = '42'; Exit = 42; Match = '"outcome":"exit:42"' },
                    @{ Scenario = '255'; Exit = 255; Match = '"outcome":"exit:255"' },
                    @{ Scenario = 'failed'; Exit = 1; Match = 'invocation-failed' },
                    @{ Scenario = 'none'; Exit = 0; Match = 'no eligible NextChild' }
                )) {
                $env:EPIC_WRAPPER_SCENARIO = $case.Scenario
                $output = @(
                    & (Get-Process -Id $PID).Path -NoProfile -File $wrapper abc123 2>&1
                ) | Out-String
                $LASTEXITCODE | Should -Be $case.Exit -Because $case.Scenario
                $output | Should -Match $case.Match -Because $case.Scenario
            }
        }
        finally {
            $env:EPIC_WRAPPER_SCENARIO = $originalScenario
        }
    }
}
