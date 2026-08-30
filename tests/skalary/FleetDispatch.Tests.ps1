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
                [string]$OmissionReason = ''
            )

            return [pscustomobject]@{
                Id             = $Id
                Label          = "Task $Id"
                Key            = "role.$Id"
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
- design | Task design | key: role.design | depends on: none
- validate | Task validate | key: role.validate | depends on: none
- implement | Task implement | key: role.implement | depends on: design, validate

Omitted tasks:
- optional | Task optional | key: role.optional | reason: not needed for this run

Projected waves:
- Wave 1 (2): design, validate
- Wave 2 (1): implement
Ready order: design -> validate -> implement
'@
    }
}
