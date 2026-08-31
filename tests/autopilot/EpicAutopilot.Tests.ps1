#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Epic autopilot host selection and resume state' {
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
    }

    AfterAll {
        $env:AUTOPILOT_CONTAINER = $script:originalContainerFlag
        Remove-Module EpicAutopilot -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'test:EpicAutopilot.HostLoop uses the exact Get-PlanState NextChild and handles boundary failures without launching' {
        $calls = [System.Collections.Generic.List[object]]::new()
        $rollupA = New-RollupJson -NextChild $script:childA
        $invoker = {
            param($EpicReference, $Root, $ScriptPath)
            $calls.Add([pscustomobject]@{
                    Epic = $EpicReference
                    Root = $Root
                    ScriptPath = $ScriptPath
                })
            $rollupA
        }.GetNewClosure()
        $resolveTarget = { param($Reference, $Root) $script:targetA }
        $statePath = New-StatePath -Name 'host-selection'

        $result = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $statePath `
            -PlanStateInvoker $invoker -TargetResolver $resolveTarget `
            -RunFactory { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }

        $calls | Should -HaveCount 1
        $calls[0].Epic | Should -BeExactly 'abc123'
        $result.NextChild.Id | Should -BeExactly $script:childA.Id
        $result.NextChild.FolderName | Should -BeExactly $script:childA.FolderName
        $result.NextChild.NextStepId | Should -BeExactly $script:childA.NextStepId
        $result.State.currentChild | Should -BeExactly $script:childA.Id
        $result.State.branch | Should -BeExactly "feature/$($script:childA.FolderName)"
        $result.State.outcome | Should -BeExactly 'selected'

        $nonePath = New-StatePath -Name 'no-child'
        $noneRollup = New-RollupJson -NextChild $null
        $none = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
            -StatePath $nonePath -PlanStateInvoker {
            param($EpicReference, $Root, $ScriptPath)
            $noneRollup
        } -TargetResolver $resolveTarget
        $none.State | Should -BeNullOrEmpty
        $none.NextChild | Should -BeNullOrEmpty
        Test-Path -LiteralPath $nonePath | Should -BeFalse

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
                    -TargetResolver $resolveTarget
            } | Should -Throw
            Test-Path -LiteralPath $failurePath | Should -BeFalse
        }

        $mismatchPath = New-StatePath -Name 'mismatched-epic'
        {
            Invoke-EpicAutopilotHostLoop -Epic 'def456' -RepoRoot $script:repoRoot `
                -StatePath $mismatchPath -PlanStateInvoker $invoker `
                -TargetResolver $resolveTarget
        } | Should -Throw
        Test-Path -LiteralPath $mismatchPath | Should -BeFalse

        $env:AUTOPILOT_CONTAINER = 'true'
        try {
            {
                Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
                    -StatePath (New-StatePath -Name 'container-refusal') `
                    -PlanStateInvoker { throw 'must not inspect plans in a container' } `
                    -TargetResolver $resolveTarget
            } | Should -Throw '*host-owned*'
        }
        finally {
            $env:AUTOPILOT_CONTAINER = $null
        }

        foreach ($name in @('EpicAutopilot.psm1', 'Get-PlanState.ps1', 'Invoke-EpicAutopilot.ps1')) {
            $canonical = Join-Path $script:repoRoot "scripts/skalary/$name"
            $bundled = Join-Path $script:repoRoot "plugins/autopilot/skills/autopilot/scripts/$name"
            (Get-FileHash -LiteralPath $bundled -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
        }
    }

    It 'test:EpicAutopilot.ResumeState roundtrips exactly, resumes after reload, and preserves bytes on every conflict' {
        $statePath = New-StatePath -Name 'resume'
        $invokerA = {
            param($EpicReference, $Root, $ScriptPath)
            New-RollupJson -NextChild $script:childA
        }
        $resolveA = { param($Reference, $Root) $script:targetA }

        $first = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $statePath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -RunFactory { 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        $first.Resumed | Should -BeFalse

        $raw = [System.IO.File]::ReadAllText($statePath)
        $json = $raw | ConvertFrom-Json
        @($json.PSObject.Properties.Name) | Should -HaveCount 6
        @($json.PSObject.Properties.Name) | Should -BeExactly @(
            'epic', 'target', 'currentChild', 'branch', 'run', 'outcome'
        )
        $json.epic | Should -BeExactly 'abc123'
        $json.target | Should -BeExactly $script:targetA
        $json.currentChild | Should -BeExactly $script:childA.Id
        $json.run | Should -BeExactly 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

        Remove-Module EpicAutopilot -Force
        Import-Module $script:modulePath -Force
        $resumed = Invoke-EpicAutopilotHostLoop -Epic 'abc123' -Target 'main' `
            -RepoRoot $script:repoRoot -StatePath $statePath `
            -PlanStateInvoker $invokerA -TargetResolver $resolveA `
            -RunFactory { throw 'resume must not allocate another run' }
        $resumed.Resumed | Should -BeTrue
        $resumed.State.run | Should -BeExactly $first.State.run
        [System.IO.File]::ReadAllText($statePath) | Should -BeExactly $raw

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
                    -RepoRoot $script:repoRoot -StatePath $statePath `
                    -PlanStateInvoker $conflict.Invoker -TargetResolver $conflict.Resolver
            } | Should -Throw -Because $conflict.Name
            [System.IO.File]::ReadAllText($statePath) | Should -BeExactly $raw
        }

        $malformedPath = New-StatePath -Name 'malformed'
        [System.IO.File]::WriteAllText($malformedPath, '{"epic":"abc123"}')
        $malformedRaw = [System.IO.File]::ReadAllBytes($malformedPath)
        {
            Invoke-EpicAutopilotHostLoop -Epic 'abc123' -RepoRoot $script:repoRoot `
                -StatePath $malformedPath -PlanStateInvoker $invokerA `
                -TargetResolver $resolveA
        } | Should -Throw
        [System.IO.File]::ReadAllBytes($malformedPath) | Should -Be $malformedRaw
    }
}
