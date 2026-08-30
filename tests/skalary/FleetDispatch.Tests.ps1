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
                TaskId = $TaskId
                Outcome = $Outcome
                Detail = $Detail
            }
        }
    }

    AfterAll {
        Remove-Module FleetDispatch -Force -ErrorAction SilentlyContinue
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
        @($exhausted.Events | Where-Object Outcome -eq failed).Count | Should -Be 1

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
        @($failureResult.Tasks | Where-Object Status -eq cancelled).Id |
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

        $launcherFailure = Invoke-FleetDispatchPlan -Plan $throttlePlan -Render {} -InvokeWave {
            throw 'host transport failed'
        }
        $launcherFailure.State | Should -Be degraded
        $launcherFailure.Attendance.Failed | Should -Be 2
        $launcherFailure.FinalView | Should -Match 'wave launcher raised'
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
- root | failed | attempts: 1:failed | detail: "ordinary failure"
- dependent | cancelled | attempts: none | detail: "dependency 'root' did not complete"

Omitted tasks:
- (none)

Degradation:
- root | "failed: ordinary failure"
- dependent | "cancelled: dependency 'root' did not complete"
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
'@
    }
}
