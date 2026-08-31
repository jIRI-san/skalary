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
                [scriptblock]$WorktreeValidator,
                [scriptblock]$RunFactory,
                [scriptblock]$LauncherInvoker,
                [scriptblock]$ContainerProbe,
                [scriptblock]$RunLeaseProbe,
                [scriptblock]$AncestorTester,
                [scriptblock]$StateDeleteInvoker,
                [string]$ReviewScriptPath,
                [scriptblock]$ReviewInvoker,
                [scriptblock]$FinalEvidenceRecorder,
                [scriptblock]$FinalEvidenceCommitResolver,
                [scriptblock]$FinalEvidenceManager,
                [switch]$UseDefaultFinalEvidenceRecorder,
                [switch]$UseDefaultFinalEvidenceTransaction,
                [switch]$UseDefaultWorktreeValidator
            )

            $parameters = @{}
            foreach ($entry in $PSBoundParameters.GetEnumerator()) {
                $parameters[$entry.Key] = $entry.Value
            }
            $useDefaultRecorder = $parameters.ContainsKey(
                'UseDefaultFinalEvidenceRecorder'
            )
            $useDefaultTransaction = $parameters.ContainsKey(
                'UseDefaultFinalEvidenceTransaction'
            )
            $useDefaultWorktreeValidator = $parameters.ContainsKey(
                'UseDefaultWorktreeValidator'
            )
            $parameters.Remove('UseDefaultFinalEvidenceRecorder')
            $parameters.Remove('UseDefaultFinalEvidenceTransaction')
            $parameters.Remove('UseDefaultWorktreeValidator')
            if (-not $useDefaultWorktreeValidator -and
                -not $parameters.ContainsKey('WorktreeValidator')) {
                $parameters.WorktreeValidator = {}
            }
            if (-not $parameters.ContainsKey('ContainerProbe')) {
                $parameters.ContainerProbe = { $true }
            }
            if (-not $useDefaultRecorder -and
                -not $parameters.ContainsKey('FinalEvidenceRecorder')) {
                $parameters.FinalEvidenceRecorder = { 0 }
            }
            if (-not $useDefaultTransaction) {
                if (-not $parameters.ContainsKey('FinalEvidenceCommitResolver')) {
                    $parameters.FinalEvidenceCommitResolver = {
                        param($Branch, $Commit)
                        [pscustomobject]@{
                            IsReplay = $false
                            ReviewedTarget = $Commit
                            EvidenceCommit = $null
                            Capture = [pscustomobject]@{
                                RelativePath = 'capture.md'
                            }
                        }
                    }
                }
                if (-not $parameters.ContainsKey('FinalEvidenceManager')) {
                    $parameters.FinalEvidenceManager = {
                        param(
                            $Descriptor,
                            $Branch,
                            $Commit,
                            $Root,
                            $EpicId,
                            $ScriptPath,
                            $PlanDirectory,
                            $Message,
                            $ReviewType,
                            $Recorder
                        )
                        $recordOutput = @(
                            & $Recorder $ScriptPath $PlanDirectory $Message `
                                $ReviewType $Root
                        )
                        if ($recordOutput.Count -ne 1) {
                            throw 'Epic final crosscheck evidence writer must return exactly one exit code.'
                        }
                        $exitText = [string]$recordOutput[0]
                        if ($exitText -cnotmatch
                            '^(?:0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])$') {
                            throw "Epic final crosscheck evidence writer returned invalid exit code '$exitText'."
                        }
                        if ([int]$exitText -ne 0) {
                            throw "Epic final crosscheck evidence writer failed with exit code '$exitText'."
                        }
                        return $Commit
                    }
                }
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
        $script:runB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $script:canonicalRoot = Join-Path $fixtureRoot 'canonical'
        $script:epicFile = Join-Path $canonicalRoot 'epic.md'
        $script:planFileA = Join-Path $canonicalRoot 'child-a/plan.md'
        $script:planFileB = Join-Path $canonicalRoot 'child-b/plan.md'
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $script:planFileA
            ) -Force)
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $script:planFileB
            ) -Force)
        [System.IO.File]::WriteAllText(
            $script:epicFile,
            "# abc123: Fixture epic`n`n## Goal`n`nShip the fixture.`n`n## Definition of done`n`nAll fixture children are complete.`n"
        )
        [System.IO.File]::WriteAllText($script:planFileA, "# 111111: First child`n")
        [System.IO.File]::WriteAllText($script:planFileB, "# 222222: Second child`n")
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
                [string]$Kind = 'epic',
                [object[]]$Children,
                [Nullable[bool]]$IsComplete,
                [string]$EpicFile = $script:epicFile
            )
            if (-not $PSBoundParameters.ContainsKey('Children')) {
                $Children = @(if ($null -ne $NextChild) {
                        [ordered]@{
                            Id = [string]$NextChild.Id
                            IsComplete = $false
                            IsBlocked = $false
                        }
                    })
            }
            $completeCount = @($Children | Where-Object { $_.IsComplete }).Count
            $blockedCount = @($Children | Where-Object { $_.IsBlocked }).Count
            if (-not $PSBoundParameters.ContainsKey('IsComplete')) {
                $IsComplete = $Children.Count -gt 0 -and
                $completeCount -eq $Children.Count
            }
            return [ordered]@{
                Kind = $Kind
                EpicId = $EpicId
                EpicFile = $EpicFile
                Rollup = [ordered]@{
                    ChildCount = $Children.Count
                    CompleteCount = $completeCount
                    BlockedCount = $blockedCount
                    IsComplete = [bool]$IsComplete
                }
                Children = @($Children)
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

        $script:workflowNoteWriter = Join-Path $script:repoRoot `
            'scripts/skalary/Add-WorkflowNote.ps1'

        function New-FinalEvidenceGitFixture {
            param(
                [Parameter(Mandatory)][string]$Name,
                [string]$PlanFolder = '2026-08-31-111111-first-child',
                [string]$PlanId = '111111',
                [string]$EpicId = 'abc123',
                [switch]$NoCheckpoint
            )

            $root = Join-Path $script:fixtureRoot $Name
            $epicDir = Join-Path $root (
                'docs/implementation-plans/epics/2026-08-31-abc123-fixture-epic'
            )
            $planDir = Join-Path $root (
                "docs/implementation-plans/$PlanFolder"
            )
            [void](New-Item -ItemType Directory -Path $epicDir -Force)
            [void](New-Item -ItemType Directory -Path $planDir -Force)
            $epicFile = Join-Path $epicDir 'epic.md'
            $planFile = Join-Path $planDir 'plan.md'
            $capturePath = Join-Path $planDir 'capture.md'
            [System.IO.File]::WriteAllText(
                $epicFile,
                "# abc123: Fixture epic`n<!-- epic-id: abc123 -->`n`n## Goal`n`nShip.`n`n## Definition of done`n`nAll children complete.`n"
            )
            [System.IO.File]::WriteAllText(
                $planFile,
                @(
                    "# ${PlanId}: First child"
                    "<!-- plan-id: $PlanId -->"
                    "<!-- epic: $EpicId -->"
                    '<!-- cip-stage: done -->'
                    ''
                    '## Requirements'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '|----|-------------|---------------------|--------------|'
                    '| REQ-1 | Fixture | `test:fixture` | 1.1 |'
                    ''
                    '## Phase 1: Fixture'
                    ''
                    '- [x] 1.1 Execute fixture (REQ-1) `S`'
                ) -join "`n"
            )
            [System.IO.File]::WriteAllText(
                $capturePath,
                "## Capture`nPhase: 0`n`nNo entries for this phase.`n"
            )
            & git -C $root init --initial-branch=main --quiet
            & git -C $root config user.name 'Epic Autopilot Test'
            & git -C $root config user.email 'epic-autopilot@example.invalid'
            & git -C $root add -- .
            & git -C $root commit --quiet -m 'fixture base'
            $baseCommit = (& git -C $root rev-parse HEAD).Trim()
            [System.IO.File]::WriteAllText(
                (Join-Path $root 'operator-merge.txt'),
                "operator merge`n"
            )
            & git -C $root add -- operator-merge.txt
            & git -C $root commit --quiet -m 'operator merge'
            $targetCommit = (& git -C $root rev-parse HEAD).Trim()
            $statePath = Join-Path $script:fixtureRoot "$Name-state.json"
            if (-not $NoCheckpoint) {
                [System.IO.File]::WriteAllText(
                    $statePath,
                    (New-StateJson -Target $baseCommit -Outcome 'awaiting-merge' `
                        -Branch "feature/$PlanFolder")
                )
            }
            $completeChild = [ordered]@{
                Id = $script:childA.Id
                IsComplete = $true
                IsBlocked = $false
                PlanFile = $planFile
            }
            return [pscustomobject]@{
                Root = $root
                PlanDir = $planDir
                PlanFolder = $PlanFolder
                CapturePath = $capturePath
                StatePath = $statePath
                BaseCommit = $baseCommit
                TargetCommit = $targetCommit
                Rollup = New-RollupJson -NextChild $null `
                    -Children @($completeChild) -IsComplete $true `
                    -EpicFile $epicFile
            }
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
            $planCallCountBeforeLaunch = $planCalls.Count
            $expectedOutcome = if ($exitCode -eq 0) {
                'awaiting-merge'
            }
            else {
                "exit:$exitCode"
            }
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

            $planCalls | Should -HaveCount ($planCallCountBeforeLaunch + 1)
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
                '-ExpectedStartCommit', $script:targetA,
                '-Run', $script:runA
            )
            $result.ExitCode | Should -Be $exitCode
            $result.Launch | Should -BeTrue
            $result.Failed | Should -Be ($exitCode -ne 0)
            if ($exitCode -eq 42) {
                $result.Message | Should -Match 'operator action.*exit code 42'
            }
            elseif ($exitCode -ne 0) {
                $result.Message | Should -Match "child '111111'.*branch 'feature/.*failed with exit code $exitCode"
            }
            Assert-ExactState -State $result.State -Outcome $expectedOutcome
            Assert-ExactState -State (Read-TestEpicState -Path $statePath) `
                -Outcome $expectedOutcome

            $persisted = [System.IO.File]::ReadAllText($statePath)
            $planCallCountBeforeReplay = $planCalls.Count
            $replay = Invoke-TestEpicHostLoop -Epic 'abc123' `
                -Target 'refs/heads/main' -RepoRoot $script:repoRoot -StatePath $statePath `
                -PlanStateInvoker $invoker -TargetResolver $resolveTarget `
                -LauncherInvoker { throw 'terminal status must not relaunch' }
            $replay.Replayed | Should -BeTrue
            $replay.Launch | Should -BeFalse
            $replay.ExitCode | Should -Be $exitCode
            $replay.Failed | Should -Be ($exitCode -ne 0)
            Assert-ExactState -State $replay.State -Outcome $expectedOutcome
            [System.IO.File]::ReadAllText($statePath) | Should -BeExactly $persisted
            $launchCalls | Should -HaveCount 1
            $expectedReplayCalls = if ($exitCode -eq 0) { 1 } else { 0 }
            $planCalls | Should -HaveCount (
                $planCallCountBeforeReplay + $expectedReplayCalls
            )
        }

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
        $none.Blocked | Should -BeTrue
        $none.ExitCode | Should -Be 42
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
            '(?i)\b(?:launch-container|launch-host|launch-sandbox|' +
            'validate-auth|prepare-packages|autopilot-dispatch)\b'
        )
        $moduleText | Should -Match 'docker container ls --all'
        $moduleText | Should -Not -Match '(?i)\bdocker\s+(?:run|start|stop|kill|rm|create)\b'
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
        $wrapperText | Should -Match 'Terminal epic autopilot result has inconsistent'
        $wrapperText | Should -Match 'Blocked epic autopilot result must carry exit code 42'
        $wrapperParameters = @(
            $wrapperAst.ParamBlock.Parameters.Name.VariablePath.UserPath
        )
        $wrapperParameters | Should -Not -Contain 'Mode'
        $wrapperParameters | Should -Not -Contain 'Runtime'
        @(Get-Command -Module EpicAutopilot).Name |
            Should -BeExactly @('Invoke-EpicAutopilotHostLoop')
        $publicParameters = (Get-Command Invoke-EpicAutopilotHostLoop).Parameters.Keys
        foreach ($parameter in @('Epic', 'Target', 'RepoRoot')) {
            $publicParameters | Should -Contain $parameter
        }
        foreach ($privateParameter in @(
                'StatePath', 'PlanStateScript', 'PlanStateInvoker', 'TargetResolver',
                'WorktreeValidator', 'RunFactory', 'LauncherInvoker',
                'ContainerProbe', 'RunLeaseProbe', 'AncestorTester',
                'StateDeleteInvoker'
            )) {
            $publicParameters | Should -Not -Contain $privateParameter
        }
    }

    It 'test:EpicAutopilot.MergeGate proves verified success awaits merge and every other terminal result stops' {
        $rollup = New-RollupJson -NextChild $script:childA
        $resolveTarget = { param($Reference, $Root) $script:targetA }
        $launches = [System.Collections.Generic.List[string]]::new()

        foreach ($case in @(
                @{ Name = 'verified-success'; Output = @(0); Outcome = 'awaiting-merge'; Exit = 0 },
                @{ Name = 'failed'; Output = @(1); Outcome = 'exit:1'; Exit = 1 },
                @{ Name = 'degraded-close'; Output = @(3); Outcome = 'exit:3'; Exit = 3 },
                @{ Name = 'operator-stop'; Output = @(42); Outcome = 'exit:42'; Exit = 42 },
                @{ Name = 'publication-failed'; Output = @(70); Outcome = 'exit:70'; Exit = 70 },
                @{ Name = 'missing-result'; Output = @(); Outcome = 'invocation-failed'; Exit = 1 },
                @{ Name = 'duplicate-result'; Output = @(0, 0); Outcome = 'invocation-failed'; Exit = 1 },
                @{ Name = 'malformed-result'; Output = @('degraded'); Outcome = 'invocation-failed'; Exit = 1 },
                @{ Name = 'negative-result'; Output = @(-1); Outcome = 'invocation-failed'; Exit = 1 },
                @{ Name = 'wide-result'; Output = @(256); Outcome = 'invocation-failed'; Exit = 1 }
            )) {
            $statePath = New-StatePath -Name "merge-gate-$($case.Name)"
            $output = @($case.Output)
            $launcher = {
                param($LaunchScript, $Argument, $Root)
                [void]$launches.Add($case.Name)
                return $output
            }.GetNewClosure()

            $result = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $statePath `
                -PlanStateInvoker { param($EpicReference, $Root, $ScriptPath) $rollup } `
                -TargetResolver $resolveTarget -RunFactory { $script:runA } `
                -LauncherInvoker $launcher

            Assert-ExactState -State $result.State -Outcome $case.Outcome
            $result.ExitCode | Should -Be $case.Exit -Because $case.Name
            $result.Failed | Should -Be ($case.Exit -ne 0) -Because $case.Name
            $result.LaunchAttempted | Should -BeTrue -Because $case.Name
            $persisted = [System.IO.File]::ReadAllText($statePath)

            $replay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $statePath `
                -PlanStateInvoker { param($EpicReference, $Root, $ScriptPath) $rollup } `
                -TargetResolver $resolveTarget -LauncherInvoker {
                throw 'terminal merge-gate state must not launch another child'
            }
            $replay.Replayed | Should -BeTrue -Because $case.Name
            $replay.Launch | Should -BeFalse -Because $case.Name
            $replay.ExitCode | Should -Be $case.Exit -Because $case.Name
            $replay.Failed | Should -Be ($case.Exit -ne 0) -Because $case.Name
            Assert-ExactState -State $replay.State -Outcome $case.Outcome
            [System.IO.File]::ReadAllText($statePath) |
                Should -BeExactly $persisted -Because $case.Name
        }
        $launches | Should -HaveCount 10

        $legacyPath = New-StatePath -Name 'merge-gate-legacy-zero'
        [System.IO.File]::WriteAllText(
            $legacyPath,
            (New-StateJson -Outcome 'exit:0')
        )
        $legacyBytes = [System.IO.File]::ReadAllText($legacyPath)
        $legacy = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $legacyPath `
            -PlanStateInvoker { param($EpicReference, $Root, $ScriptPath) $rollup } `
            -TargetResolver $resolveTarget -LauncherInvoker {
            throw 'legacy terminal success must not relaunch or select a sibling'
        }
        $legacy.Replayed | Should -BeTrue
        $legacy.Launch | Should -BeFalse
        $legacy.ExitCode | Should -Be 0
        Assert-ExactState -State $legacy.State -Outcome 'exit:0'
        [System.IO.File]::ReadAllText($legacyPath) | Should -BeExactly $legacyBytes

        $moduleText = [System.IO.File]::ReadAllText($script:modulePath)
        $moduleText | Should -Not -Match '(?i)\bgit\s+(?:push|merge|checkout)\b'
        $moduleText | Should -Not -Match '(?i)\bgh\s+(?:api|pr)\b'
        $moduleText | Should -Not -Match '(?i)\b(?:Invoke-RestMethod|Invoke-WebRequest)\b'
        $moduleText | Should -Not -Match '(?i)transcript'

        $entrypointText = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/scripts/container-entrypoint.sh')
        )
        $dispatchText = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/scripts/plan-dispatch.sh')
        )
        $entrypointText | Should -Match 'WORK_BRANCH="feature/\$\{PLAN_SLUG\}"'
        $publishBeforeCloseIndex = $entrypointText.LastIndexOf(
            'Publishing ${WORK_BRANCH} before terminal close proof'
        )
        $closeProbeIndex = $entrypointText.LastIndexOf('autopilot_entrypoint_target_close_state')
        $finalPushIndex = $entrypointText.LastIndexOf('git push origin "${WORK_BRANCH}"')
        $successExitIndex = $entrypointText.LastIndexOf('exit "${RUN_EXIT_CODE}"')
        $publishBeforeCloseIndex | Should -BeGreaterThan -1
        $closeProbeIndex | Should -BeGreaterThan $publishBeforeCloseIndex
        $closeProbeIndex | Should -BeGreaterThan -1
        $finalPushIndex | Should -BeGreaterThan $closeProbeIndex
        $successExitIndex | Should -BeGreaterThan $finalPushIndex
        $entrypointText | Should -Match (
            'autopilot_entrypoint_target_close_state\s+\\\s+' +
            '"\$\{PLAN_PATH\}" "\$\{TARGET\}" "\$\{FINAL_PHASE_NUM\}" "\$\{REVIEW_GATE\}"\s+\\\s+' +
            '"\$\{WORK_BRANCH\}"'
        )
        $dispatchText | Should -Match 'Get-PhaseExecutionState\.ps1'
        $dispatchText | Should -Match 'autopilot_branch_has_published_pr'
        $dispatchText | Should -Match '--json headRefName,headRefOid,baseRefName,state'
        $dispatchText | Should -Match 'archived_tree_at_commit'
    }

    It 'test:EpicAutopilot.RefreshAndRepeat advances only proven merges and preserves every stop' {
        $completeA = [ordered]@{
            Id = $script:childA.Id; IsComplete = $true; IsBlocked = $false
            PlanFile = $script:planFileA
        }
        $incompleteA = [ordered]@{
            Id = $script:childA.Id; IsComplete = $false; IsBlocked = $false
        }
        $incompleteB = [ordered]@{
            Id = $script:childB.Id; IsComplete = $false; IsBlocked = $false
        }
        $blockedB = [ordered]@{
            Id = $script:childB.Id; IsComplete = $false; IsBlocked = $true
        }
        $blockedA = [ordered]@{
            Id = $script:childA.Id; IsComplete = $false; IsBlocked = $true
        }
        $forward = { param($Ancestor, $Descendant, $Root) $true }
        $resolveB = { param($Reference, $Root) $script:targetB }

        $ancestryRoot = Join-Path $script:fixtureRoot 'refresh-ancestry'
        [void](New-Item -ItemType Directory -Path $ancestryRoot -Force)
        & git -C $ancestryRoot init -q -b main
        & git -C $ancestryRoot config user.name fixture
        & git -C $ancestryRoot config user.email fixture@example.invalid
        [System.IO.File]::WriteAllText((Join-Path $ancestryRoot 'value.txt'), 'one')
        & git -C $ancestryRoot add .
        & git -C $ancestryRoot commit -q -m one
        $ancestorCommit = (& git -C $ancestryRoot rev-parse HEAD).Trim()
        [System.IO.File]::WriteAllText((Join-Path $ancestryRoot 'value.txt'), 'two')
        & git -C $ancestryRoot add .
        & git -C $ancestryRoot commit -q -m two
        $descendantCommit = (& git -C $ancestryRoot rev-parse HEAD).Trim()
        & $script:epicModule {
            param($Ancestor, $Descendant, $Root)
            Test-EpicAutopilotAncestor -Ancestor $Ancestor -Descendant $Descendant `
                -RepoRoot $Root
        } $ancestorCommit $descendantCommit $ancestryRoot | Should -BeTrue
        & $script:epicModule {
            param($Ancestor, $Descendant, $Root)
            Test-EpicAutopilotAncestor -Ancestor $Ancestor -Descendant $Descendant `
                -RepoRoot $Root
        } $descendantCommit $ancestorCommit $ancestryRoot | Should -BeFalse

        $advancePath = New-StatePath -Name 'refresh-advance'
        [System.IO.File]::WriteAllText(
            $advancePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $reordered = New-RollupJson -NextChild $script:childB `
            -Children @($incompleteB, $completeA)
        $advanceLaunches = [System.Collections.Generic.List[object]]::new()
        $advanced = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $advancePath `
            -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $reordered
        } -TargetResolver $resolveB -AncestorTester $forward `
            -RunFactory { $script:runB } -LauncherInvoker {
            param($LaunchScript, $Argument, $Root)
            $during = [System.IO.File]::ReadAllText($advancePath) |
                ConvertFrom-Json
            [void]$advanceLaunches.Add([pscustomobject]@{
                    Argument = @($Argument)
                    During = $during
                })
            return 0
        }
        $advanceLaunches | Should -HaveCount 1
        $advanceLaunches[0].During.target | Should -BeExactly $script:targetB
        $advanceLaunches[0].During.currentChild | Should -BeExactly $script:childB.Id
        $advanceLaunches[0].During.run | Should -BeExactly $script:runB
        $advanceLaunches[0].During.outcome | Should -BeExactly 'running'
        $advanceLaunches[0].Argument | Should -BeExactly @(
            '-PlanSlug', $script:childB.FolderName,
            '-Mode', 'whole-plan',
            '-Runtime', 'container',
            '-Branch', 'main',
            '-ExpectedStartCommit', $script:targetB,
            '-Run', $script:runB
        )
        $advanced.State.outcome | Should -BeExactly 'awaiting-merge'
        $advanced.State.currentChild | Should -BeExactly $script:childB.Id
        @($advanced.State.PSObject.Properties.Name) | Should -BeExactly @(
            'epic', 'target', 'currentChild', 'branch', 'run', 'outcome'
        )

        $restartPath = New-StatePath -Name 'refresh-selected-restart'
        [System.IO.File]::WriteAllText(
            $restartPath,
            (New-StateJson -Target $script:targetB -Child $script:childB.Id `
                -Branch "feature/$($script:childB.FolderName)" -Run $script:runB)
        )
        $restartLaunches = [System.Collections.Generic.List[object]]::new()
        $restart = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $restartPath `
            -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $reordered
        } -TargetResolver $resolveB -RunFactory {
            throw 'selected restart must retain its run'
        } -LauncherInvoker {
            param($LaunchScript, $Argument, $Root)
            [void]$restartLaunches.Add($null)
            return 42
        }
        $restartLaunches | Should -HaveCount 1
        $restart.Resumed | Should -BeTrue
        $restart.State.currentChild | Should -BeExactly $script:childB.Id
        $restart.State.run | Should -BeExactly $script:runB
        $restart.State.outcome | Should -BeExactly 'exit:42'

        $unchangedPath = New-StatePath -Name 'refresh-unchanged'
        [System.IO.File]::WriteAllText(
            $unchangedPath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $unchangedBytes = [System.IO.File]::ReadAllText($unchangedPath)
        $unchanged = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $unchangedPath `
            -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $reordered
        } -TargetResolver { param($Reference, $Root) $script:targetA } `
            -AncestorTester { throw 'unchanged target must not probe ancestry' } `
            -LauncherInvoker { throw 'unchanged target must not launch' }
        $unchanged.State.outcome | Should -BeExactly 'awaiting-merge'
        $unchanged.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($unchangedPath) |
            Should -BeExactly $unchangedBytes

        $invalidGraphs = @(
            @{
                Name = 'prior-incomplete'
                Json = New-RollupJson -NextChild $script:childB `
                    -Children @($incompleteA, $incompleteB)
                Match = '*NextChild must be the first*'
            },
            @{
                Name = 'prior-still-current'
                Json = New-RollupJson -NextChild $script:childA `
                    -Children @($completeA, $incompleteB)
                Match = '*NextChild must be the first*'
            },
            @{
                Name = 'prior-missing'
                Json = New-RollupJson -NextChild $script:childB `
                    -Children @($incompleteB)
                Match = '*exactly once; found 0*'
            },
            @{
                Name = 'prior-duplicate'
                Json = New-RollupJson -NextChild $script:childB `
                    -Children @($completeA, $completeA, $incompleteB)
                Match = '*duplicate Id*'
            }
        )
        foreach ($case in $invalidGraphs) {
            $path = New-StatePath -Name "refresh-$($case.Name)"
            [System.IO.File]::WriteAllText(
                $path,
                (New-StateJson -Outcome 'awaiting-merge')
            )
            $before = [System.IO.File]::ReadAllText($path)
            $json = $case.Json
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $path `
                    -PlanStateInvoker {
                    param($EpicReference, $Root, $ScriptPath)
                    $json
                } -TargetResolver $resolveB -AncestorTester $forward `
                    -LauncherInvoker { throw 'invalid graph must not launch' }
            } | Should -Throw $case.Match -Because $case.Name
            [System.IO.File]::ReadAllText($path) |
                Should -BeExactly $before -Because $case.Name
        }

        $globalConsistencyCases = [System.Collections.Generic.List[object]]::new()
        function Add-InvalidRollupCase {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Json,
                [Parameter(Mandatory)][string]$Match,
                [scriptblock]$Mutate
            )
            $document = $Json | ConvertFrom-Json
            if ($Mutate) {
                & $Mutate $document
            }
            [void]$globalConsistencyCases.Add([pscustomobject]@{
                    Name = $Name
                    Json = $document | ConvertTo-Json -Depth 6 -Compress
                    Match = $Match
                })
        }

        Add-InvalidRollupCase -Name 'duplicate-ids' `
            -Json (New-RollupJson -NextChild $script:childA `
                -Children @($incompleteA, $incompleteA)) `
            -Match '*duplicate Id*'
        Add-InvalidRollupCase -Name 'complete-and-blocked' `
            -Json (New-RollupJson -NextChild $null -Children @(
                [ordered]@{
                    Id = $script:childA.Id
                    IsComplete = $true
                    IsBlocked = $true
                }
            )) -Match '*both complete and blocked*'
        foreach ($field in @('ChildCount', 'CompleteCount', 'BlockedCount')) {
            Add-InvalidRollupCase -Name "mismatched-$field" `
                -Json (New-RollupJson -NextChild $script:childA) `
                -Match "*Rollup.$field does not match Children*" `
                -Mutate { param($Document) $Document.Rollup.$field++ }
            Add-InvalidRollupCase -Name "missing-$field" `
                -Json (New-RollupJson -NextChild $script:childA) `
                -Match "*Rollup.$field must be a nonnegative integer*" `
                -Mutate {
                param($Document)
                $Document.Rollup.PSObject.Properties.Remove($field)
            }
        }
        Add-InvalidRollupCase -Name 'negative-count' `
            -Json (New-RollupJson -NextChild $script:childA) `
            -Match '*Rollup.ChildCount must be a nonnegative integer*' `
            -Mutate { param($Document) $Document.Rollup.ChildCount = -1 }
        Add-InvalidRollupCase -Name 'fractional-count' `
            -Json (New-RollupJson -NextChild $script:childA) `
            -Match '*Rollup.CompleteCount must be a nonnegative integer*' `
            -Mutate { param($Document) $Document.Rollup.CompleteCount = 0.5 }
        Add-InvalidRollupCase -Name 'complete-rollup-false' `
            -Json (New-RollupJson -NextChild $null -Children @($completeA) `
                -IsComplete $false) -Match '*Rollup.IsComplete does not match Children*'
        Add-InvalidRollupCase -Name 'incomplete-rollup-true' `
            -Json (New-RollupJson -NextChild $script:childA `
                -Children @($incompleteA) -IsComplete $true) `
            -Match '*Rollup.IsComplete does not match Children*'
        Add-InvalidRollupCase -Name 'null-with-eligible' `
            -Json (New-RollupJson -NextChild $null -Children @($incompleteA)) `
            -Match '*NextChild is null*eligible*'
        Add-InvalidRollupCase -Name 'unknown-next' `
            -Json (New-RollupJson -NextChild $script:childB `
                -Children @($incompleteA)) `
            -Match '*NextChild must be the first*'
        Add-InvalidRollupCase -Name 'complete-next' `
            -Json (New-RollupJson -NextChild $script:childA `
                -Children @($completeA, $incompleteB)) `
            -Match '*NextChild must be the first*'
        Add-InvalidRollupCase -Name 'blocked-next' `
            -Json (New-RollupJson -NextChild $script:childA `
                -Children @($blockedA, $incompleteB)) `
            -Match '*NextChild must be the first*'
        Add-InvalidRollupCase -Name 'later-next' `
            -Json (New-RollupJson -NextChild $script:childB `
                -Children @($incompleteA, $incompleteB)) `
            -Match '*NextChild must be the first*'
        $childWithFolder = [ordered]@{
            Id = $script:childA.Id
            FolderName = $script:childA.FolderName
            IsComplete = $false
            IsBlocked = $false
        }
        $wrongFolderNext = [ordered]@{
            Id = $script:childA.Id
            Slug = $script:childA.Slug
            FolderName = 'wrong-folder'
            PlanFile = $script:childA.PlanFile
            NextStepId = $script:childA.NextStepId
        }
        Add-InvalidRollupCase -Name 'folder-mismatch' `
            -Json (New-RollupJson -NextChild $wrongFolderNext `
                -Children @($childWithFolder)) `
            -Match '*NextChild FolderName does not match child*'

        foreach ($case in $globalConsistencyCases) {
            $path = New-StatePath -Name "refresh-global-$($case.Name)"
            [System.IO.File]::WriteAllText(
                $path,
                (New-StateJson -Outcome 'awaiting-merge')
            )
            $before = [System.IO.File]::ReadAllText($path)
            $json = $case.Json
            $launches = 0
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $path `
                    -PlanStateInvoker {
                    param($EpicReference, $Root, $ScriptPath)
                    $json
                } -TargetResolver $resolveB -AncestorTester {
                    throw 'invalid global rollup must not probe ancestry'
                } -StateDeleteInvoker {
                    throw 'invalid global rollup must not delete state'
                } -LauncherInvoker {
                    $launches++
                    throw 'invalid global rollup must not launch'
                }
            } | Should -Throw $case.Match -Because $case.Name
            $launches | Should -Be 0 -Because $case.Name
            [System.IO.File]::ReadAllText($path) |
                Should -BeExactly $before -Because $case.Name
        }

        $completePath = New-StatePath -Name 'refresh-complete'
        [System.IO.File]::WriteAllText(
            $completePath,
            (New-StateJson -Outcome 'exit:0')
        )
        $completeRollup = New-RollupJson -NextChild $null `
            -Children @($completeA) -IsComplete $true
        $complete = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $completePath `
            -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $completeRollup
        } -TargetResolver $resolveB -AncestorTester $forward `
            -LauncherInvoker { throw 'complete epic must not launch' }
        $complete.Completed | Should -BeTrue
        $complete.Blocked | Should -BeFalse
        $complete.State | Should -BeNullOrEmpty
        Test-Path -LiteralPath $completePath | Should -BeFalse

        $blockedPath = New-StatePath -Name 'refresh-blocked'
        [System.IO.File]::WriteAllText(
            $blockedPath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $blockedBefore = [System.IO.File]::ReadAllText($blockedPath)
        $blockedRollup = New-RollupJson -NextChild $null `
            -Children @($blockedB, $completeA)
        $blocked = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $blockedPath `
            -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $blockedRollup
        } -TargetResolver $resolveB -AncestorTester $forward `
            -LauncherInvoker { throw 'blocked epic must not launch' }
        $blocked.Blocked | Should -BeTrue
        $blocked.Completed | Should -BeFalse
        $blocked.ExitCode | Should -Be 42
        $blocked.Message | Should -Match 'prior success checkpoint is retained'
        [System.IO.File]::ReadAllText($blockedPath) |
            Should -BeExactly $blockedBefore

        $nonForwardPath = New-StatePath -Name 'refresh-non-forward'
        [System.IO.File]::WriteAllText(
            $nonForwardPath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $nonForwardBefore = [System.IO.File]::ReadAllText($nonForwardPath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $nonForwardPath `
                -PlanStateInvoker {
                param($EpicReference, $Root, $ScriptPath)
                $reordered
            } -TargetResolver $resolveB `
                -AncestorTester { param($Ancestor, $Descendant, $Root) $false } `
                -LauncherInvoker { throw 'non-forward target must not launch' }
        } | Should -Throw '*not a forward descendant*'
        [System.IO.File]::ReadAllText($nonForwardPath) |
            Should -BeExactly $nonForwardBefore

        foreach ($outcome in @(
                'invocation-failed', 'exit:1', 'exit:3', 'exit:42', 'exit:43', 'exit:255'
            )) {
            $path = New-StatePath -Name ('refresh-immutable-' + $outcome.Replace(':', '-'))
            [System.IO.File]::WriteAllText($path, (New-StateJson -Outcome $outcome))
            $before = [System.IO.File]::ReadAllText($path)
            $terminal = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $path `
                -PlanStateInvoker {
                param($EpicReference, $Root, $ScriptPath)
                $reordered
            } -TargetResolver $resolveB `
                -AncestorTester { throw 'failed outcome must not probe ancestry' } `
                -LauncherInvoker { throw 'failed outcome must not launch' }
            $terminal.Replayed | Should -BeTrue -Because $outcome
            $terminal.State.outcome | Should -BeExactly $outcome
            [System.IO.File]::ReadAllText($path) |
                Should -BeExactly $before -Because $outcome
        }

        $replaceRacePath = New-StatePath -Name 'refresh-replace-race'
        [System.IO.File]::WriteAllText(
            $replaceRacePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $racedReplacement = New-StateJson -Outcome 'exit:42'
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $replaceRacePath `
                -PlanStateInvoker {
                param($EpicReference, $Root, $ScriptPath)
                $reordered
            } -TargetResolver $resolveB -AncestorTester $forward -RunFactory {
                [System.IO.File]::WriteAllText($replaceRacePath, $racedReplacement)
                $script:runB
            } -LauncherInvoker { throw 'CAS conflict must not launch' }
        } | Should -Throw '*replacement failed with status ''cas-conflict''*'
        [System.IO.File]::ReadAllText($replaceRacePath) |
            Should -BeExactly $racedReplacement

        $deleteRacePath = New-StatePath -Name 'refresh-delete-race'
        [System.IO.File]::WriteAllText(
            $deleteRacePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $racedDelete = New-StateJson -Outcome 'exit:42'
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $deleteRacePath `
                -PlanStateInvoker {
                param($EpicReference, $Root, $ScriptPath)
                $completeRollup
            } -TargetResolver $resolveB -AncestorTester $forward `
                -StateDeleteInvoker {
                param($Path, $ExpectedGeneration)
                [System.IO.File]::WriteAllText($Path, $racedDelete)
                [pscustomobject]@{ Status = 'cas-conflict' }
            } -LauncherInvoker { throw 'delete CAS conflict must not launch' }
        } | Should -Throw '*delete failed with status ''cas-conflict''*'
        [System.IO.File]::ReadAllText($deleteRacePath) |
            Should -BeExactly $racedDelete
    }

    It 'test:EpicAutopilot.FinalCrosscheck gates completion, records evidence, and never creates a finalization delivery' {
        $completeA = [ordered]@{
            Id = $script:childA.Id
            IsComplete = $true
            IsBlocked = $false
            PlanFile = $script:planFileA
        }
        $completeRollup = New-RollupJson -NextChild $null `
            -Children @($completeA) -IsComplete $true
        $resolveB = { param($Reference, $Root) $script:targetB }
        $forward = { param($Ancestor, $Descendant, $Root) $true }
        $reviewScript = Join-Path $script:fixtureRoot (
            'installed-review/Invoke-EpicCoherencyReview.ps1'
        )
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $reviewScript
            ) -Force)
        [System.IO.File]::WriteAllText($reviewScript, "exit 0`n")
        $missingReview = Join-Path $script:fixtureRoot (
            'missing/Invoke-EpicCoherencyReview.ps1'
        )

        $noCheckpointPath = New-StatePath -Name 'final-no-checkpoint'
        $noCheckpointRecords = [System.Collections.Generic.List[string]]::new()
        $noCheckpoint = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $noCheckpointPath `
            -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
            -ReviewScriptPath $missingReview -FinalEvidenceRecorder {
            param($ScriptPath, $PlanDir, $Message)
            [void]$noCheckpointRecords.Add($Message)
            return 0
        } -LauncherInvoker { throw 'complete no-checkpoint epic must not launch' }
        $noCheckpoint.Completed | Should -BeTrue
        $noCheckpoint.Blocked | Should -BeFalse
        $noCheckpoint.ExitCode | Should -Be 0
        $noCheckpoint.FinalCrosscheck | Should -BeExactly 'fallback'
        $noCheckpointRecords | Should -HaveCount 1
        Test-Path -LiteralPath $noCheckpointPath | Should -BeFalse

        $incompleteNoCheckpoint = New-RollupJson -NextChild $null
        $incompletePath = New-StatePath -Name 'incomplete-no-checkpoint'
        $incomplete = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $incompletePath `
            -PlanStateInvoker { $incompleteNoCheckpoint } `
            -TargetResolver $resolveB `
            -FinalEvidenceRecorder { throw 'blocked epic must not publish evidence' } `
            -LauncherInvoker { throw 'blocked epic must not launch' }
        $incomplete.Completed | Should -BeFalse
        $incomplete.Blocked | Should -BeTrue
        $incomplete.ExitCode | Should -Be 42
        Test-Path -LiteralPath $incompletePath | Should -BeFalse

        $failedNoCheckpointPath = New-StatePath -Name 'final-no-checkpoint-review-failure'
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $failedNoCheckpointPath `
                -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
                -ReviewScriptPath $reviewScript -ReviewInvoker { 9 } `
                -FinalEvidenceRecorder {
                throw 'failed no-checkpoint review must not publish evidence'
            } -LauncherInvoker { throw 'failed no-checkpoint review must not launch' }
        } | Should -Throw "*failed with exit code '9'*"
        Test-Path -LiteralPath $failedNoCheckpointPath | Should -BeFalse

        $availablePath = New-StatePath -Name 'final-review-available'
        [System.IO.File]::WriteAllText(
            $availablePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $reviewCalls = [System.Collections.Generic.List[object]]::new()
        $recordCalls = [System.Collections.Generic.List[object]]::new()
        $available = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $availablePath `
            -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
            -AncestorTester $forward -ReviewScriptPath $reviewScript `
            -ReviewInvoker {
            param($ScriptPath, $EpicFile, $TargetCommit, $Root)
            [void]$reviewCalls.Add([pscustomobject]@{
                    Script = $ScriptPath
                    Epic = $EpicFile
                    Target = $TargetCommit
                    Root = $Root
                })
            return 0
        } -FinalEvidenceRecorder {
            param($ScriptPath, $PlanDir, $Message, $ReviewType, $Root)
            (Read-TestEpicState -Path $availablePath).outcome |
                Should -BeExactly 'awaiting-merge'
            [void]$recordCalls.Add([pscustomobject]@{
                    PlanDir = $PlanDir
                    Message = $Message
                    ReviewType = $ReviewType
                })
            return 0
        } -LauncherInvoker { throw 'final crosscheck must not launch a child' }

        $available.Completed | Should -BeTrue
        $available.FinalCrosscheck | Should -BeExactly 'review'
        $available.State | Should -BeNullOrEmpty
        Test-Path -LiteralPath $availablePath | Should -BeFalse
        $reviewCalls | Should -HaveCount 1
        $reviewCalls[0].Script | Should -BeExactly $reviewScript
        $reviewCalls[0].Epic | Should -BeExactly $script:epicFile
        $reviewCalls[0].Target | Should -BeExactly $script:targetB
        $recordCalls | Should -HaveCount 1
        $recordCalls[0].PlanDir |
            Should -BeExactly (Split-Path -Parent $script:planFileA)
        $recordCalls[0].ReviewType | Should -BeExactly 'dr'
        $recordCalls[0].Message | Should -Match 'installed simplified'

        $fallbackPath = New-StatePath -Name 'final-review-fallback'
        [System.IO.File]::WriteAllText(
            $fallbackPath,
            (New-StateJson -Outcome 'exit:0')
        )
        $fallbackRecords = [System.Collections.Generic.List[object]]::new()
        $fallback = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $fallbackPath `
            -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
            -AncestorTester $forward -ReviewScriptPath $missingReview `
            -ReviewInvoker { throw 'absent review must use the bounded fallback' } `
            -FinalEvidenceRecorder {
            param($ScriptPath, $PlanDir, $Message, $ReviewType, $Root)
            [void]$fallbackRecords.Add([pscustomobject]@{
                    Message = $Message
                    ReviewType = $ReviewType
                })
            return 0
        } -LauncherInvoker { throw 'fallback completion must not launch' }
        $fallback.Completed | Should -BeTrue
        $fallback.FinalCrosscheck | Should -BeExactly 'fallback'
        Test-Path -LiteralPath $fallbackPath | Should -BeFalse
        $fallbackRecords | Should -HaveCount 1
        $fallbackRecords[0].ReviewType | Should -BeExactly 'none'
        $fallbackRecords[0].Message |
            Should -Match 'complete merged rollup.*Goal and Definition of done'

        foreach ($case in @(
                @{ Name = 'degraded'; Result = @(3); Match = '*failed with exit code ''3''*' },
                @{ Name = 'malformed'; Result = @('degraded'); Match = '*invalid exit code*' },
                @{ Name = 'duplicate'; Result = @(0, 0); Match = '*exactly one exit code*' }
            )) {
            $path = New-StatePath -Name "final-review-$($case.Name)"
            [System.IO.File]::WriteAllText(
                $path,
                (New-StateJson -Outcome 'awaiting-merge')
            )
            $before = [System.IO.File]::ReadAllText($path)
            $result = @($case.Result)
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $path `
                    -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
                    -AncestorTester $forward -ReviewScriptPath $reviewScript `
                    -ReviewInvoker { $result | ForEach-Object { Write-Output $_ } } `
                    -FinalEvidenceRecorder { throw 'failed review must not record a pass' } `
                    -LauncherInvoker { throw 'failed review must not launch' }
            } | Should -Throw $case.Match -Because $case.Name
            [System.IO.File]::ReadAllText($path) |
                Should -BeExactly $before -Because $case.Name
        }

        $startFailurePath = New-StatePath -Name 'final-review-start-failure'
        [System.IO.File]::WriteAllText(
            $startFailurePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $startFailureBefore = [System.IO.File]::ReadAllBytes($startFailurePath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $startFailurePath `
                -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
                -AncestorTester $forward -ReviewScriptPath $reviewScript `
                -ReviewInvoker { throw 'synthetic installed-review start failure' } `
                -FinalEvidenceRecorder {
                throw 'review start failure must not record a pass'
            } -LauncherInvoker { throw 'review start failure must not launch' }
        } | Should -Throw '*synthetic installed-review start failure*'
        [System.IO.File]::ReadAllBytes($startFailurePath) |
            Should -Be $startFailureBefore

        foreach ($invalidEpic in @(
                @{
                    Name = 'missing-goal'
                    Text = "# abc123`n`n## Definition of done`n`nComplete.`n"
                    Match = "*non-empty 'Goal' section*"
                },
                @{
                    Name = 'missing-done'
                    Text = "# abc123`n`n## Goal`n`nShip.`n"
                    Match = "*non-empty 'Definition of done' section*"
                }
            )) {
            $epicPath = Join-Path $script:fixtureRoot "$($invalidEpic.Name)/epic.md"
            [void](New-Item -ItemType Directory -Path (
                    Split-Path -Parent $epicPath
                ) -Force)
            [System.IO.File]::WriteAllText($epicPath, $invalidEpic.Text)
            $rollup = New-RollupJson -NextChild $null -Children @($completeA) `
                -IsComplete $true -EpicFile $epicPath
            $path = New-StatePath -Name "final-fallback-$($invalidEpic.Name)"
            [System.IO.File]::WriteAllText(
                $path,
                (New-StateJson -Outcome 'awaiting-merge')
            )
            $before = [System.IO.File]::ReadAllText($path)
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $script:repoRoot -StatePath $path `
                    -PlanStateInvoker { $rollup } -TargetResolver $resolveB `
                    -AncestorTester $forward -ReviewScriptPath $missingReview `
                    -FinalEvidenceRecorder { throw 'failed fallback must not record' } `
                    -LauncherInvoker { throw 'failed fallback must not launch' }
            } | Should -Throw $invalidEpic.Match
            [System.IO.File]::ReadAllText($path) | Should -BeExactly $before
        }

        $recordFailurePath = New-StatePath -Name 'final-record-failure'
        [System.IO.File]::WriteAllText(
            $recordFailurePath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $recordFailureBefore = [System.IO.File]::ReadAllText($recordFailurePath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $recordFailurePath `
                -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
                -AncestorTester $forward -ReviewScriptPath $missingReview `
                -FinalEvidenceRecorder { 5 } `
                -LauncherInvoker { throw 'record failure must not launch' }
        } | Should -Throw "*evidence writer failed with exit code '5'*"
        [System.IO.File]::ReadAllText($recordFailurePath) |
            Should -BeExactly $recordFailureBefore

        $replayPath = New-StatePath -Name 'final-delete-replay'
        [System.IO.File]::WriteAllText(
            $replayPath,
            (New-StateJson -Outcome 'awaiting-merge')
        )
        $replayRecords = [System.Collections.Generic.List[string]]::new()
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $replayPath `
                -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
                -AncestorTester $forward -ReviewScriptPath $missingReview `
                -FinalEvidenceRecorder {
                param($ScriptPath, $PlanDir, $Message)
                [void]$replayRecords.Add($Message)
                return 0
            } -StateDeleteInvoker {
                [pscustomobject]@{ Status = 'cas-conflict' }
            } -LauncherInvoker { throw 'delete failure must not launch' }
        } | Should -Throw "*delete failed with status 'cas-conflict'*"
        Test-Path -LiteralPath $replayPath | Should -BeTrue
        $replayed = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $replayPath `
            -PlanStateInvoker { $completeRollup } -TargetResolver $resolveB `
            -AncestorTester $forward -ReviewScriptPath $missingReview `
            -FinalEvidenceRecorder {
            param($ScriptPath, $PlanDir, $Message)
            [void]$replayRecords.Add($Message)
            return 0
        } -LauncherInvoker { throw 'complete replay must not launch' }
        $replayed.Completed | Should -BeTrue
        $replayed.FinalCrosscheck | Should -BeExactly 'fallback'
        $replayRecords | Should -HaveCount 2
        $replayRecords[0] | Should -BeExactly $replayRecords[1]
        Test-Path -LiteralPath $replayPath | Should -BeFalse

        $evidenceRoot = Join-Path $script:fixtureRoot 'final-evidence-production'
        $epicDir = Join-Path $evidenceRoot (
            'docs/implementation-plans/epics/2026-08-31-abc123-fixture-epic'
        )
        $planDir = Join-Path $evidenceRoot (
            'docs/implementation-plans/2026-08-31-111111-first-child'
        )
        $capturePath = Join-Path $planDir 'capture.md'
        [void](New-Item -ItemType Directory -Path $epicDir -Force)
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $capturePath
            ) -Force)
        $integrationEpic = Join-Path $epicDir 'epic.md'
        $integrationPlan = Join-Path $planDir 'plan.md'
        [System.IO.File]::WriteAllText(
            $integrationEpic,
            "# abc123: Fixture epic`n<!-- epic-id: abc123 -->`n`n## Goal`n`nShip.`n`n## Definition of done`n`nAll children complete.`n"
        )
        [System.IO.File]::WriteAllText(
            $integrationPlan,
            @(
                '# 111111: First child'
                '<!-- plan-id: 111111 -->'
                '<!-- epic: abc123 -->'
                '<!-- cip-stage: done -->'
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Fixture | `test:fixture` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
                '- [x] 1.1 Execute fixture (REQ-1) `S`'
            ) -join "`n"
        )
        [System.IO.File]::WriteAllText(
            $capturePath,
            "## Capture`nPhase: 0`n`nNo entries for this phase.`n"
        )
        & git -C $evidenceRoot init --initial-branch=main --quiet
        $LASTEXITCODE | Should -Be 0
        & git -C $evidenceRoot config user.name 'Epic Autopilot Test'
        & git -C $evidenceRoot config user.email 'epic-autopilot@example.invalid'
        & git -C $evidenceRoot add -- .
        & git -C $evidenceRoot commit --quiet -m 'fixture base'
        $LASTEXITCODE | Should -Be 0
        $baseCommit = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        [System.IO.File]::WriteAllText(
            (Join-Path $evidenceRoot 'operator-merge.txt'),
            "operator merge`n"
        )
        & git -C $evidenceRoot add -- operator-merge.txt
        & git -C $evidenceRoot commit --quiet -m 'operator merge'
        $LASTEXITCODE | Should -Be 0
        $reviewedTarget = (& git -C $evidenceRoot rev-parse HEAD).Trim()

        $integrationState = Join-Path $script:fixtureRoot (
            'final-evidence-production-state.json'
        )
        [System.IO.File]::WriteAllText(
            $integrationState,
            (New-StateJson -Target $baseCommit -Outcome 'awaiting-merge')
        )
        $integrationStateBefore = [System.IO.File]::ReadAllText($integrationState)
        $integrationComplete = [ordered]@{
            Id = $script:childA.Id
            IsComplete = $true
            IsBlocked = $false
            PlanFile = $integrationPlan
        }
        $integrationRollup = New-RollupJson -NextChild $null `
            -Children @($integrationComplete) -IsComplete $true `
            -EpicFile $integrationEpic
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $evidenceRoot -StatePath $integrationState `
                -PlanStateInvoker { $integrationRollup } `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -FinalEvidenceRecorder {
                param($ScriptPath, $PlanDir)
                [System.IO.File]::WriteAllText(
                    (Join-Path $PlanDir 'capture.md'),
                    "partial evidence`n"
                )
                return 5
            }
        } | Should -Throw "*evidence writer failed with exit code '5'*"
        [System.IO.File]::ReadAllText($integrationState) |
            Should -BeExactly $integrationStateBefore
        (& git -C $evidenceRoot rev-parse HEAD).Trim() |
            Should -BeExactly $reviewedTarget
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        [System.IO.File]::ReadAllText($capturePath) |
            Should -BeExactly "## Capture`nPhase: 0`n`nNo entries for this phase.`n"

        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $evidenceRoot -StatePath $integrationState `
                -PlanStateInvoker { $integrationRollup } `
                -UseDefaultFinalEvidenceRecorder `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -StateDeleteInvoker {
                [pscustomobject]@{ Status = 'cas-conflict' }
            } -LauncherInvoker { throw 'evidence integration must not launch' }
        } | Should -Throw "*delete failed with status 'cas-conflict'*"
        [System.IO.File]::ReadAllText($integrationState) |
            Should -BeExactly $integrationStateBefore
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        $evidenceCommit = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        $evidenceCommit | Should -Not -BeExactly $reviewedTarget
        (& git -C $evidenceRoot rev-parse "$evidenceCommit^").Trim() |
            Should -BeExactly $reviewedTarget
        [int](& git -C $evidenceRoot rev-list --count "$reviewedTarget..main") |
            Should -Be 1
        @(
            & git -C $evidenceRoot diff-tree --no-commit-id --name-only -r `
                $reviewedTarget $evidenceCommit
        ) | Should -BeExactly @(
            'docs/implementation-plans/2026-08-31-111111-first-child/capture.md'
        )
        (& git -C $evidenceRoot show -s --format=%B $evidenceCommit) -join "`n" |
            Should -Match "Epic-Autopilot-Reviewed-Target: $reviewedTarget"

        $integrated = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $evidenceRoot -StatePath $integrationState `
            -PlanStateInvoker { $integrationRollup } `
            -UseDefaultFinalEvidenceRecorder `
            -UseDefaultFinalEvidenceTransaction `
            -UseDefaultWorktreeValidator `
            -LauncherInvoker { throw 'evidence replay must not launch' }
        $integrated.Completed | Should -BeTrue
        $integrated.FinalCrosscheck | Should -BeExactly 'fallback'
        Test-Path -LiteralPath $integrationState | Should -BeFalse
        (& git -C $evidenceRoot rev-parse HEAD).Trim() |
            Should -BeExactly $evidenceCommit
        [int](& git -C $evidenceRoot rev-list --count "$reviewedTarget..main") |
            Should -Be 1
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        $capture = [System.IO.File]::ReadAllText($capturePath)
        $capture | Should -Match 'Epic final crosscheck passed via fallback'
        $capture | Should -Match '\[concern:architecture-patterns\]'
        $capture | Should -Match '\[review:none\]'
        $capture | Should -Match '\[source-record:[0-9a-f]{64}\]'
        ([regex]::Matches(
            $capture,
            'Epic final crosscheck passed via fallback'
        )).Count | Should -Be 1

        $wrongHeadState = Join-Path $script:fixtureRoot (
            'final-evidence-wrong-head-state.json'
        )
        [System.IO.File]::WriteAllText(
            $wrongHeadState,
            (New-StateJson -Target $baseCommit -Outcome 'awaiting-merge')
        )
        $wrongHeadBefore = [System.IO.File]::ReadAllText($wrongHeadState)
        & git -C $evidenceRoot update-ref --no-deref HEAD $evidenceCommit
        $LASTEXITCODE | Should -Be 0
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $evidenceRoot -StatePath $wrongHeadState `
                -PlanStateInvoker { $integrationRollup } `
                -UseDefaultFinalEvidenceRecorder `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator
        } | Should -Throw '*must be attached to checked-out target ref*'
        [System.IO.File]::ReadAllText($wrongHeadState) |
            Should -BeExactly $wrongHeadBefore
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        & git -C $evidenceRoot symbolic-ref HEAD refs/heads/main
        $LASTEXITCODE | Should -Be 0

        $concurrentState = Join-Path $script:fixtureRoot (
            'final-evidence-concurrent-state.json'
        )
        [System.IO.File]::WriteAllText(
            $concurrentState,
            (New-StateJson -Target $baseCommit -Outcome 'awaiting-merge')
        )
        $concurrentBefore = [System.IO.File]::ReadAllText($concurrentState)
        $concurrentCommit = [pscustomobject]@{ Value = $null }
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $evidenceRoot -StatePath $concurrentState `
                -PlanStateInvoker { $integrationRollup } `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -FinalEvidenceRecorder {
                param($ScriptPath, $PlanDir, $Message, $ReviewType, $Root)
                $tree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
                $parent = (& git -C $Root rev-parse HEAD).Trim()
                $created = (
                    & git -C $Root commit-tree $tree -p $parent `
                        -m 'concurrent target movement'
                ).Trim()
                & git -C $Root update-ref refs/heads/main $created $parent
                $concurrentCommit.Value = $created
                return 0
            }
        } | Should -Throw "*moved from expected commit '$evidenceCommit'*"
        [System.IO.File]::ReadAllText($concurrentState) |
            Should -BeExactly $concurrentBefore
        (& git -C $evidenceRoot rev-parse HEAD).Trim() |
            Should -BeExactly $concurrentCommit.Value
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0

        $ignoredReviewPath = Join-Path $evidenceRoot (
            '.github/skills/cep/scripts/Invoke-EpicCoherencyReview.ps1'
        )
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $ignoredReviewPath
            ) -Force)
        [System.IO.File]::WriteAllText(
            (Join-Path $evidenceRoot '.git/info/exclude'),
            "/.github/skills/cep/scripts/Invoke-EpicCoherencyReview.ps1`n"
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $evidenceRoot 'ignored-review-operator-merge.txt'),
            "operator merge`n"
        )
        & git -C $evidenceRoot add -- ignored-review-operator-merge.txt
        & git -C $evidenceRoot commit --quiet -m 'operator merge before ignored review'
        $ignoredReviewTarget = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        [System.IO.File]::WriteAllText(
            $ignoredReviewPath,
            "throw 'ignored mutable review must never execute'`n"
        )
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        $ignoredReviewState = Join-Path $script:fixtureRoot (
            'final-evidence-ignored-review-state.json'
        )
        [System.IO.File]::WriteAllText(
            $ignoredReviewState,
            (New-StateJson -Target $concurrentCommit.Value `
                -Outcome 'awaiting-merge')
        )
        $ignoredReview = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $evidenceRoot -StatePath $ignoredReviewState `
            -PlanStateInvoker { $integrationRollup } `
            -UseDefaultFinalEvidenceTransaction `
            -UseDefaultWorktreeValidator `
            -ReviewInvoker {
            throw 'target-absent ignored review must not be invoked'
        } -FinalEvidenceRecorder {
            param($ScriptPath, $PlanDir)
            [System.IO.File]::AppendAllText(
                (Join-Path $PlanDir 'capture.md'),
                "target-bound fallback replay`n"
            )
            return 0
        } -LauncherInvoker { throw 'ignored review crosscheck must not launch' }
        $ignoredReview.Completed | Should -BeTrue
        $ignoredReview.FinalCrosscheck | Should -BeExactly 'fallback'
        Test-Path -LiteralPath $ignoredReviewState | Should -BeFalse
        Remove-Item -LiteralPath $ignoredReviewPath -Force
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0
        $ignoredReviewEvidence = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        (& git -C $evidenceRoot rev-parse "$ignoredReviewEvidence^").Trim() |
            Should -BeExactly $ignoredReviewTarget

        [System.IO.File]::WriteAllText(
            $ignoredReviewPath,
            @'
param(
    [string]$EpicFile,
    [string]$TargetCommit,
    [string]$RepoRoot
)
if (-not (Test-Path -LiteralPath $EpicFile -PathType Leaf) -or
    $TargetCommit -notmatch '^[0-9a-f]{40}$' -or
    -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    exit 9
}
exit 0
'@
        )
        & git -C $evidenceRoot add -f -- (
            '.github/skills/cep/scripts/Invoke-EpicCoherencyReview.ps1'
        )
        & git -C $evidenceRoot commit --quiet -m 'install simplified review'
        $installedReviewTarget = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        & git -C $evidenceRoot branch preserved-ref $installedReviewTarget
        & git -C $evidenceRoot tag preserved-tag $installedReviewTarget
        $refInventory = @(
            & git -C $evidenceRoot for-each-ref `
                '--format=%(refname) %(objectname)' refs
        )
        $installedReviewState = Join-Path $script:fixtureRoot (
            'final-evidence-installed-review-state.json'
        )
        [System.IO.File]::WriteAllText(
            $installedReviewState,
            (New-StateJson -Target $ignoredReviewEvidence `
                -Outcome 'awaiting-merge')
        )
        $installedReviewStateBefore = [System.IO.File]::ReadAllText(
            $installedReviewState
        )
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $evidenceRoot -StatePath $installedReviewState `
                -PlanStateInvoker { $integrationRollup } `
                -UseDefaultFinalEvidenceRecorder `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -StateDeleteInvoker {
                [pscustomobject]@{ Status = 'cas-conflict' }
            } -LauncherInvoker { throw 'installed review must not launch a child' }
        } | Should -Throw "*delete failed with status 'cas-conflict'*"
        [System.IO.File]::ReadAllText($installedReviewState) |
            Should -BeExactly $installedReviewStateBefore
        $installedReviewEvidence = (& git -C $evidenceRoot rev-parse HEAD).Trim()
        (& git -C $evidenceRoot rev-parse "$installedReviewEvidence^").Trim() |
            Should -BeExactly $installedReviewTarget
        @(
            & git -C $evidenceRoot diff-tree --no-commit-id --name-only -r `
                $installedReviewTarget $installedReviewEvidence
        ) | Should -BeExactly @(
            'docs/implementation-plans/2026-08-31-111111-first-child/capture.md'
        )
        $installedCapture = [System.IO.File]::ReadAllText($capturePath)
        $installedCapture |
            Should -Match 'passed via installed simplified epic coherency review'

        $installedReplay = Invoke-TestEpicHostLoop -Epic 'abc123' `
            -Target 'main' -RepoRoot $evidenceRoot `
            -StatePath $installedReviewState `
            -PlanStateInvoker { $integrationRollup } `
            -UseDefaultFinalEvidenceRecorder `
            -UseDefaultFinalEvidenceTransaction `
            -UseDefaultWorktreeValidator `
            -LauncherInvoker { throw 'installed review replay must not launch' }
        $installedReplay.Completed | Should -BeTrue
        $installedReplay.FinalCrosscheck | Should -BeExactly 'review'
        Test-Path -LiteralPath $installedReviewState | Should -BeFalse
        (& git -C $evidenceRoot rev-parse HEAD).Trim() |
            Should -BeExactly $installedReviewEvidence
        ([regex]::Matches(
            [System.IO.File]::ReadAllText($capturePath),
            'passed via installed simplified epic coherency review'
        )).Count | Should -Be 1
        $refsAfter = @(
            & git -C $evidenceRoot for-each-ref `
                '--format=%(refname) %(objectname)' refs
        )
        @($refsAfter | ForEach-Object { ($_ -split ' ', 2)[0] }) |
            Should -BeExactly @(
                $refInventory | ForEach-Object { ($_ -split ' ', 2)[0] }
            )
        @($refsAfter | Where-Object { $_ -notmatch '^refs/heads/main ' }) |
            Should -BeExactly @(
                $refInventory |
                    Where-Object { $_ -notmatch '^refs/heads/main ' }
                )
        $refsAfter | Should -Not -Match '(?i)finalization|evidence'
        @(& git -C $evidenceRoot status --porcelain=v1) |
            Should -HaveCount 0

        $moduleText = [System.IO.File]::ReadAllText($script:modulePath)
        $moduleText | Should -Not -Match '(?i)\bgit\s+(?:push|merge|checkout)\b'
        $moduleText | Should -Not -Match '(?i)\bgh\s+(?:api|pr)\b'
        $moduleText | Should -Not -Match '(?i)\b(?:new|create).*(?:branch|pull request|pr)\b'
        $moduleText | Should -Not -Match '(?i)&\s*gh(?:\.exe)?\b'
        $moduleText | Should -Not -Match (
            '(?i)&\s*git(?:\.exe)?\b[^\r\n]*\s' +
            '(?:push|pull|fetch|remote|branch|switch|checkout)\b'
        )
    }

    It 'test:EpicAutopilot.NoCheckpointProductionFinalization publishes one Capture-only commit and replays idempotently' {
        $fixture = New-FinalEvidenceGitFixture `
            -Name 'final-evidence-no-checkpoint-production' -NoCheckpoint
        Test-Path -LiteralPath $fixture.StatePath |
            Should -BeFalse -Because 'the production completion path starts without a checkpoint'

        $first = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $fixture.Root -StatePath $fixture.StatePath `
            -PlanStateInvoker { $fixture.Rollup } `
            -UseDefaultFinalEvidenceRecorder `
            -UseDefaultFinalEvidenceTransaction `
            -UseDefaultWorktreeValidator `
            -LauncherInvoker { throw 'complete no-checkpoint epic must not launch' }

        $first.Completed | Should -BeTrue
        $first.FinalCrosscheck | Should -BeExactly 'fallback'
        Test-Path -LiteralPath $fixture.StatePath | Should -BeFalse
        $evidenceCommit = (& git -C $fixture.Root rev-parse HEAD).Trim()
        $parents = @(
            (& git -C $fixture.Root show -s --format=%P $evidenceCommit).Trim() `
                -split ' '
        )
        $parents | Should -BeExactly @($fixture.TargetCommit)
        [int](& git -C $fixture.Root rev-list --count (
                "$($fixture.TargetCommit)..main"
            )) | Should -Be 1
        @(
            & git -C $fixture.Root diff-tree --no-commit-id --name-only -r `
                $fixture.TargetCommit $evidenceCommit
        ) | Should -BeExactly @(
            [System.IO.Path]::GetRelativePath(
                $fixture.Root,
                $fixture.CapturePath
            ).Replace('\', '/')
        )
        @(& git -C $fixture.Root status --porcelain=v1) |
            Should -HaveCount 0

        $replay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $fixture.Root -StatePath $fixture.StatePath `
            -PlanStateInvoker { $fixture.Rollup } `
            -UseDefaultFinalEvidenceRecorder `
            -UseDefaultFinalEvidenceTransaction `
            -UseDefaultWorktreeValidator `
            -LauncherInvoker { throw 'final evidence replay must not launch' }

        $replay.Completed | Should -BeTrue
        $replay.FinalCrosscheck | Should -BeExactly 'fallback'
        Test-Path -LiteralPath $fixture.StatePath | Should -BeFalse
        (& git -C $fixture.Root rev-parse HEAD).Trim() |
            Should -BeExactly $evidenceCommit
        [int](& git -C $fixture.Root rev-list --count (
                "$($fixture.TargetCommit)..main"
            )) | Should -Be 1
        @(& git -C $fixture.Root status --porcelain=v1) |
            Should -HaveCount 0
        ([regex]::Matches(
            [System.IO.File]::ReadAllText($fixture.CapturePath),
            'Epic final crosscheck passed via fallback'
        )).Count | Should -Be 1
    }

    It 'test:EpicAutopilot.AbruptEvidenceRecovery admits only exact writer or staging residue' {
        function Add-AbruptEvidenceRecord {
            param([Parameter(Mandatory)]$Fixture)

            $result = & $script:workflowNoteWriter -Kind Capture `
                -PlanDir $Fixture.PlanDir `
                -Phase 0 `
                -Message 'Epic final crosscheck passed via fallback: complete merged rollup and non-empty canonical Goal and Definition of done.' `
                -Src note -Concern architecture-patterns -ReviewType none `
                -RepoRoot $Fixture.Root
            $result.Status | Should -BeExactly 'complete'
        }

        foreach ($case in @(
                @{
                    Name = 'abrupt-post-writer'
                    Stage = $false
                    Folder = '2026-08-31-111111-first-child'
                },
                @{
                    Name = 'abrupt-post-stage'
                    Stage = $true
                    Folder = '2026-08-31-111111-first-child'
                },
                @{
                    Name = 'abrupt-prefixed-post-writer'
                    Stage = $false
                    Folder = 'abc123-2026-08-31-111111-first-child'
                }
            )) {
            $fixture = New-FinalEvidenceGitFixture -Name $case.Name `
                -PlanFolder $case.Folder
            Add-AbruptEvidenceRecord -Fixture $fixture
            if ($case.Stage) {
                & git -C $fixture.Root add -- (
                    [System.IO.Path]::GetRelativePath(
                        $fixture.Root,
                        $fixture.CapturePath
                    )
                )
            }

            $completed = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $fixture.Root -StatePath $fixture.StatePath `
                -PlanStateInvoker { $fixture.Rollup } `
                -UseDefaultFinalEvidenceRecorder `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -LauncherInvoker { throw 'recovery must not launch' }

            $completed.Completed | Should -BeTrue
            Test-Path -LiteralPath $fixture.StatePath | Should -BeFalse
            @(& git -C $fixture.Root status --porcelain=v1) |
                Should -HaveCount 0
            [int](& git -C $fixture.Root rev-list --count (
                    "$($fixture.TargetCommit)..main"
                )) | Should -Be 1
            $capture = [System.IO.File]::ReadAllText($fixture.CapturePath)
            ([regex]::Matches(
                $capture,
                'Epic final crosscheck passed via fallback'
            )).Count | Should -Be 1
        }

        foreach ($invalid in @(
                @{
                    Name = 'abrupt-legacy-folder'
                    Folder = '123-first-child'
                    PlanId = '123'
                    EpicId = 'abc123'
                    Match = '*legacy three-digit plan folder*'
                },
                @{
                    Name = 'abrupt-wrong-prefix'
                    Folder = 'def456-2026-08-31-111111-first-child'
                    PlanId = '111111'
                    EpicId = 'abc123'
                    Match = "*prefix 'def456' does not match epic 'abc123'*"
                },
                @{
                    Name = 'abrupt-standalone-prefix'
                    Folder = 'standalone-2026-08-31-111111-first-child'
                    PlanId = '111111'
                    EpicId = 'abc123'
                    Match = "*prefix 'standalone' does not match epic 'abc123'*"
                },
                @{
                    Name = 'abrupt-wrong-membership'
                    Folder = 'abc123-2026-08-31-111111-first-child'
                    PlanId = '111111'
                    EpicId = 'def456'
                    Match = "*header epic membership 'abc123'*"
                }
            )) {
            $fixture = New-FinalEvidenceGitFixture -Name $invalid.Name `
                -PlanFolder $invalid.Folder -PlanId $invalid.PlanId `
                -EpicId $invalid.EpicId
            Add-AbruptEvidenceRecord -Fixture $fixture
            $stateBefore = [System.IO.File]::ReadAllBytes($fixture.StatePath)
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $fixture.Root -StatePath $fixture.StatePath `
                    -PlanStateInvoker { $fixture.Rollup } `
                    -UseDefaultFinalEvidenceRecorder `
                    -UseDefaultFinalEvidenceTransaction `
                    -UseDefaultWorktreeValidator
            } | Should -Throw $invalid.Match -Because $invalid.Name
            [System.IO.File]::ReadAllBytes($fixture.StatePath) |
                Should -Be $stateBefore
        }

        $forged = New-FinalEvidenceGitFixture -Name 'abrupt-forged'
        Add-AbruptEvidenceRecord -Fixture $forged
        [System.IO.File]::AppendAllText($forged.CapturePath, "forged`n")
        $forgedState = [System.IO.File]::ReadAllBytes($forged.StatePath)
        $forgedCapture = [System.IO.File]::ReadAllBytes($forged.CapturePath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $forged.Root -StatePath $forged.StatePath `
                -PlanStateInvoker { $forged.Rollup } `
                -UseDefaultFinalEvidenceRecorder `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator
        } | Should -Throw '*does not match deterministic writer output*'
        [Convert]::ToBase64String(
            [System.IO.File]::ReadAllBytes($forged.StatePath)
        ) | Should -BeExactly ([Convert]::ToBase64String($forgedState))
        [Convert]::ToBase64String(
            [System.IO.File]::ReadAllBytes($forged.CapturePath)
        ) | Should -BeExactly ([Convert]::ToBase64String($forgedCapture))
        (& git -C $forged.Root rev-parse HEAD).Trim() |
            Should -BeExactly $forged.TargetCommit

        $concurrent = New-FinalEvidenceGitFixture -Name 'abrupt-concurrent'
        Add-AbruptEvidenceRecord -Fixture $concurrent
        $concurrentState = [System.IO.File]::ReadAllBytes($concurrent.StatePath)
        $concurrentCapture = [System.IO.File]::ReadAllBytes(
            $concurrent.CapturePath
        )
        $movedCommit = [pscustomobject]@{ Value = $null }
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $concurrent.Root -StatePath $concurrent.StatePath `
                -PlanStateInvoker { $concurrent.Rollup } `
                -UseDefaultFinalEvidenceTransaction `
                -UseDefaultWorktreeValidator `
                -FinalEvidenceRecorder {
                param($ScriptPath, $PlanDir, $Message, $ReviewType, $Root)
                & $script:workflowNoteWriter -Kind Capture `
                    -PlanDir $PlanDir -Phase 0 `
                    -Message $Message -Src note `
                    -Concern architecture-patterns -ReviewType $ReviewType `
                    -RepoRoot $Root | Out-Null
                $parent = (& git -C $Root rev-parse HEAD).Trim()
                $tree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
                $created = (
                    & git -C $Root commit-tree $tree -p $parent `
                        -m 'concurrent recovery movement'
                ).Trim()
                & git -C $Root update-ref refs/heads/main $created $parent
                $movedCommit.Value = $created
                return 0
            }
        } | Should -Throw "*moved from expected commit '$($concurrent.TargetCommit)'*"
        [Convert]::ToBase64String(
            [System.IO.File]::ReadAllBytes($concurrent.StatePath)
        ) | Should -BeExactly (
            [Convert]::ToBase64String($concurrentState)
        )
        [Convert]::ToBase64String(
            [System.IO.File]::ReadAllBytes($concurrent.CapturePath)
        ) | Should -BeExactly (
            [Convert]::ToBase64String($concurrentCapture)
        )
        (& git -C $concurrent.Root rev-parse HEAD).Trim() |
            Should -BeExactly $movedCommit.Value

        foreach ($kind in @('untracked', 'other-index', 'mixed-capture')) {
            $extra = New-FinalEvidenceGitFixture -Name "abrupt-extra-$kind"
            Add-AbruptEvidenceRecord -Fixture $extra
            switch ($kind) {
                'untracked' {
                    [System.IO.File]::WriteAllText(
                        (Join-Path $extra.Root 'extra.txt'),
                        "extra`n"
                    )
                }
                'other-index' {
                    [System.IO.File]::AppendAllText(
                        (Join-Path $extra.Root 'operator-merge.txt'),
                        "other`n"
                    )
                    & git -C $extra.Root add -- operator-merge.txt
                }
                'mixed-capture' {
                    $relativeCapture = [System.IO.Path]::GetRelativePath(
                        $extra.Root,
                        $extra.CapturePath
                    )
                    & git -C $extra.Root add -- $relativeCapture
                    [System.IO.File]::AppendAllText(
                        $extra.CapturePath,
                        "mixed`n"
                    )
                }
            }
            $stateBefore = [System.IO.File]::ReadAllBytes($extra.StatePath)
            {
                Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                    -RepoRoot $extra.Root -StatePath $extra.StatePath `
                    -PlanStateInvoker { $extra.Rollup } `
                    -UseDefaultFinalEvidenceRecorder `
                    -UseDefaultFinalEvidenceTransaction `
                    -UseDefaultWorktreeValidator
            } | Should -Throw $(if ($kind -ceq 'untracked') {
                    '*worktree must be clean*'
                }
                else {
                    '*permits only sole unstaged or staged Capture residue*'
                })
            [Convert]::ToBase64String(
                [System.IO.File]::ReadAllBytes($extra.StatePath)
            ) | Should -BeExactly (
                [Convert]::ToBase64String($stateBefore)
            )
            (& git -C $extra.Root rev-parse HEAD).Trim() |
                Should -BeExactly $extra.TargetCommit
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

    It 'test:EpicAutopilot.ContainerState classifies only genuine activity as active' {
        foreach ($state in @('running', 'restarting', 'paused', 'removing')) {
            & $script:epicModule {
                param($State)
                ConvertFrom-EpicAutopilotContainerState `
                    -ContainerName 'autopilot-run-fixture' -State $State
            } $state | Should -BeTrue -Because $state
        }
        foreach ($state in @('created', 'exited', 'dead')) {
            & $script:epicModule {
                param($State)
                ConvertFrom-EpicAutopilotContainerState `
                    -ContainerName 'autopilot-run-fixture' -State $State
            } $state | Should -BeFalse -Because $state
        }
        {
            & $script:epicModule {
                ConvertFrom-EpicAutopilotContainerState `
                    -ContainerName 'autopilot-run-fixture' -State 'unknown'
            }
        } | Should -Throw "*unknown state 'unknown'*"
    }

    It 'test:EpicAutopilot.RunLease is visible to a concurrent host process' {
        $statePath = New-StatePath -Name 'cross-process-lease'
        $lease = & $script:epicModule {
            param($Path, $Run)
            Enter-EpicAutopilotRunLease -StatePath $Path -Run $Run
        } $statePath $script:runA
        $probeScript = Join-Path $TestDrive 'probe-epic-run-lease.ps1'
        [System.IO.File]::WriteAllText(
            $probeScript,
            @'
param(
    [string]$ModulePath,
    [string]$StatePath,
    [string]$Run
)
Import-Module $ModulePath -Force
$active = & (Get-Module EpicAutopilot) {
    param($Path, $RunId)
    Test-EpicAutopilotRunLeaseActive -StatePath $Path -Run $RunId
} $StatePath $Run
if ($active) { exit 0 }
exit 1
'@
        )

        try {
            & (Get-Process -Id $PID).Path -NoProfile -File $probeScript `
                -ModulePath $script:modulePath -StatePath $statePath `
                -Run $script:runA
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            & $script:epicModule {
                param($RunLease)
                Exit-EpicAutopilotRunLease -Lease $RunLease
            } $lease
        }
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
        $activeProbeNames = [System.Collections.Generic.List[string]]::new()
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $runningPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -ContainerProbe {
                param($ContainerName)
                $activeProbeNames.Add($ContainerName)
                return $true
            } `
                -LauncherInvoker {
                [void]$blockedLaunches.Add($null)
                return 0
            }
        } | Should -Throw '*already running*'
        $activeProbeNames | Should -BeExactly @("autopilot-run-$script:runA")
        $blockedLaunches | Should -HaveCount 0
        [System.IO.File]::ReadAllText($runningPath) | Should -BeExactly $runningRaw

        $hostActivePath = New-StatePath -Name 'host-launcher-active'
        [System.IO.File]::WriteAllText(
            $hostActivePath,
            (New-StateJson -Outcome 'running')
        )
        $hostActiveRaw = [System.IO.File]::ReadAllText($hostActivePath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $hostActivePath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -RunLeaseProbe { return $true } `
                -ContainerProbe { throw 'active host lease must stop before container probe' } `
                -LauncherInvoker { throw 'active host lease must not relaunch' }
        } | Should -Throw '*active host launcher*'
        [System.IO.File]::ReadAllText($hostActivePath) |
            Should -BeExactly $hostActiveRaw

        $inactivePath = New-StatePath -Name 'interrupted-running'
        [System.IO.File]::WriteAllText(
            $inactivePath,
            (New-StateJson -Outcome 'running')
        )
        $inactiveBefore = [System.IO.File]::ReadAllBytes($inactivePath)
        $probedNames = [System.Collections.Generic.List[string]]::new()
        $inactive = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $inactivePath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -ContainerProbe {
            param($ContainerName)
            $probedNames.Add($ContainerName)
            return $false
        } -LauncherInvoker { throw 'inactive running state must not relaunch' }
        $probedNames | Should -BeExactly @("autopilot-run-$script:runA")
        $inactive.Failed | Should -BeTrue
        $inactive.Replayed | Should -BeTrue
        $inactive.Launch | Should -BeFalse
        $inactive.LaunchAttempted | Should -BeFalse
        $inactive.Message | Should -Match 'reconciled to invocation-failed'
        Assert-ExactState -State $inactive.State -Outcome 'invocation-failed'
        [System.IO.File]::ReadAllBytes($inactivePath) |
            Should -Not -Be $inactiveBefore

        $probeFailurePath = New-StatePath -Name 'running-probe-failure'
        [System.IO.File]::WriteAllText(
            $probeFailurePath,
            (New-StateJson -Outcome 'running')
        )
        $probeFailureBefore = [System.IO.File]::ReadAllBytes($probeFailurePath)
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $probeFailurePath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -ContainerProbe { throw 'synthetic daemon failure' } `
                -LauncherInvoker { throw 'probe failure must not relaunch' }
        } | Should -Throw '*Unable to determine*synthetic daemon failure*'
        [System.IO.File]::ReadAllBytes($probeFailurePath) |
            Should -Be $probeFailureBefore

        $reconcileCasPath = New-StatePath -Name 'running-reconcile-cas'
        [System.IO.File]::WriteAllText(
            $reconcileCasPath,
            (New-StateJson -Outcome 'running')
        )
        {
            Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $reconcileCasPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -ContainerProbe {
                [System.IO.File]::WriteAllText(
                    $reconcileCasPath,
                    (New-StateJson -Outcome 'selected')
                )
                return $false
            } -LauncherInvoker { throw 'CAS conflict must not relaunch' }
        } | Should -Throw '*reconciliation failed*'
        [System.IO.File]::ReadAllText($reconcileCasPath) |
            Should -BeExactly (New-StateJson -Outcome 'selected')

        foreach ($terminalOutcome in @('exit:43', 'invocation-failed')) {
            $terminalPath = New-StatePath -Name (
                'terminal-' + $terminalOutcome.Replace(':', '-')
            )
            [System.IO.File]::WriteAllText(
                $terminalPath,
                (New-StateJson -Outcome $terminalOutcome)
            )
            $terminalRaw = [System.IO.File]::ReadAllText($terminalPath)
            $terminalCalls = [System.Collections.Generic.List[string]]::new()
            $replay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $terminalPath `
                -TargetResolver {
                $terminalCalls.Add('target:synthetic-target-secret')
                throw 'synthetic-target-secret'
            } -WorktreeValidator {
                $terminalCalls.Add('worktree:synthetic-worktree-secret')
                throw 'synthetic-worktree-secret'
            } -PlanStateInvoker {
                $terminalCalls.Add('graph:synthetic-graph-secret')
                throw 'synthetic-graph-secret'
            } `
                -LauncherInvoker { throw 'terminal state must not relaunch' }
            $replay.Replayed | Should -BeTrue
            $replay.Launch | Should -BeFalse
            $replay.NextChild | Should -BeNullOrEmpty
            $replay.State.outcome | Should -BeExactly $terminalOutcome
            $terminalCalls | Should -HaveCount 0
            ($replay | ConvertTo-Json -Depth 5) |
                Should -Not -Match 'synthetic-(?:target|worktree|graph)-secret'
            [System.IO.File]::ReadAllText($terminalPath) | Should -BeExactly $terminalRaw
        }

        $wrongTerminalPath = New-StatePath -Name 'terminal-wrong-epic'
        [System.IO.File]::WriteAllText(
            $wrongTerminalPath,
            (New-StateJson -Outcome 'exit:43')
        )
        $wrongTerminalBytes = [System.IO.File]::ReadAllBytes($wrongTerminalPath)
        {
            Invoke-TestEpicHostLoop -Epic 'def456' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $wrongTerminalPath `
                -TargetResolver { throw 'wrong epic must fail before target resolution' } `
                -WorktreeValidator { throw 'wrong epic must fail before worktree status' } `
                -PlanStateInvoker { throw 'wrong epic must fail before graph resolution' }
        } | Should -Throw "*belongs to epic 'abc123', not requested epic 'def456'*"
        [System.IO.File]::ReadAllBytes($wrongTerminalPath) |
            Should -Be $wrongTerminalBytes

        $throwPath = New-StatePath -Name 'launcher-throw'
        $failureReceipt = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $throwPath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -RunFactory { $script:runA } -LauncherInvoker {
            throw 'synthetic start failure'
        }
        $failureReceipt.Failed | Should -BeTrue
        $failureReceipt.Launch | Should -BeFalse
        $failureReceipt.LaunchAttempted | Should -BeTrue
        $failureReceipt.Message |
            Should -Match "launcher invocation failed.*child '111111'.*run '$script:runA'.*start-failed/RuntimeException.*immutable"
        Assert-ExactState -State $failureReceipt.State -Outcome 'invocation-failed'
        $failureReceipt.StatePath | Should -BeExactly $throwPath
        $throwRaw = [System.IO.File]::ReadAllText($throwPath)
        $throwReplay = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $throwPath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -LauncherInvoker { throw 'stored failure must not relaunch' }
        $throwReplay.Replayed | Should -BeTrue
        $throwReplay.Failed | Should -BeTrue
        $throwReplay.Message | Should -Match 'invocation-failed'
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
            $invalidReceipt = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
                -RepoRoot $script:repoRoot -StatePath $invalidResultPath `
                -PlanStateInvoker $invokerA -TargetResolver $resolveA `
                -RunFactory { $script:runA } -LauncherInvoker $invalidLauncher
            $invalidReceipt.Failed | Should -BeTrue
            $invalidReceipt.Message | Should -Match 'exit-code-invalid'
            Assert-ExactState -State $invalidReceipt.State -Outcome 'invocation-failed'
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
        $conflictingPlanDir = Join-Path $plans '2026-08-31-def456-fixture-epic'
        $epicDir = Join-Path $plans 'epics/2026-08-31-abc123-fixture-epic'
        [void](New-Item -ItemType Directory -Path $childDir -Force)
        [void](New-Item -ItemType Directory -Path $conflictingPlanDir -Force)
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
        [System.IO.File]::WriteAllText(
            (Join-Path $conflictingPlanDir 'plan.md'),
            @(
                '# def456: Fixture epic'
                '<!-- plan-id: def456 -->'
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
        $ordinary = & (Join-Path $script:repoRoot 'scripts/skalary/Get-PlanState.ps1') `
            -Reference 'fixture-epic' -RepoRoot $root -Json |
            ConvertFrom-Json
        $ordinary.Kind | Should -BeExactly 'plan'

        $statePath = Join-Path $root 'state.json'
        $launches = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-TestEpicHostLoop -Epic 'fixture-epic' -Target 'refs/heads/main' `
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
            '-ExpectedStartCommit', $targetCommit,
            '-Run', $script:runA
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

    It 'test:EpicAutopilot.Admission resolves and validates the target before plan selection' {
        $order = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-TestEpicHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath (New-StatePath -Name 'admission-order') `
            -TargetResolver {
            $order.Add('target')
            return $script:targetA
        } -WorktreeValidator {
            param($Root, $Commit)
            $order.Add("worktree:$Commit")
        } -PlanStateInvoker {
            $order.Add('plan-state')
            return (New-RollupJson -NextChild $null)
        } -LauncherInvoker { throw 'no child must not launch' }

        $result.State | Should -BeNullOrEmpty
        $order | Should -BeExactly @(
            'target',
            "worktree:$script:targetA",
            'plan-state'
        )
    }

    It 'test:EpicAutopilot.PublicDefaults use clean HEAD and shared Git-common-dir state' {
        $root = Join-Path $script:fixtureRoot 'public-defaults'
        $linked = Join-Path $script:fixtureRoot 'public-defaults-linked'
        $plans = Join-Path $root 'docs/implementation-plans'
        $childFolder = '2026-08-31-111111-first-child'
        $childDir = Join-Path $plans $childFolder
        $epicDir = Join-Path $plans 'epics/2026-08-31-abc123-fixture-epic'
        $launcherDir = Join-Path $root '.github/skills/autopilot/scripts'
        [void](New-Item -ItemType Directory -Path $childDir -Force)
        [void](New-Item -ItemType Directory -Path $epicDir -Force)
        [void](New-Item -ItemType Directory -Path $launcherDir -Force)
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
        [System.IO.File]::WriteAllText(
            (Join-Path $launcherDir 'launch.ps1'),
            @'
param(
        [string]$PlanSlug,
        [string]$Mode,
        [string]$Runtime,
        [string]$Branch,
        [string]$ExpectedStartCommit,
        [string]$Run
)
if ($Branch -cne 'main') { exit 9 }
if ($Run -cnotmatch '^[0-9a-f-]{36}$') { exit 10 }
exit 0
'@
        )
        & git -C $root init -q -b main
        & git -C $root config user.name fixture
        & git -C $root config user.email fixture@example.invalid
        & git -C $root add .
        & git -C $root commit -q -m fixture
        $targetCommit = (& git -C $root rev-parse HEAD).Trim()

        Push-Location $root
        try {
            $first = Invoke-EpicAutopilotHostLoop -Epic 'abc123'
        }
        finally {
            Pop-Location
        }
        $commonDir = (& git -C $root rev-parse --git-common-dir).Trim()
        if (-not [System.IO.Path]::IsPathRooted($commonDir)) {
            $commonDir = Join-Path $root $commonDir
        }
        $expectedStatePath = [System.IO.Path]::GetFullPath(
            (Join-Path $commonDir 'skalary/epic-autopilot.json')
        )
        $first.StatePath | Should -BeExactly $expectedStatePath
        $first.State.target | Should -BeExactly $targetCommit
        $first.ExitCode | Should -Be 0
        $first.Failed | Should -BeFalse

        $tree = (& git -C $root rev-parse 'HEAD^{tree}').Trim()
        $aheadCommit = (
            'ahead' | & git -C $root commit-tree $tree -p $targetCommit
        ).Trim()
        & git -C $root update-ref refs/heads/ahead $aheadCommit
        Push-Location $root
        try {
            { Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target ahead } |
                Should -Throw '*does not equal resolved target*'
        }
        finally {
            Pop-Location
        }

        & git -C $root worktree add -q -b linked $linked $targetCommit
        Push-Location $linked
        try {
            $shared = Invoke-EpicAutopilotHostLoop -Epic 'abc123'
        }
        finally {
            Pop-Location
        }
        $shared.StatePath | Should -BeExactly $expectedStatePath
        $shared.Replayed | Should -BeTrue
        $shared.State.run | Should -BeExactly $first.State.run

        [System.IO.File]::WriteAllText((Join-Path $linked 'dirty.txt'), 'dirty')
        Push-Location $linked
        try {
            { Invoke-EpicAutopilotHostLoop -Epic 'abc123' } |
                Should -Throw '*worktree must be clean*'
        }
        finally {
            Pop-Location
            Remove-Item -LiteralPath (Join-Path $linked 'dirty.txt') -Force
        }

        & git -C $linked checkout --detach -q
        Push-Location $linked
        try {
            { Invoke-EpicAutopilotHostLoop -Epic 'abc123' } |
                Should -Throw '*HEAD does not name a local branch*'
        }
        finally {
            Pop-Location
        }
        [System.IO.File]::ReadAllText($expectedStatePath) |
            Should -BeExactly (
                $first.State | ConvertTo-Json -Compress
            )
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
        [string]$RepoRoot
    )
    if ($env:EPIC_WRAPPER_CAPTURE) {
        [System.IO.File]::WriteAllText(
            $env:EPIC_WRAPPER_CAPTURE,
            "$Epic|$Target|$RepoRoot"
        )
    }
    if ($env:EPIC_WRAPPER_SCENARIO -ceq 'final-review-failed') {
        throw 'Synthetic final-review failure.'
    }
    if ($env:EPIC_WRAPPER_SCENARIO -in @('none', 'complete', 'blocked')) {
        return [pscustomobject]@{
            State = $null
            Completed = $env:EPIC_WRAPPER_SCENARIO -ceq 'complete'
            Blocked = $env:EPIC_WRAPPER_SCENARIO -ceq 'blocked'
            ExitCode = if ($env:EPIC_WRAPPER_SCENARIO -ceq 'complete') { 0 }
                elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'blocked') { 42 }
                else { $null }
        }
    }
    $outcome = if ($env:EPIC_WRAPPER_SCENARIO -ceq 'failed') {
        'invocation-failed'
    }
    elseif ($env:EPIC_WRAPPER_SCENARIO -in @('0', 'blocked-retained')) {
        'awaiting-merge'
    }
    elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'legacy-zero') {
        'exit:0'
    }
    elseif ($env:EPIC_WRAPPER_SCENARIO -in @('missing-exit', 'invalid-exit', 'mismatch-exit')) {
        'exit:42'
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
        ExitCode = if ($env:EPIC_WRAPPER_SCENARIO -ceq 'blocked-retained') {
            42
        }
        elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'failed') {
            1
        }
        elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'missing-exit') {
            $null
        }
        elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'invalid-exit') {
            'invalid'
        }
        elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'mismatch-exit') {
            3
        }
        elseif ($outcome -eq 'awaiting-merge') {
            0
        }
        elseif ($outcome -like 'exit:*') {
            if ($env:EPIC_WRAPPER_SCENARIO -ceq 'legacy-zero') { 0 }
            else {
                [int]$env:EPIC_WRAPPER_SCENARIO
            }
        }
        else { $null }
        Failed = $outcome -eq 'invocation-failed' -or
            ($outcome -like 'exit:*' -and $outcome -ne 'exit:0')
        Completed = $false
        Blocked = $env:EPIC_WRAPPER_SCENARIO -ceq 'blocked-retained'
        Message = if ($outcome -eq 'invocation-failed') {
            'Synthetic persisted launcher failure.'
        }
        elseif ($env:EPIC_WRAPPER_SCENARIO -ceq 'blocked-retained') {
            'Synthetic retained-checkpoint blocked stop.'
        }
        else { $null }
    }
}
Export-ModuleMember -Function Invoke-EpicAutopilotHostLoop
'@
        )
        $wrapper = Join-Path $layout 'Invoke-EpicAutopilot.ps1'
        $originalScenario = $env:EPIC_WRAPPER_SCENARIO
        $originalCapture = $env:EPIC_WRAPPER_CAPTURE
        try {
            foreach ($case in @(
                    @{ Scenario = '0'; Exit = 0; Match = '"outcome":"awaiting-merge"' },
                    @{ Scenario = 'legacy-zero'; Exit = 0; Match = 'legacy exit:0 close proof' },
                    @{ Scenario = '42'; Exit = 42; Match = '"outcome":"exit:42"' },
                    @{ Scenario = '255'; Exit = 255; Match = '"outcome":"exit:255"' },
                    @{ Scenario = 'failed'; Exit = 1; Match = 'invocation-failed' },
                    @{ Scenario = 'blocked'; Exit = 42; Match = 'incomplete with no eligible NextChild' },
                    @{ Scenario = 'blocked-retained'; Exit = 42; Match = 'retained-checkpoint blocked stop' },
                    @{ Scenario = 'complete'; Exit = 0; Match = 'complete after target refresh' },
                    @{ Scenario = 'none'; Exit = 1; Match = 'neither state, completion, nor a blocked stop' },
                    @{ Scenario = 'missing-exit'; Exit = 1; Match = '(?s)inconsistent outcome.*Failed flag' },
                    @{ Scenario = 'invalid-exit'; Exit = 1; Match = 'invalid exit code' },
                    @{ Scenario = 'mismatch-exit'; Exit = 1; Match = '(?s)inconsistent outcome.*Failed flag' },
                    @{ Scenario = 'final-review-failed'; Exit = 1; Match = 'Synthetic final-review failure' }
                )) {
                $env:EPIC_WRAPPER_SCENARIO = $case.Scenario
                $output = @(
                    & (Get-Process -Id $PID).Path -NoProfile -File $wrapper abc123 2>&1
                ) | Out-String
                $LASTEXITCODE | Should -Be $case.Exit -Because $case.Scenario
                $output | Should -Match $case.Match -Because $case.Scenario
            }
            $capturePath = Join-Path $layout 'bound-parameters.txt'
            $env:EPIC_WRAPPER_CAPTURE = $capturePath
            $env:EPIC_WRAPPER_SCENARIO = '0'
            & (Get-Process -Id $PID).Path -NoProfile -File $wrapper abc123 `
                -Target refs/heads/main -RepoRoot $layout 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            [System.IO.File]::ReadAllText($capturePath) |
                Should -BeExactly "abc123|refs/heads/main|$layout"
        }
        finally {
            $env:EPIC_WRAPPER_SCENARIO = $originalScenario
            $env:EPIC_WRAPPER_CAPTURE = $originalCapture
        }
    }
}
