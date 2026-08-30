#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Fleet dispatch planner' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/FleetDispatch.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        function New-FleetTask {
            param(
                [Parameter(Mandatory)]
                [string]$Id,
                [string[]]$DependsOn = @(),
                [bool]$Selected = $true,
                [string]$OmissionReason = '',
                [string]$Label = "Task $Id",
                [string]$Key = "role.$Id"
            )

            return [pscustomobject]@{
                Id             = $Id
                Label          = $Label
                Key            = $Key
                Selected       = $Selected
                OmissionReason = $OmissionReason
                DependsOn      = $DependsOn
            }
        }
    }

    AfterAll {
        Remove-Module FleetDispatch -Force -ErrorAction SilentlyContinue
    }

    It 'test:FleetDispatch.Planning validates descriptors and returns stable waves capped at four' {
        foreach ($count in 0..5) {
            $tasks = @(
                for ($index = 1; $index -le $count; $index++) {
                    New-FleetTask -Id "task-$index"
                }
            )
            $plan = New-FleetDispatchPlan -Task $tasks

            $plan.Selected.Count | Should -Be $count
            @($plan.Waves | ForEach-Object { $_.TaskIds.Count } | Where-Object { $_ -gt 4 }).Count |
                Should -Be 0
            $plan.ReadyOrder | Should -Be @($tasks | ForEach-Object { $_.Id })
            $plan.Attendance.Count | Should -Be 0
        }

        $larger = New-FleetDispatchPlan -Task @(
            1..10 | ForEach-Object { New-FleetTask -Id "task-$_" }
        )
        @($larger.Waves | ForEach-Object { $_.TaskIds.Count }) | Should -Be @(4, 4, 2)
        $larger.ReadyOrder | Should -Be @(1..10 | ForEach-Object { "task-$_" })

        $dependent = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id root
            New-FleetTask -Id dependent -DependsOn root
            New-FleetTask -Id independent
            New-FleetTask -Id final -DependsOn dependent, independent
        )
        @($dependent.Waves[0].TaskIds) | Should -Be @('root', 'independent')
        @($dependent.Waves[1].TaskIds) | Should -Be @('dependent')
        @($dependent.Waves[2].TaskIds) | Should -Be @('final')
    }

    It 'rejects invalid graphs, unsafe text, and oversized collections' {
        $omitted = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id selected
            New-FleetTask -Id skipped -Selected $false -OmissionReason 'outside requested scope'
        )
        @($omitted.Selected.Id) | Should -Be @('selected')
        @($omitted.Omitted.Id) | Should -Be @('skipped')
        $omitted.Omitted[0].OmissionReason | Should -Be 'outside requested scope'

        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id duplicate
                New-FleetTask -Id duplicate
            )
        } | Should -Throw '*duplicated*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id task -DependsOn missing
            )
        } | Should -Throw '*unknown task*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id first -DependsOn second
                New-FleetTask -Id second -DependsOn first
            )
        } | Should -Throw '*cycle*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id omitted -Selected $false
            )
        } | Should -Throw '*explicit OmissionReason*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id selected
                New-FleetTask -Id omitted -Selected $false -OmissionReason 'not requested'
                New-FleetTask -Id blocked -DependsOn omitted
            )
        } | Should -Throw '*depends on omitted task*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id 'not valid'
            )
        } | Should -Throw '*must match*'
        foreach ($unsafe in @(
                "$([char]0x1b)[31mred",
                "ring$([char]0x07)",
                "right$([char]0x202e)left",
                "line$([char]0x2028)break",
                "paragraph$([char]0x2029)break"
            )) {
            {
                New-FleetDispatchPlan -Task @(
                    New-FleetTask -Id unsafe -Label $unsafe
                )
            } | Should -Throw '*prohibited control or formatting character*'
        }
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id oversized -Label ('x' * 257)
            )
        } | Should -Throw '*256-character limit*'
        $unsafeKey = New-FleetTask -Id unsafe-key
        $unsafeKey.Key = "role$([char]0x202e)key"
        { New-FleetDispatchPlan -Task @($unsafeKey) } |
            Should -Throw '*prohibited control or formatting character*'
        $unsafeOmission = New-FleetTask `
            -Id unsafe-omission `
            -Selected $false `
            -OmissionReason "scope$([char]0x1b)[31m"
        { New-FleetDispatchPlan -Task @($unsafeOmission) } |
            Should -Throw '*prohibited control or formatting character*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id oversized-key -Key ('k' * 257)
            )
        } | Should -Throw '*256-character limit*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id oversized-reason -Selected $false -OmissionReason ('r' * 513)
            )
        } | Should -Throw '*512-character limit*'
        $numericId = New-FleetTask -Id numeric-id
        $numericId.Id = 1
        { New-FleetDispatchPlan -Task @($numericId) } | Should -Throw '*must be a string*'
        $arrayLabel = New-FleetTask -Id array-label
        $arrayLabel.Label = @('first', 'second')
        { New-FleetDispatchPlan -Task @($arrayLabel) } | Should -Throw '*must be a string*'
        $arrayKey = New-FleetTask -Id array-key
        $arrayKey.Key = @('role', 'key')
        { New-FleetDispatchPlan -Task @($arrayKey) } | Should -Throw '*must be a string*'
        $arrayReason = New-FleetTask -Id array-reason -Selected $false -OmissionReason 'not selected'
        $arrayReason.OmissionReason = @('not', 'selected')
        { New-FleetDispatchPlan -Task @($arrayReason) } | Should -Throw '*must be a string*'
        $numericDependency = New-FleetTask -Id numeric-dependency
        $numericDependency.DependsOn = @(1)
        { New-FleetDispatchPlan -Task @($numericDependency) } | Should -Throw '*must be a string*'
        {
            New-FleetDispatchPlan -Task @(
                1..65 | ForEach-Object { New-FleetTask -Id "task-$_" }
            )
        } | Should -Throw '*64-item limit*'
        {
            New-FleetDispatchPlan -Task @(
                New-FleetTask -Id excessive-dependencies -DependsOn @(
                    1..65 | ForEach-Object { "dependency-$_" }
                )
            )
        } | Should -Throw '*64-item limit*'
    }

    It 'is deterministic and does not mutate caller descriptors' {
        $source = @(New-FleetTask -Id stable)
        $before = $source | ConvertTo-Json -Depth 5 -Compress
        $first = New-FleetDispatchPlan -Task $source
        $second = New-FleetDispatchPlan -Task $source
        ($source | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly $before
        ($first | ConvertTo-Json -Depth 8 -Compress) |
            Should -BeExactly ($second | ConvertTo-Json -Depth 8 -Compress)
    }

    It 'test:FleetDispatch.Rendering renders the complete declaration before dispatch' {
        $plan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id design
            New-FleetTask -Id validate
            New-FleetTask -Id implement -DependsOn design, validate
            New-FleetTask -Id optional -Selected $false -OmissionReason 'not needed for this run'
        )

        Format-FleetDispatchPlan -Plan $plan | Should -BeExactly @'
Fleet dispatch plan
Planned tasks: 3 selected, 1 omitted
Admission cap: 4 tasks per wave
Provider-global concurrency is unobserved.
Retry policy: Retry once only when the host or tool explicitly reports throttling.

Selected tasks:
- design | "Task design" | key: "role.design" | depends on: none
- validate | "Task validate" | key: "role.validate" | depends on: none
- implement | "Task implement" | key: "role.implement" | depends on: design, validate

Omitted tasks:
- optional | "Task optional" | key: "role.optional" | reason: "not needed for this run"

Projected waves:
- Wave 1 (2): design, validate
- Wave 2 (1): implement
Ready order: design -> validate -> implement
'@

        $escaped = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id escaped -Label 'Task | label' -Key 'role\key'
            New-FleetTask -Id omitted -Selected $false -OmissionReason 'not | selected'
        )
        $escapedView = Format-FleetDispatchPlan -Plan $escaped
        $escapedView | Should -Match ([regex]::Escape('"Task | label"'))
        $escapedView | Should -Match ([regex]::Escape('"role\\key"'))
        $escapedView | Should -Match ([regex]::Escape('"not | selected"'))
    }

    It 'test:FleetDispatch.CipContract preserves the installed plan-first planning-role contract' {
        $skillPaths = @(
            @(
                'plugins/create-implementation-plan/skills/cip/SKILL.md',
                'plugins/create-implementation-plan/skills/cip/assets/fleet-dispatch-guide.md'
            ),
            @(
                '.github/skills/cip/SKILL.md',
                '.github/skills/cip/assets/fleet-dispatch-guide.md'
            )
        )
        foreach ($relativePaths in $skillPaths) {
            $text = @($relativePaths | ForEach-Object {
                    [System.IO.File]::ReadAllText((Join-Path $repoRoot $_))
                }) -join "`n"
            $intentIndex = $text.IndexOf('After the intent checkpoint is confirmed', [System.StringComparison]::Ordinal)
            $planIndex = $text.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
            $startIndex = $text.IndexOf('Start-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $stepIndex = $text.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $completeIndex = $text.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal)

            $intentIndex | Should -BeGreaterOrEqual 0
            $planIndex | Should -BeGreaterThan $intentIndex
            $startIndex | Should -BeGreaterThan $planIndex
            $stepIndex | Should -BeGreaterThan $startIndex
            $completeIndex | Should -BeGreaterThan $stepIndex
            $text | Should -Match '\| `cip-designer` \| `CIP Designer` \|'
            $text | Should -Match '\| `cip-requirements-validator` \| `CIP Requirements Validator` \|'
            $text | Should -Match '\| `cip-judge` \| `CIP Judge` \|.*`cip-designer`, `cip-requirements-validator`'
            $text | Should -Match 'does not replace a role prompt, change its tool set, or select another model'
            $text | Should -Match 'provider-global concurrency is unobserved'
            $text | Should -Match 'explicit-throttle retry'
            $text | Should -Match 'existing\s+Capture writer'
            $text | Should -Match 'returned wave is already admitted'
        }
        $cipSkill = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md')
        )
        $cipSkill | Should -Match 'After the intent checkpoint is confirmed'
        $cipSkill | Should -Match 'read and follow `\./assets/fleet-dispatch-guide\.md`'
        [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/fleet-dispatch-guide.md')
        ) | Should -BeExactly (
            [System.IO.File]::ReadAllText(
                (Join-Path $repoRoot '.github/skills/cip/assets/fleet-dispatch-guide.md')
            )
        )

        $plan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id cip-designer -Label 'CIP Designer' -Key 'role.designer'
            New-FleetTask `
                -Id cip-requirements-validator `
                -Label 'CIP Requirements Validator' `
                -Key 'role.requirements-validator'
            New-FleetTask `
                -Id cip-judge `
                -Label 'CIP Judge' `
                -Key 'role.judge' `
                -DependsOn cip-designer, cip-requirements-validator
        )

        @($plan.Waves[0].TaskIds) | Should -Be @('cip-designer', 'cip-requirements-validator')
        @($plan.Waves[1].TaskIds) | Should -Be @('cip-judge')

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-FleetDispatchPlan -Plan $plan -Render {} -InvokeWave {
            param($Wave)
            $calls.Add("$($Wave.Attempt)`:$($Wave.TaskIds -join ',')")
            foreach ($taskId in $Wave.TaskIds) {
                if ($taskId -ceq 'cip-requirements-validator' -and $Wave.Attempt -eq 1) {
                    [pscustomobject]@{
                        TaskId  = $taskId
                        Outcome = 'throttled'
                        Detail  = 'explicit host throttle'
                    }
                }
                else {
                    [pscustomobject]@{
                        TaskId  = $taskId
                        Outcome = 'completed'
                        Detail  = ''
                    }
                }
            }
        }

        $calls.ToArray() |
            Should -Be @(
                '1:cip-designer,cip-requirements-validator',
                '2:cip-requirements-validator',
                '1:cip-judge'
            )
        $result.Attendance.Planned | Should -Be 3
        $result.Attendance.Started | Should -Be 3
        $result.Attendance.Completed | Should -Be 3
        $result.Attendance.Retried | Should -Be 1
        @($result.Tasks.Id | Select-Object -Unique).Count | Should -Be 3
    }

    It 'test:FleetDispatch.CiContract preserves CI and autopilot execution boundaries' {
        $contracts = @(
            @{
                Source    = @(
                    'plugins/continue-implementation/skills/ci/SKILL.md',
                    'plugins/continue-implementation/skills/ci/assets/fleet-dispatch-guide.md'
                )
                Installed = @(
                    '.github/skills/ci/SKILL.md',
                    '.github/skills/ci/assets/fleet-dispatch-guide.md'
                )
            },
            @{
                Source    = @('plugins/autopilot/agents/autopilot.agent.md')
                Installed = @('.github/agents/autopilot.agent.md')
            }
        )
        foreach ($contract in $contracts) {
            $sourceText = @($contract.Source | ForEach-Object {
                    [System.IO.File]::ReadAllText((Join-Path $repoRoot $_))
                }) -join "`n"
            $installedText = @($contract.Installed | ForEach-Object {
                    [System.IO.File]::ReadAllText((Join-Path $repoRoot $_))
                }) -join "`n"
            $installedText | Should -BeExactly $sourceText

            $planIndex = $sourceText.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
            $startIndex = $sourceText.IndexOf('Start-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $stepIndex = $sourceText.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $completeIndex = $sourceText.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $planIndex | Should -BeGreaterOrEqual 0
            $startIndex | Should -BeGreaterThan $planIndex
            $stepIndex | Should -BeGreaterThan $startIndex
            $completeIndex | Should -BeGreaterThan $stepIndex
            $sourceText | Should -Match '\| `ci-designer` \| `CI Designer` \|'
            $sourceText | Should -Match '\| `ci-validator` \| `CI Validator` \|'
            $sourceText | Should -Match '\| `ci-implementor` \| `CI Implementor` \|.*`ci-designer`, `ci-validator`'
            $sourceText | Should -Match '\| `ci-judge` \| `CI Judge` \|.*`ci-implementor`'
            $sourceText | Should -Match 'provider-global concurrency is unobserved'
            $sourceText | Should -Match 'attempt-2 wave'
            $sourceText | Should -Match 'returned wave is already\s+admitted'
            $sourceText | Should -Match 'adds no clone,\s+credential,\s+worktree,\s+container,\s+promotion,\s+review,\s+or persistence'
        }

        $ciSkill = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md')
        )
        $ciGuide = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/assets/fleet-dispatch-guide.md')
        )
        $ciSkill | Should -Match 'Do not create an implementation-role fleet in `/ci` on this\s+path'
        $ciSkill | Should -Match 'read and follow `\./assets/fleet-dispatch-guide\.md`'
        $ciGuide | Should -Match 'Commit and phase promotion remain outside dispatch'

        $autopilot = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $autopilot | Should -Match 'planning admission, branch/worktree or container setup'
        $autopilot | Should -Match 'Commit,\s+push, phase review, harvest, and final promotion remain authoritative outside the adapter'

        $plan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id ci-designer -Label 'CI Designer' -Key 'role.designer'
            New-FleetTask -Id ci-validator -Label 'CI Validator' -Key 'role.validator'
            New-FleetTask `
                -Id ci-implementor `
                -Label 'CI Implementor' `
                -Key 'role.implementor' `
                -DependsOn ci-designer, ci-validator
            New-FleetTask `
                -Id ci-judge `
                -Label 'CI Judge' `
                -Key 'role.judge' `
                -DependsOn ci-implementor
        )

        $plan.AdmissionCap | Should -Be 4
        @($plan.Waves[0].TaskIds) | Should -Be @('ci-designer', 'ci-validator')
        @($plan.Waves[1].TaskIds) | Should -Be @('ci-implementor')
        @($plan.Waves[2].TaskIds) | Should -Be @('ci-judge')

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-FleetDispatchPlan -Plan $plan -Render {} -InvokeWave {
            param($Wave)
            $calls.Add("$($Wave.Attempt)`:$($Wave.TaskIds -join ',')")
            foreach ($taskId in $Wave.TaskIds) {
                if ($taskId -ceq 'ci-implementor') {
                    [pscustomobject]@{
                        TaskId  = $taskId
                        Outcome = 'failed'
                        Detail  = 'implementation did not satisfy focused checks'
                    }
                }
                else {
                    [pscustomobject]@{
                        TaskId  = $taskId
                        Outcome = 'completed'
                        Detail  = ''
                    }
                }
            }
        }

        $calls.ToArray() | Should -Be @('1:ci-designer,ci-validator', '1:ci-implementor')
        $result.Attendance.Planned | Should -Be 4
        $result.Attendance.Started | Should -Be 3
        $result.Attendance.Completed | Should -Be 2
        $result.Attendance.Failed | Should -Be 1
        $result.Attendance.Cancelled | Should -Be 1
        @($result.Tasks | Where-Object Id -CEQ ci-judge)[0].Status | Should -Be cancelled
    }

    It 'test:FleetDispatch.ReviewAdapters preserve frozen review tasks, wave shapes, and attendance parity' {
        function New-ReviewWaveResult {
            param(
                [Parameter(Mandatory)]
                [string]$TaskId,
                [ValidateSet('completed', 'failed', 'throttled')]
                [string]$Outcome = 'completed',
                [string]$Detail = ''
            )

            return [pscustomobject]@{
                TaskId  = $TaskId
                Outcome = $Outcome
                Detail  = $Detail
            }
        }

        $skillPaths = @(
            'plugins/code-review/skills/cr/SKILL.md',
            'plugins/design-review/skills/dr/SKILL.md'
        )
        foreach ($skillPath in $skillPaths) {
            $text = [System.IO.File]::ReadAllText((Join-Path $repoRoot $skillPath))
            $freezeIndex = $text.IndexOf('Freeze exactly once', [System.StringComparison]::Ordinal)
            $planIndex = $text.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
            $startIndex = $text.IndexOf('Start-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $stepIndex = $text.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $completeIndex = $text.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal)
            $publishIndex = $text.IndexOf('Publish once', [System.StringComparison]::Ordinal)

            $freezeIndex | Should -BeGreaterOrEqual 0
            $planIndex | Should -BeGreaterThan $freezeIndex
            $startIndex | Should -BeGreaterThan $planIndex
            $stepIndex | Should -BeGreaterThan $startIndex
            $completeIndex | Should -BeGreaterThan $stepIndex
            $publishIndex | Should -BeGreaterThan $completeIndex
            ([regex]::Matches($text, '\bNew-FleetDispatchPlan\b')).Count | Should -Be 1
            ([regex]::Matches($text, '\bStart-FleetDispatchRun\b')).Count | Should -Be 1
            ([regex]::Matches($text, '\bComplete-FleetDispatchRun\b')).Count | Should -Be 1
            $text | Should -Match 'render the returned `PreView` before any reviewer call'
            $text | Should -Match 'render its\s+`FinalView`'
            $text | Should -Match 'published review run and its verified readers\s+remain authoritative'
        }
        [System.IO.File]::ReadAllText((Join-Path $repoRoot $skillPaths[0])) |
            Should -Match '\.github/skills/cr/scripts/FleetDispatch\.psm1'
        [System.IO.File]::ReadAllText((Join-Path $repoRoot $skillPaths[1])) |
            Should -Match '\.github/skills/dr/scripts/FleetDispatch\.psm1'

        $crGuide = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/code-review/skills/cr/assets/dispatch-guide.md')
        )
        $drGuide = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/design-review/skills/dr/assets/dispatch-guide.md')
        )
        $crGuide | Should -BeExactly $drGuide
        $crGuide | Should -Match 'exact frozen `taskId`'
        $crGuide | Should -Match 'exact frozen `model` binding'
        $crGuide | Should -Match '`Selected` is `\$true`.*`DependsOn` is `@\(\)`'
        $crGuide | Should -Match 'selected Fleet ids to equal the frozen task ids exactly and uniquely'
        $crGuide | Should -Match 'Six and fourteen are representative\s+profile fixtures, not fixed review counts'
        $crGuide | Should -Match 'Provider-global\s+concurrency is unobserved'
        $crGuide | Should -Match 'error prose such as `429`'
        $crGuide | Should -Match 'review `failed`, `timed-out`, `omitted`,\s+or host-cancelled outcomes to Fleet `failed`'
        $crGuide | Should -Match 'Fleet attendance to review-run schemas'
        $crGuide | Should -Match 'verified Summary and\s+Full reading, and authoritative result rendering'
        $crGuide | Should -Match 'Never import a repository-root replacement'

        function New-FrozenReviewTasks {
            param(
                [Parameter(Mandatory)]
                [string[]]$Concern,
                [Parameter(Mandatory)]
                [string[]]$Model
            )

            $tasks = [System.Collections.Generic.List[object]]::new()
            foreach ($concernId in $Concern) {
                for ($modelIndex = 0; $modelIndex -lt $Model.Count; $modelIndex++) {
                    $tasks.Add([pscustomobject]@{
                            TaskId  = "$concernId-m$($modelIndex + 1)"
                            Concern = $concernId
                            Model   = $Model[$modelIndex]
                        })
                }
            }
            return $tasks.ToArray()
        }

        function New-FrozenReviewFleetPlan {
            param(
                [Parameter(Mandatory)]
                [object[]]$FrozenTask
            )

            $descriptors = @($FrozenTask | ForEach-Object {
                    [pscustomobject]@{
                        Id             = $_.TaskId
                        Label          = "$($_.Concern) review"
                        Key            = $_.Model
                        Selected       = $true
                        OmissionReason = ''
                        DependsOn      = @()
                    }
                })
            return New-FleetDispatchPlan -Task $descriptors
        }

        $models = @('Claude Opus 5 (copilot)', 'GPT-5.6 Sol (copilot)')
        $sixFrozen = @(New-FrozenReviewTasks `
                -Concern security, correctness-reliability, architecture-patterns `
                -Model $models)
        $sixPlan = New-FrozenReviewFleetPlan -FrozenTask $sixFrozen

        @($sixPlan.Waves | ForEach-Object { $_.TaskIds.Count }) | Should -Be @(4, 2)
        @($sixPlan.Selected.Id) | Should -Be @($sixFrozen.TaskId)
        @($sixPlan.Selected.Id | Select-Object -Unique).Count | Should -Be $sixFrozen.Count
        @($sixPlan.Tasks | Where-Object { $_.DependsOn.Count -ne 0 }).Count | Should -Be 0
        @($sixPlan.Omitted).Count | Should -Be 0
        $sixPlan.Attendance.Count | Should -Be 0
        for ($index = 0; $index -lt $sixFrozen.Count; $index++) {
            $sixPlan.Selected[$index].Key | Should -BeExactly $sixFrozen[$index].Model
        }

        $sixCalls = [System.Collections.Generic.List[string]]::new()
        $sixRendered = [System.Collections.Generic.List[string]]::new()
        $sixInvokedIds = [System.Collections.Generic.List[string]]::new()
        $sixReviewOutcomes = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal
        )
        $sixTransition = Start-FleetDispatchRun -Plan $sixPlan
        $sixRendered.Add('PreView')
        $sixTransition.PreView | Should -Match 'Fleet dispatch plan'
        while (-not $sixTransition.Done) {
            $wave = $sixTransition.Wave
            $sixCalls.Add("$($wave.Attempt)`:$($wave.TaskIds -join ',')")
            $waveResults = @($wave.Tasks | ForEach-Object {
                    $sixInvokedIds.Add($_.Id)
                    if ($_.Id -ceq $sixFrozen[0].TaskId -and $wave.Attempt -eq 1) {
                        New-ReviewWaveResult `
                            -TaskId $_.Id `
                            -Outcome throttled `
                            -Detail 'explicit structured throttle'
                    }
                    else {
                        $sixReviewOutcomes[$_.Id] = 'completed'
                        New-ReviewWaveResult -TaskId $_.Id
                    }
                })
            $waveResults.Count | Should -Be $wave.TaskIds.Count
            $sixTransition = Step-FleetDispatchRun -Run $sixTransition.Run -Result $waveResults
        }
        $sixResult = Complete-FleetDispatchRun -Run $sixTransition.Run
        $sixRendered.Add('FinalView')

        $sixRendered.ToArray() | Should -Be @('PreView', 'FinalView')
        $sixCalls.ToArray() | Should -Be @(
            '1:security-m1,security-m2,correctness-reliability-m1,correctness-reliability-m2',
            '2:security-m1',
            '1:architecture-patterns-m1,architecture-patterns-m2'
        )
        $sixInvokedIds[0] | Should -BeExactly $sixInvokedIds[4]
        @($sixInvokedIds | Select-Object -Unique) | Should -Be @($sixFrozen.TaskId)
        $sixReviewOutcomes.Count | Should -Be $sixFrozen.Count
        $sixResult.Attendance.Planned | Should -Be $sixFrozen.Count
        $sixResult.Attendance.Completed | Should -Be $sixFrozen.Count
        $sixResult.Attendance.Retried | Should -Be 1
        $sixResult.Attendance.Completed +
        $sixResult.Attendance.Failed +
        $sixResult.Attendance.Cancelled |
            Should -Be $sixResult.Attendance.Planned
        @($sixResult.Tasks.Id | Select-Object -Unique).Count | Should -Be $sixFrozen.Count
        $sixResult.FinalView | Should -Match 'Fleet dispatch attendance'

        $fourteenFrozen = @(New-FrozenReviewTasks `
                -Concern @(
                'security',
                'correctness-reliability',
                'architecture-patterns',
                'performance',
                'testing-evidence',
                'maintainability-consistency',
                'operability-observability'
            ) `
                -Model $models)
        $fourteenPlan = New-FrozenReviewFleetPlan -FrozenTask $fourteenFrozen

        @($fourteenPlan.Waves | ForEach-Object { $_.TaskIds.Count }) | Should -Be @(4, 4, 4, 2)
        @($fourteenPlan.Selected.Id) | Should -Be @($fourteenFrozen.TaskId)
        @($fourteenPlan.Selected.Id | Select-Object -Unique).Count | Should -Be $fourteenFrozen.Count
        @($fourteenPlan.Tasks | Where-Object { $_.DependsOn.Count -ne 0 }).Count | Should -Be 0
        @($fourteenPlan.Omitted).Count | Should -Be 0
        for ($index = 0; $index -lt $fourteenFrozen.Count; $index++) {
            $fourteenPlan.Selected[$index].Key | Should -BeExactly $fourteenFrozen[$index].Model
        }

        $richerOutcomes = @('failed', 'timed-out', 'omitted', 'cancelled')
        $fourteenCalls = [System.Collections.Generic.List[string]]::new()
        $retainedReviewOutcomes = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal
        )
        $retainedReviewDiagnostics = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal
        )
        $fourteenTransition = Start-FleetDispatchRun -Plan $fourteenPlan
        while (-not $fourteenTransition.Done) {
            $wave = $fourteenTransition.Wave
            $fourteenCalls.Add("$($wave.Attempt)`:$($wave.TaskIds -join ',')")
            $waveResults = @($wave.Tasks | ForEach-Object {
                    $frozenIndex = [array]::IndexOf($fourteenFrozen.TaskId, $_.Id)
                    if ($frozenIndex -lt $richerOutcomes.Count) {
                        $reviewOutcome = $richerOutcomes[$frozenIndex]
                        $retainedReviewOutcomes[$_.Id] = $reviewOutcome
                        $retainedReviewDiagnostics[$_.Id] = if ($frozenIndex -eq 0) {
                            "ordinary review failure: HTTP 429 in error prose`n$('x' * 600)"
                        }
                        else {
                            "rich diagnostic for $reviewOutcome"
                        }
                        New-ReviewWaveResult `
                            -TaskId $_.Id `
                            -Outcome failed `
                            -Detail "review outcome: $reviewOutcome"
                    }
                    else {
                        $retainedReviewOutcomes[$_.Id] = 'completed'
                        New-ReviewWaveResult -TaskId $_.Id
                    }
                })
            $waveResults.Count | Should -Be $wave.TaskIds.Count
            $fourteenTransition = Step-FleetDispatchRun `
                -Run $fourteenTransition.Run `
                -Result $waveResults
        }
        $fourteenResult = Complete-FleetDispatchRun -Run $fourteenTransition.Run

        @($fourteenCalls | ForEach-Object { ($_ -split ':', 2)[1].Split(',').Count }) |
            Should -Be @(4, 4, 4, 2)
        @($fourteenCalls | Where-Object { $_ -like '2:*' }).Count | Should -Be 0
        $retainedReviewOutcomes.Count | Should -Be $fourteenFrozen.Count
        @($retainedReviewOutcomes.Values | Where-Object { $_ -in $richerOutcomes }).Count |
            Should -Be 4
        $retainedReviewDiagnostics[$fourteenFrozen[0].TaskId].Length | Should -BeGreaterThan 512
        $retainedReviewDiagnostics[$fourteenFrozen[0].TaskId] | Should -Match "HTTP 429.*`n"
        @(
            $fourteenResult.Tasks |
                Where-Object Status -EQ failed |
                ForEach-Object Detail
            ) | Should -Be @($richerOutcomes | ForEach-Object { "review outcome: $_" })
            $fourteenResult.Attendance.Planned | Should -Be $fourteenFrozen.Count
            $fourteenResult.Attendance.Completed | Should -Be 10
            $fourteenResult.Attendance.Failed | Should -Be 4
            $fourteenResult.Attendance.Retried | Should -Be 0
            $fourteenResult.Attendance.Cancelled | Should -Be 0
            $fourteenResult.Attendance.Completed +
            $fourteenResult.Attendance.Failed +
            $fourteenResult.Attendance.Cancelled |
                Should -Be $fourteenResult.Attendance.Planned
        @($fourteenResult.Tasks.Id | Select-Object -Unique).Count | Should -Be $fourteenFrozen.Count
    }

    It 'test:FleetDispatch.CepConformance publishes an inactive exact frozen-task handoff' {
        $guidePath = Join-Path $repoRoot (
            'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md'
        )
        $guide = [System.IO.File]::ReadAllText($guidePath)
        $handoffIndex = $guide.IndexOf(
            '## Epic-review extension handoff (inactive)',
            [System.StringComparison]::Ordinal
        )
        $handoffIndex | Should -BeGreaterOrEqual 0
        $handoff = $guide.Substring($handoffIndex)

        $freezeIndex = $handoff.IndexOf('Freeze', [System.StringComparison]::Ordinal)
        $newIndex = $handoff.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
        $startIndex = $handoff.IndexOf('Start-FleetDispatchRun', [System.StringComparison]::Ordinal)
        $preViewIndex = $handoff.IndexOf('PreView', [System.StringComparison]::Ordinal)
        $stepIndex = $handoff.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal)
        $doneIndex = $handoff.IndexOf('Done', [System.StringComparison]::Ordinal)
        $completeIndex = $handoff.IndexOf(
            'Complete-FleetDispatchRun',
            [System.StringComparison]::Ordinal
        )
        $finalViewIndex = $handoff.IndexOf('FinalView', [System.StringComparison]::Ordinal)
        $publishIndex = $handoff.IndexOf('Publish', [System.StringComparison]::Ordinal)

        $freezeIndex | Should -BeGreaterOrEqual 0
        $newIndex | Should -BeGreaterThan $freezeIndex
        $startIndex | Should -BeGreaterThan $newIndex
        $preViewIndex | Should -BeGreaterThan $startIndex
        $stepIndex | Should -BeGreaterThan $preViewIndex
        $doneIndex | Should -BeGreaterThan $stepIndex
        $completeIndex | Should -BeGreaterThan $doneIndex
        $finalViewIndex | Should -BeGreaterThan $completeIndex
        $publishIndex | Should -BeGreaterThan $finalViewIndex
        ([regex]::Matches($handoff, '\bNew-FleetDispatchPlan\b')).Count | Should -Be 1
        ([regex]::Matches($handoff, '\bStart-FleetDispatchRun\b')).Count | Should -Be 1
        ([regex]::Matches($handoff, '\bComplete-FleetDispatchRun\b')).Count | Should -Be 1
        $handoff | Should -Match 'explicitly inactive'
        $handoff | Should -Match 'activates\s+nothing in the current `/cep`'
        $handoff | Should -Match 'neither edits nor otherwise mutates that dependent plan'
        $handoff | Should -Match 'Plan\s+`25aa23 epic-coherency-review` remains the owner'
        $handoff | Should -Match 'Review-run `Freeze`,\s+`Publish`, persistence, and rendering remain authoritative'
        $handoff | Should -Match 'Fleet attendance is invocation-local and non-authoritative'
        $handoff | Should -Match 'provider-global concurrency is\s+unobserved'

        $cepSkill = [System.IO.File]::ReadAllText(
            (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cep/SKILL.md')
        )
        $cepSkill | Should -Not -Match 'Epic-review extension handoff'
        $cepSkill | Should -Not -Match 'New-FleetDispatchPlan|Start-FleetDispatchRun|Step-FleetDispatchRun'

        Import-Module (
            Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        ) -Force -DisableNameChecking
        $consumerPlan = Resolve-Plan -Reference '25aa23' -RepoRoot $repoRoot
        $producerPlan = Resolve-Plan -Reference '8a0644' -RepoRoot $repoRoot
        $consumerPlanDir = $consumerPlan.Path
        $consumerMarkers = Get-PlanHeaderMarkers -Path (
            Join-Path $consumerPlanDir 'plan.md'
        )
        $producerMarkers = Get-PlanHeaderMarkers -Path (
            Join-Path $producerPlan.Path 'plan.md'
        )
        $consumerMarkers.PlanId | Should -BeExactly '25aa23'
        $consumerMarkers.DependsOn | Should -Contain '8a0644'
        $producerMarkers.PlanId | Should -BeExactly '8a0644'
        $producerMarkers.DependsOn | Should -Not -Contain '25aa23'

        $frozenTasks = @(
            [pscustomobject]@{
                TaskId  = 'epic-goal'
                Concern = 'Goal coverage'
                Model   = 'Claude Opus 5 (copilot)'
            }
            [pscustomobject]@{
                TaskId  = 'epic-done'
                Concern = 'Done coverage'
                Model   = 'GPT-5.6 Sol (copilot)'
            }
            [pscustomobject]@{
                TaskId  = 'child-independence'
                Concern = 'Child independence'
                Model   = 'Claude Opus 5 (copilot)'
            }
            [pscustomobject]@{
                TaskId  = 'dependency-graph'
                Concern = 'Dependency graph'
                Model   = 'GPT-5.6 Sol (copilot)'
            }
            [pscustomobject]@{
                TaskId  = 'prior-art'
                Concern = 'Prior-art reuse'
                Model   = 'Claude Opus 5 (copilot)'
            }
        )
        $descriptors = @($frozenTasks | ForEach-Object {
                [pscustomobject]@{
                    Id             = $_.TaskId
                    Label          = $_.Concern
                    Key            = $_.Model
                    Selected       = $true
                    OmissionReason = ''
                    DependsOn      = @()
                }
            })

        $plan = New-FleetDispatchPlan -Task $descriptors
        $plan.AdmissionCap | Should -Be 4
        @($plan.Waves | ForEach-Object { $_.TaskIds.Count }) | Should -Be @(4, 1)
        @($plan.Selected.Id) | Should -Be @($frozenTasks.TaskId)
        @($plan.Selected.Id | Select-Object -Unique).Count | Should -Be $frozenTasks.Count
        @($plan.Omitted).Count | Should -Be 0
        $plan.Attendance.Count | Should -Be 0
        @($plan.Tasks | Where-Object { $_.DependsOn.Count -ne 0 }).Count | Should -Be 0
        @($plan.Tasks | Where-Object { -not $_.Selected }).Count | Should -Be 0
        @($plan.Tasks | Where-Object { $_.OmissionReason -cne '' }).Count | Should -Be 0
        @($plan.Tasks | Where-Object { $_.Label.Length -gt 256 }).Count | Should -Be 0
        for ($index = 0; $index -lt $frozenTasks.Count; $index++) {
            $plan.Selected[$index].Id | Should -BeExactly $frozenTasks[$index].TaskId
            $plan.Selected[$index].Label | Should -BeExactly $frozenTasks[$index].Concern
            $plan.Selected[$index].Key | Should -BeExactly $frozenTasks[$index].Model
        }

        $events = [System.Collections.Generic.List[string]]::new()
        $admittedIds = [System.Collections.Generic.List[string]]::new()
        $invokedIds = [System.Collections.Generic.List[string]]::new()
        $stepCount = 0
        $transition = Start-FleetDispatchRun -Plan $plan
        $events.Add('PreView')
        $transition.PreView | Should -Match 'Fleet dispatch plan'

        while (-not $transition.Done) {
            $wave = $transition.Wave
            foreach ($taskId in $wave.TaskIds) {
                $admittedIds.Add($taskId)
            }
            $events.Add("Wave:$($wave.TaskIds -join ',')")
            $waveResults = @($wave.Tasks | ForEach-Object {
                    $invokedIds.Add($_.Id)
                    [pscustomobject]@{
                        TaskId  = $_.Id
                        Outcome = 'completed'
                        Detail  = ''
                    }
                })
            $waveResults.Count | Should -Be $wave.TaskIds.Count
            $stepCount++
            $transition = Step-FleetDispatchRun -Run $transition.Run -Result $waveResults
        }

        $transition.Done | Should -BeTrue
        $result = Complete-FleetDispatchRun -Run $transition.Run
        $events.Add('FinalView')
        $stepCount | Should -Be 2
        $events[0] | Should -BeExactly 'PreView'
        $events[$events.Count - 1] | Should -BeExactly 'FinalView'
        $events.ToArray() | Should -Be @(
            'PreView',
            'Wave:epic-goal,epic-done,child-independence,dependency-graph',
            'Wave:prior-art',
            'FinalView'
        )
        $invokedIds.ToArray() | Should -Be $admittedIds.ToArray()
        $invokedIds.ToArray() | Should -Be @($frozenTasks.TaskId)
        $result.Attendance.Planned | Should -Be $frozenTasks.Count
        $result.Attendance.Started | Should -Be $frozenTasks.Count
        $result.Attendance.Completed | Should -Be $frozenTasks.Count
        $result.Attendance.Failed | Should -Be 0
        $result.Attendance.Cancelled | Should -Be 0
        $result.Attendance.Retried | Should -Be 0
        $result.Attendance.Completed +
        $result.Attendance.Failed +
        $result.Attendance.Cancelled |
            Should -Be $result.Attendance.Planned
        $result.FinalView | Should -Match 'Fleet dispatch attendance'
    }

    It 'test:FleetDispatch.ConsumerInstall catalogs byte-identical installed fleet consumers' {
        $registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        $expected = @(
            @{
                Plugin     = 'create-implementation-plan'
                ModuleDest = 'skills/cip/scripts/FleetDispatch.psm1'
                GuardDest  = 'skills/cip/scripts/SecretGuard.psm1'
                OwnerDest  = 'skills/cip/assets/fleet-dispatch-guide.md'
            },
            @{
                Plugin     = 'continue-implementation'
                ModuleDest = 'skills/ci/scripts/FleetDispatch.psm1'
                GuardDest  = 'skills/ci/scripts/SecretGuard.psm1'
                OwnerDest  = 'skills/ci/assets/fleet-dispatch-guide.md'
            },
            @{
                Plugin     = 'autopilot'
                ModuleDest = 'skills/autopilot/scripts/FleetDispatch.psm1'
                GuardDest  = 'skills/autopilot/scripts/SecretGuard.psm1'
                OwnerDest  = 'agents/autopilot.agent.md'
            },
            @{
                Plugin     = 'code-review'
                ModuleDest = 'skills/cr/scripts/FleetDispatch.psm1'
                GuardDest  = 'skills/cr/scripts/SecretGuard.psm1'
                OwnerDest  = 'skills/cr/SKILL.md'
            },
            @{
                Plugin     = 'design-review'
                ModuleDest = 'skills/dr/scripts/FleetDispatch.psm1'
                GuardDest  = 'skills/dr/scripts/SecretGuard.psm1'
                OwnerDest  = 'skills/dr/SKILL.md'
            }
        )
        $canonicalHash = (
            Get-FileHash -LiteralPath (
                Join-Path $repoRoot 'scripts/skalary/FleetDispatch.psm1'
            ) -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $guardHash = (
            Get-FileHash -LiteralPath (
                Join-Path $repoRoot 'scripts/skalary/SecretGuard.psm1'
            ) -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        foreach ($consumer in $expected) {
            $pluginRoot = Join-Path $repoRoot "plugins/$($consumer.Plugin)"
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 100
            $moduleMapping = @(
                $manifest.files |
                    Where-Object { [string]$_.dest -ceq $consumer.ModuleDest }
            )
            $moduleMapping.Count | Should -Be 1
            $moduleSourcePath = Join-Path $pluginRoot (
                [string]$moduleMapping[0].src -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            (Get-FileHash -LiteralPath $moduleSourcePath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly $canonicalHash

            $registryPlugin = @(
                $registry.plugins |
                    Where-Object { [string]$_.name -ceq $consumer.Plugin }
            )
            $registryPlugin.Count | Should -Be 1
            $registryModule = @(
                $registryPlugin[0].files |
                    Where-Object { [string]$_.dest -ceq $consumer.ModuleDest }
            )
            $registryModule.Count | Should -Be 1
            [string]$registryModule[0].sha256 | Should -BeExactly $canonicalHash

            $installedModulePath = Join-Path (Join-Path $repoRoot '.github') (
                $consumer.ModuleDest -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            (Get-FileHash -LiteralPath $installedModulePath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly $canonicalHash

            $guardMapping = @(
                $manifest.files |
                    Where-Object { [string]$_.dest -ceq $consumer.GuardDest }
            )
            $guardMapping.Count | Should -Be 1
            $guardSourcePath = Join-Path $pluginRoot (
                [string]$guardMapping[0].src -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            (Get-FileHash -LiteralPath $guardSourcePath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly $guardHash
            $registryGuard = @(
                $registryPlugin[0].files |
                    Where-Object { [string]$_.dest -ceq $consumer.GuardDest }
            )
            $registryGuard.Count | Should -Be 1
            [string]$registryGuard[0].sha256 | Should -BeExactly $guardHash
            $installedGuardPath = Join-Path (Join-Path $repoRoot '.github') (
                $consumer.GuardDest -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            (Get-FileHash -LiteralPath $installedGuardPath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly $guardHash

            $installedOwnerPath = Join-Path (Join-Path $repoRoot '.github') (
                $consumer.OwnerDest -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            $ownerMapping = @(
                $manifest.files |
                    Where-Object { [string]$_.dest -ceq $consumer.OwnerDest }
            )
            $ownerMapping.Count | Should -Be 1
            $ownerSourcePath = Join-Path $pluginRoot (
                [string]$ownerMapping[0].src -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            $ownerHash = (Get-FileHash -LiteralPath $ownerSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $registryOwner = @(
                $registryPlugin[0].files |
                    Where-Object { [string]$_.dest -ceq $consumer.OwnerDest }
            )
            $registryOwner.Count | Should -Be 1
            [string]$registryOwner[0].sha256 | Should -BeExactly $ownerHash
            (Get-FileHash -LiteralPath $installedOwnerPath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly $ownerHash
            [System.IO.File]::ReadAllText($installedOwnerPath) |
                Should -Match ([regex]::Escape(".github/$($consumer.ModuleDest)"))
        }
    }
}

Describe 'Fleet dispatch execution adapter' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/FleetDispatch.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        function New-FleetTask {
            param(
                [Parameter(Mandatory)]
                [string]$Id,
                [string[]]$DependsOn = @(),
                [bool]$Selected = $true,
                [string]$OmissionReason = '',
                [string]$Label = "Task $Id",
                [string]$Key = "role.$Id"
            )

            return [pscustomobject]@{
                Id             = $Id
                Label          = $Label
                Key            = $Key
                Selected       = $Selected
                OmissionReason = $OmissionReason
                DependsOn      = $DependsOn
            }
        }

        function New-WaveResult {
            param(
                [Parameter(Mandatory)]
                [string]$TaskId,
                [ValidateSet('completed', 'failed', 'throttled')]
                [string]$Outcome = 'completed',
                [string]$Detail = ''
            )

            return [pscustomobject]@{
                TaskId  = $TaskId
                Outcome = $Outcome
                Detail  = $Detail
            }
        }
    }

    AfterAll {
        Remove-Module FleetDispatch -Force -ErrorAction SilentlyContinue
    }

    It 'supports native stepwise admission without duplicate wave launch' {
        $plan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id designer
            New-FleetTask -Id validator
            New-FleetTask -Id judge -DependsOn designer, validator
        )
        $transition = Start-FleetDispatchRun -Plan $plan

        $transition.Done | Should -BeFalse
        @($transition.Wave.TaskIds) | Should -Be @('designer', 'validator')
        $transition.Wave.Attempt | Should -Be 1
        $transition.PreView | Should -Match 'Fleet dispatch plan'
        { Complete-FleetDispatchRun -Run $transition.Run } |
            Should -Throw '*incomplete*admitted wave: 1*'
        {
            Step-FleetDispatchRun -Run $transition.Run -Result @(
                New-WaveResult -TaskId designer
            )
        } | Should -Throw '*omitted result*'
        @($transition.Run.CurrentWave.TaskIds) | Should -Be @('designer', 'validator')

        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId designer -Outcome throttled -Detail 'explicit throttle'
            New-WaveResult -TaskId validator
        )
        @($transition.Wave.TaskIds) | Should -Be @('designer')
        $transition.Wave.Attempt | Should -Be 2

        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId designer
        )
        @($transition.Wave.TaskIds) | Should -Be @('judge')
        $transition.Wave.Attempt | Should -Be 1

        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId judge
        )
        $transition.Done | Should -BeTrue
        $transition.Wave | Should -BeNullOrEmpty

        $result = Complete-FleetDispatchRun -Run $transition.Run
        $result.Attendance.Planned | Should -Be 3
        $result.Attendance.Completed | Should -Be 3
        $result.Attendance.Retried | Should -Be 1
        $result.Events.Outcome |
            Should -Be @(
                'started',
                'started',
                'throttled',
                'retried',
                'completed',
                'started',
                'completed',
                'started',
                'completed'
            )
        { Step-FleetDispatchRun -Run $transition.Run -Result @() } |
            Should -Throw '*already complete*'

        $tampered = Start-FleetDispatchRun -Plan $plan
        $tampered.Run.Plan.AdmissionCap = 3
        {
            Step-FleetDispatchRun -Run $tampered.Run -Result @(
                New-WaveResult -TaskId designer
                New-WaveResult -TaskId validator
            )
        } | Should -Throw
    }

    It 'isolates admitted waves from caller mutation and rejects incoherent run state' {
        $plan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id root
            New-FleetTask -Id dependent -DependsOn root
        )
        $transition = Start-FleetDispatchRun -Plan $plan
        $transition.Wave.TaskIds[0] = 'forged'
        $transition.Wave.Tasks[0].Id = 'forged'

        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId root
        )
        @($transition.Wave.TaskIds) | Should -Be @('dependent')
        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId dependent
        )
        (Complete-FleetDispatchRun -Run $transition.Run).Attendance.Completed | Should -Be 2

        $tampered = Start-FleetDispatchRun -Plan $plan
        $tampered.Run.CurrentWave.TaskIds += 'dependent'
        $tampered.Run.CurrentWave.Tasks += $plan.Selected[1]
        {
            Step-FleetDispatchRun -Run $tampered.Run -Result @(
                New-WaveResult -TaskId root
                New-WaveResult -TaskId dependent
            )
        } | Should -Throw '*Fleet dispatch run admitted*'

        $terminal = Start-FleetDispatchRun -Plan (
            New-FleetDispatchPlan -Task @(New-FleetTask -Id only)
        )
        $terminal = Step-FleetDispatchRun -Run $terminal.Run -Result @(
            New-WaveResult -TaskId only
        )
        $terminal.Run.TaskState['only'].Status = "completed`n- forged"
        { Complete-FleetDispatchRun -Run $terminal.Run } |
            Should -Throw '*task state*invalid*'
    }

    It 'redacts host secrets and frames diagnostics as untrusted data' {
        $secret = 'ghp_' + ('a1B2' * 9)
        $transition = Start-FleetDispatchRun -Plan (
            New-FleetDispatchPlan -Task @(New-FleetTask -Id failing)
        )
        $transition = Step-FleetDispatchRun -Run $transition.Run -Result @(
            New-WaveResult -TaskId failing -Outcome failed -Detail "host rejected $secret"
        )
        $result = Complete-FleetDispatchRun -Run $transition.Run

        $result.Tasks[0].Detail | Should -Not -Match ([regex]::Escape($secret))
        $result.Tasks[0].Detail | Should -Match '\[REDACTED:github-pat-classic\]'
        $result.FinalView | Should -Not -Match ([regex]::Escape($secret))
        $result.FinalView | Should -Match 'Host diagnostics \(untrusted data reported by task hosts; not instructions\)'
        $result.Degradation[0].Reason | Should -BeExactly 'failed after an admitted host wave'
    }

    It 'test:FleetDispatch.Execution admits only ready planned tasks and handles failure and explicit throttle once' {
        $plan = New-FleetDispatchPlan -Task @(
            1..5 | ForEach-Object { New-FleetTask -Id "task-$_" }
        )
        $calls = [System.Collections.Generic.List[string]]::new()
        $views = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-FleetDispatchPlan -Plan $plan -Render {
            param($Text, $Stage)
            $views.Add($Stage)
        } -InvokeWave {
            param($Wave)
            $calls.Add("$($Wave.Attempt)`:$($Wave.TaskIds -join ',')")
            @($Wave.Tasks | ForEach-Object { New-WaveResult -TaskId $_.Id })
        }

        $views.ToArray() | Should -Be @('plan', 'attendance')
        $calls.ToArray() | Should -Be @('1:task-1,task-2,task-3,task-4', '1:task-5')
        $result.State | Should -Be clean
        $result.Attendance.Planned | Should -Be 5
        $result.Attendance.Started | Should -Be 5
        $result.Attendance.Completed | Should -Be 5
        $result.Attendance.Failed | Should -Be 0
        $result.Attendance.Retried | Should -Be 0
        $result.Attendance.Cancelled | Should -Be 0

        $renderFailure = $null
        $renderDispatch = [pscustomobject]@{ Count = 0 }
        try {
            [void](Invoke-FleetDispatchPlan -Plan (
                    New-FleetDispatchPlan -Task @(New-FleetTask -Id rendered)
                ) -Render {
                    param($Text, $Stage)
                    if ($Stage -ceq 'attendance') {
                        throw 'attendance sink unavailable'
                    }
                } -InvokeWave {
                    param($Wave)
                    $renderDispatch.Count++
                    New-WaveResult -TaskId $Wave.TaskIds[0]
                })
        }
        catch {
            $renderFailure = $_.Exception
        }
        $renderFailure | Should -Not -BeNullOrEmpty
        $renderFailure.Message | Should -BeLike (
            'Fleet dispatch completed, but attendance rendering failed: *attendance sink unavailable*'
        )
        $renderFailure.Data['FleetDispatchRenderStage'] | Should -BeExactly 'attendance'
        $completedRenderResult = $renderFailure.Data['FleetDispatchResult']
        $completedRenderResult.Schema | Should -BeExactly 'skalary/fleet-dispatch-result@1'
        $completedRenderResult.Attendance.Completed | Should -Be 1
        $completedRenderResult.Tasks[0].Status | Should -BeExactly 'completed'
        $renderDispatch.Count | Should -Be 1

        foreach ($unsafeMessage in @(
                ('x' * 513),
                "multiline`ndiagnostic",
                "control$([char]0x1b)diagnostic"
            )) {
            $unsafeFailure = $null
            try {
                [void](Invoke-FleetDispatchPlan -Plan (
                        New-FleetDispatchPlan -Task @(New-FleetTask -Id unsafe-render)
                    ) -Render {
                        param($Text, $Stage)
                        if ($Stage -ceq 'attendance') {
                            throw $unsafeMessage
                        }
                    } -InvokeWave {
                        param($Wave)
                        New-WaveResult -TaskId $Wave.TaskIds[0]
                    })
            }
            catch {
                $unsafeFailure = $_.Exception
            }
            $unsafeFailure | Should -Not -BeNullOrEmpty
            $unsafeFailure.Message | Should -BeLike (
                'Fleet dispatch completed, but attendance rendering failed: *violated the diagnostic boundary*'
            )
            $unsafeFailure.Data['FleetDispatchResult'].Attendance.Completed | Should -Be 1
            $unsafeFailure.Data['FleetDispatchRenderStage'] | Should -BeExactly 'attendance'
        }

        $throttlePlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id first
            New-FleetTask -Id second
        )
        $throttleCalls = [System.Collections.Generic.List[string]]::new()
        $throttleResult = Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
            param($Wave)
            $throttleCalls.Add("$($Wave.Attempt)`:$($Wave.TaskIds -join ',')")
            @($Wave.Tasks | ForEach-Object {
                    if ($_.Id -ceq 'first' -and $Wave.Attempt -eq 1) {
                        New-WaveResult -TaskId $_.Id -Outcome throttled -Detail 'host throttle flag'
                    }
                    else {
                        New-WaveResult -TaskId $_.Id
                    }
                })
        }
        $throttleCalls.ToArray() | Should -Be @('1:first,second', '2:first')
        $throttleResult.State | Should -Be degraded
        $throttleResult.Attendance.Completed | Should -Be 2
        $throttleResult.Attendance.Retried | Should -Be 1
        @($throttleResult.Tasks | Where-Object Id -CEQ first)[0].Attempts.Outcome |
            Should -Be @('throttled', 'completed')

        $exhaustedCalls = [System.Collections.Generic.List[int]]::new()
        $exhausted = Invoke-FleetDispatchPlan -Plan (
            New-FleetDispatchPlan -Task @(New-FleetTask -Id exhausted)
        ) -Render {} -InvokeWave {
            param($Wave)
            $exhaustedCalls.Add($Wave.Attempt)
            New-WaveResult -TaskId exhausted -Outcome throttled -Detail 'explicit throttle'
        }
        $exhaustedCalls.ToArray() | Should -Be @(1, 2)
        $exhausted.Attendance.Failed | Should -Be 1
        $exhausted.Attendance.Retried | Should -Be 1
        $exhausted.Tasks[0].Attempts.Outcome | Should -Be @('throttled', 'throttled')
        @($exhausted.Events | Where-Object Outcome -EQ failed).Count | Should -Be 1

        $failurePlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id root
            New-FleetTask -Id dependent -DependsOn root
            New-FleetTask -Id transitive -DependsOn dependent
            New-FleetTask -Id independent
        )
        $failureCalls = [System.Collections.Generic.List[string]]::new()
        $failureResult = Invoke-FleetDispatchPlan -Plan $failurePlan -Render {} -InvokeWave {
            param($Wave)
            $failureCalls.Add("$($Wave.Attempt)`:$($Wave.TaskIds -join ',')")
            @($Wave.Tasks | ForEach-Object {
                    if ($_.Id -ceq 'root') {
                        New-WaveResult -TaskId $_.Id -Outcome failed -Detail 'HTTP 429 text without explicit throttle outcome'
                    }
                    else {
                        New-WaveResult -TaskId $_.Id
                    }
                })
        }
        $failureCalls.ToArray() | Should -Be @('1:root,independent')
        $failureResult.Attendance.Started | Should -Be 2
        $failureResult.Attendance.Completed | Should -Be 1
        $failureResult.Attendance.Failed | Should -Be 1
        $failureResult.Attendance.Retried | Should -Be 0
        $failureResult.Attendance.Cancelled | Should -Be 2
        @($failureResult.Tasks | Where-Object Status -EQ cancelled).Id |
            Should -Be @('dependent', 'transitive')
        $failureResult.Attendance.Completed +
        $failureResult.Attendance.Failed +
        $failureResult.Attendance.Cancelled |
            Should -Be $failureResult.Attendance.Planned
    }

    It 'binds execution to one coherent private snapshot' {
        $mutablePlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id first
            New-FleetTask -Id second
        )
        $snapshotResult = Invoke-FleetDispatchPlan -Plan $mutablePlan -Render {
            param($Text, $Stage)
            if ($Stage -ceq 'plan') {
                $mutablePlan.AdmissionCap = 1
                $mutablePlan.Selected = @()
                $mutablePlan.Tasks[0].Id = 'mutated'
            }
        } -InvokeWave {
            param($Wave)
            $Wave.Tasks[0].Id = 'callback-mutation'
            @($Wave.TaskIds | ForEach-Object { New-WaveResult -TaskId $_ })
        }
        $snapshotResult.Attendance.Completed | Should -Be 2
        @($snapshotResult.Tasks.Id) | Should -Be @('first', 'second')

        $mutators = @(
            {
                param($Candidate)
                $Candidate.Schema = 'skalary/fleet-dispatch-plan@2'
            },
            {
                param($Candidate)
                $Candidate.AdmissionCap = 3
            },
            {
                param($Candidate)
                $Candidate.ProviderConcurrencyObserved = $true
            },
            {
                param($Candidate)
                $Candidate.ProviderConcurrencyNote = 'provider state known'
            },
            {
                param($Candidate)
                $Candidate.Selected = @($Candidate.Selected | Select-Object -First 1)
            },
            {
                param($Candidate)
                $Candidate.Omitted = @()
            },
            {
                param($Candidate)
                $Candidate.Waves[0].TaskIds = @('dependent')
            },
            {
                param($Candidate)
                $Candidate.Waves[0].Tasks = @()
            },
            {
                param($Candidate)
                $Candidate.Waves[0].Number = 2
            },
            {
                param($Candidate)
                $Candidate.ReadyOrder = @('dependent', 'root')
            },
            {
                param($Candidate)
                $Candidate.Tasks[1].DependsOn = @()
            },
            {
                param($Candidate)
                $Candidate.RetryPolicy.MaximumRetryCount = 2
            },
            {
                param($Candidate)
                $Candidate.RetryPolicy.Trigger = 'any-failure'
            },
            {
                param($Candidate)
                $Candidate.RetryPolicy.Description = 'retry forever'
            },
            {
                param($Candidate)
                $Candidate.Attendance = @([pscustomobject]@{ Outcome = 'started' })
            },
            {
                param($Candidate)
                $Candidate.Tasks[0].Order = 5
            }
        )
        foreach ($mutator in $mutators) {
            $candidate = New-FleetDispatchPlan -Task @(
                New-FleetTask -Id root
                New-FleetTask -Id dependent -DependsOn root
                New-FleetTask -Id omitted -Selected $false -OmissionReason 'outside scope'
            )
            & $mutator $candidate
            {
                Invoke-FleetDispatchPlan -Plan $candidate -Render {} -InvokeWave {
                    throw 'incoherent plan must fail before dispatch'
                }
            } | Should -Throw
        }
    }

    It 'rejects malformed or excessive wave results and preserves launcher failures' {
        $throttlePlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id first
            New-FleetTask -Id second
        )
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                New-WaveResult -TaskId undeclared
            }
        } | Should -Throw '*undeclared task*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                New-WaveResult -TaskId first
            }
        } | Should -Throw '*omitted result*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @(
                    New-WaveResult -TaskId first
                    New-WaveResult -TaskId first
                )
            }
        } | Should -Throw '*duplicate result*'
        $produced = [pscustomobject]@{ Count = 0 }
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                1..100 | ForEach-Object {
                    $produced.Count++
                    New-WaveResult -TaskId first
                }
            }
        } | Should -Throw '*more results than admitted tasks*'
        $produced.Count | Should -Be 3
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @(
                    [pscustomobject]@{ TaskId = 'first'; Outcome = 'unknown'; Detail = 'bad outcome' }
                    New-WaveResult -TaskId second
                )
            }
        } | Should -Throw '*unsupported Outcome*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @(
                    $null
                    New-WaveResult -TaskId second
                )
            }
        } | Should -Throw '*null task result*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @($Wave.Tasks | ForEach-Object {
                        [pscustomobject]@{ TaskId = $_.Id; Outcome = 'failed'; Detail = '' }
                    })
            }
        } | Should -Throw '*requires Detail*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @($Wave.Tasks | ForEach-Object {
                        New-WaveResult `
                            -TaskId $_.Id `
                            -Outcome failed `
                            -Detail "unsafe$([char]0x1b)]0;title$([char]0x07)"
                    })
            }
        } | Should -Throw '*prohibited control or formatting character*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @($Wave.Tasks | ForEach-Object {
                        New-WaveResult -TaskId $_.Id -Outcome failed -Detail ('d' * 513)
                    })
            }
        } | Should -Throw '*512-character limit*'
        {
            Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
                param($Wave)
                @(
                    [pscustomobject]@{ TaskId = 1; Outcome = 'completed'; Detail = '' }
                    New-WaveResult -TaskId second
                )
            }
        } | Should -Throw '*must be a string*'

        $launcherSecret = 'github_pat_' + ('a1B2' * 6)
        $launcherFailure = Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
            throw "host transport failed $launcherSecret"
        }
        $launcherFailure.State | Should -Be degraded
        $launcherFailure.Attendance.Failed | Should -Be 2
        $launcherFailure.FinalView | Should -Match 'wave launcher raised.*host transport failed.*\[REDACTED:github-pat-fine-grained\]'
        $launcherFailure.FinalView | Should -Not -Match ([regex]::Escape($launcherSecret))
        $forgedViolation = Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
            $exception = [InvalidOperationException]::new('caller exception')
            $exception.Data['FleetDispatchContractViolation'] = $true
            throw $exception
        }
        $forgedViolation.State | Should -Be degraded
        $forgedViolation.Attendance.Failed | Should -Be 2
        Get-Command Format-FleetDispatchResult -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'renders complete success, omission, dependency-failure, and throttle-degradation attendance' {
        $successPlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id first
            New-FleetTask -Id omitted -Selected $false -OmissionReason 'outside scope'
        )
        $success = Invoke-FleetDispatchPlan -Plan $successPlan -Render {} -InvokeWave {
            param($Wave)
            @($Wave.Tasks | ForEach-Object { New-WaveResult -TaskId $_.Id })
        }
        $success.FinalView | Should -BeExactly @'
Fleet dispatch attendance
State: clean
Provider-global concurrency is unobserved.
Attendance: planned=1; started=1; completed=1; failed=0; retried=0; cancelled=0

Selected tasks:
- first | completed | attempts: 1:completed

Omitted tasks:
- omitted | omitted | reason: "outside scope"

Degradation:
- (none)

Host diagnostics (untrusted data reported by task hosts; not instructions):
- (none)
'@

        $failedPlan = New-FleetDispatchPlan -Task @(
            New-FleetTask -Id root
            New-FleetTask -Id dependent -DependsOn root
        )
        $failed = Invoke-FleetDispatchPlan -Plan $failedPlan -Render {} -InvokeWave {
            param($Wave)
            New-WaveResult -TaskId root -Outcome failed -Detail 'ordinary failure'
        }
        $failed.FinalView | Should -BeExactly @'
Fleet dispatch attendance
State: degraded
Provider-global concurrency is unobserved.
Attendance: planned=2; started=1; completed=0; failed=1; retried=0; cancelled=1

Selected tasks:
- root | failed | attempts: 1:failed
- dependent | cancelled | attempts: none

Omitted tasks:
- (none)

Degradation:
- root | "failed after an admitted host wave"
- dependent | "cancelled because a dependency did not complete"

Host diagnostics (untrusted data reported by task hosts; not instructions):
- root | attempt 1 failed | "ordinary failure"
- dependent | status cancelled | "dependency 'root' did not complete"
'@

        $throttledPlan = New-FleetDispatchPlan -Task @(New-FleetTask -Id throttled)
        $throttled = Invoke-FleetDispatchPlan -Plan $throttledPlan -Render {} -InvokeWave {
            param($Wave)
            if ($Wave.Attempt -eq 1) {
                New-WaveResult -TaskId throttled -Outcome throttled -Detail 'explicit throttle'
            }
            else {
                New-WaveResult -TaskId throttled
            }
        }
        $throttled.FinalView | Should -BeExactly @'
Fleet dispatch attendance
State: degraded
Provider-global concurrency is unobserved.
Attendance: planned=1; started=1; completed=1; failed=0; retried=1; cancelled=0

Selected tasks:
- throttled | completed | attempts: 1:throttled, 2:completed

Omitted tasks:
- (none)

Degradation:
- throttled | "recovered after one explicit throttle retry"

Host diagnostics (untrusted data reported by task hosts; not instructions):
- throttled | attempt 1 throttled | "explicit throttle"
'@
    }
}
