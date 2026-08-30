#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FleetDispatchAdmissionCap = 4
$script:FleetDispatchIdPattern = '^[a-z0-9][a-z0-9._:-]{0,127}$'

function Get-FleetDispatchProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Required
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
    }
    elseif ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    if ($Required) {
        throw "Fleet task descriptor is missing required property '$Name'."
    }
    return $null
}

function Assert-FleetDispatchText {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Label,

        [switch]$AllowEmpty
    )

    if ($null -eq $Value) {
        if ($AllowEmpty) { return '' }
        throw "$Label must be a non-empty string."
    }

    $text = [string]$Value
    if ((-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) -or
        $text -match '[\r\n]' -or
        $text.IndexOfAny([char[]]@(0, 9)) -ge 0) {
        throw "$Label must be a single-line string$(if ($AllowEmpty) { '' } else { ' with visible content' })."
    }
    return $text.Trim()
}

function ConvertTo-FleetDispatchTask {
    param(
        [Parameter(Mandatory)]
        [object]$Descriptor,

        [Parameter(Mandatory)]
        [int]$Order
    )

    $id = Assert-FleetDispatchText `
        -Value (Get-FleetDispatchProperty -InputObject $Descriptor -Name Id -Required) `
        -Label "Fleet task $Order id"
    if ($id -cnotmatch $script:FleetDispatchIdPattern) {
        throw "Fleet task id '$id' must match $script:FleetDispatchIdPattern."
    }

    $label = Assert-FleetDispatchText `
        -Value (Get-FleetDispatchProperty -InputObject $Descriptor -Name Label -Required) `
        -Label "Fleet task '$id' label"
    $key = Assert-FleetDispatchText `
        -Value (Get-FleetDispatchProperty -InputObject $Descriptor -Name Key -Required) `
        -Label "Fleet task '$id' key"

    $selectedValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name Selected -Required
    if ($selectedValue -isnot [bool]) {
        throw "Fleet task '$id' Selected must be a Boolean."
    }

    $reasonValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name OmissionReason
    $omissionReason = Assert-FleetDispatchText `
        -Value $reasonValue `
        -Label "Fleet task '$id' omission reason" `
        -AllowEmpty
    if (-not $selectedValue -and [string]::IsNullOrWhiteSpace($omissionReason)) {
        throw "Omitted fleet task '$id' requires an explicit OmissionReason."
    }
    if ($selectedValue -and -not [string]::IsNullOrWhiteSpace($omissionReason)) {
        throw "Selected fleet task '$id' cannot declare an OmissionReason."
    }

    $dependencies = [System.Collections.Generic.List[string]]::new()
    $dependencySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $dependencyValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name DependsOn
    foreach ($dependency in @($dependencyValue)) {
        $dependencyId = Assert-FleetDispatchText `
            -Value $dependency `
            -Label "Fleet task '$id' dependency"
        if ($dependencyId -cnotmatch $script:FleetDispatchIdPattern) {
            throw "Fleet task '$id' dependency '$dependencyId' must match $script:FleetDispatchIdPattern."
        }
        if ($dependencyId -ceq $id) {
            throw "Fleet task '$id' cannot depend on itself."
        }
        if (-not $dependencySet.Add($dependencyId)) {
            throw "Fleet task '$id' declares duplicate dependency '$dependencyId'."
        }
        $dependencies.Add($dependencyId)
    }

    return [pscustomobject]@{
        Id             = $id
        Label          = $label
        Key            = $key
        Selected       = [bool]$selectedValue
        OmissionReason = $omissionReason
        DependsOn      = $dependencies.ToArray()
        Order          = $Order
    }
}

function Assert-FleetDispatchGraph {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Task,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]]$TaskById
    )

    foreach ($item in $Task) {
        foreach ($dependencyId in $item.DependsOn) {
            if (-not $TaskById.ContainsKey($dependencyId)) {
                throw "Fleet task '$($item.Id)' depends on unknown task '$dependencyId'."
            }
            if ($item.Selected -and -not $TaskById[$dependencyId].Selected) {
                throw "Selected fleet task '$($item.Id)' depends on omitted task '$dependencyId'; omit '$($item.Id)' explicitly or select its prerequisite."
            }
        }
    }

    $inDegree = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $dependents = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($item in $Task) {
        $inDegree.Add($item.Id, $item.DependsOn.Count)
        $dependents.Add($item.Id, [System.Collections.Generic.List[string]]::new())
    }
    foreach ($item in $Task) {
        foreach ($dependencyId in $item.DependsOn) {
            $dependents[$dependencyId].Add($item.Id)
        }
    }

    $remaining = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Task) {
        [void]$remaining.Add($item.Id)
    }
    while ($remaining.Count -gt 0) {
        $ready = @($Task | Where-Object {
                $remaining.Contains($_.Id) -and $inDegree[$_.Id] -eq 0
            })
        if ($ready.Count -eq 0) {
            $cycleIds = @($Task | Where-Object { $remaining.Contains($_.Id) } | ForEach-Object { $_.Id })
            throw "Fleet task dependencies contain a cycle among: $($cycleIds -join ', ')."
        }
        foreach ($item in $ready) {
            [void]$remaining.Remove($item.Id)
            foreach ($dependentId in $dependents[$item.Id]) {
                $inDegree[$dependentId]--
            }
        }
    }
}

function New-FleetDispatchWaves {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Task
    )

    $selected = @($Task | Where-Object Selected)
    $remaining = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $selected) {
        [void]$remaining.Add($item.Id)
    }
    $completed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $waves = [System.Collections.Generic.List[object]]::new()
    $readyOrder = [System.Collections.Generic.List[string]]::new()

    while ($remaining.Count -gt 0) {
        $ready = @($selected | Where-Object {
                if (-not $remaining.Contains($_.Id)) { return $false }
                foreach ($dependencyId in $_.DependsOn) {
                    if (-not $completed.Contains($dependencyId)) { return $false }
                }
                return $true
            })
        if ($ready.Count -eq 0) {
            throw 'Fleet dispatch planner reached an invalid dependency state.'
        }

        $waveTasks = @($ready | Select-Object -First $script:FleetDispatchAdmissionCap)
        $waveIds = @($waveTasks | ForEach-Object { $_.Id })
        $waves.Add([pscustomobject]@{
                Number  = $waves.Count + 1
                TaskIds = $waveIds
                Tasks   = $waveTasks
            })
        foreach ($taskId in $waveIds) {
            $readyOrder.Add($taskId)
            [void]$remaining.Remove($taskId)
            [void]$completed.Add($taskId)
        }
    }

    return [pscustomobject]@{
        Waves      = $waves.ToArray()
        ReadyOrder = $readyOrder.ToArray()
    }
}

function New-FleetDispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Task
    )

    $normalized = [System.Collections.Generic.List[object]]::new()
    $taskById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $order = 0
    foreach ($descriptor in @($Task)) {
        if ($null -eq $descriptor) {
            throw "Fleet task descriptor at order $order cannot be null."
        }
        $item = ConvertTo-FleetDispatchTask -Descriptor $descriptor -Order $order
        if (-not $taskById.TryAdd($item.Id, $item)) {
            throw "Fleet task id '$($item.Id)' is duplicated."
        }
        $normalized.Add($item)
        $order++
    }

    $tasks = $normalized.ToArray()
    Assert-FleetDispatchGraph -Task $tasks -TaskById $taskById
    $projection = New-FleetDispatchWaves -Task $tasks

    return [pscustomobject]@{
        Schema                      = 'skalary/fleet-dispatch-plan@1'
        AdmissionCap                = $script:FleetDispatchAdmissionCap
        ProviderConcurrencyObserved = $false
        ProviderConcurrencyNote     = 'Provider-global concurrency is unobserved.'
        RetryPolicy                 = [pscustomobject]@{
            Trigger           = 'explicit-throttle-only'
            MaximumRetryCount = 1
            Description       = 'Retry once only when the host or tool explicitly reports throttling.'
        }
        Tasks                       = $tasks
        Selected                    = @($tasks | Where-Object Selected)
        Omitted                     = @($tasks | Where-Object { -not $_.Selected })
        Waves                       = $projection.Waves
        ReadyOrder                  = $projection.ReadyOrder
        Attendance                  = @()
    }
}

function Format-FleetDispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    if ($Plan.Schema -cne 'skalary/fleet-dispatch-plan@1') {
        throw "Unsupported fleet dispatch plan schema '$($Plan.Schema)'."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Fleet dispatch plan')
    $lines.Add("Planned tasks: $($Plan.Selected.Count) selected, $($Plan.Omitted.Count) omitted")
    $lines.Add("Admission cap: $($Plan.AdmissionCap) tasks per wave")
    $lines.Add($Plan.ProviderConcurrencyNote)
    $lines.Add("Retry policy: $($Plan.RetryPolicy.Description)")
    $lines.Add('')
    $lines.Add('Selected tasks:')
    if ($Plan.Selected.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Plan.Selected) {
            $dependencies = if ($task.DependsOn.Count -eq 0) { 'none' } else { $task.DependsOn -join ', ' }
            $lines.Add("- $($task.Id) | $($task.Label) | key: $($task.Key) | depends on: $dependencies")
        }
    }
    $lines.Add('')
    $lines.Add('Omitted tasks:')
    if ($Plan.Omitted.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Plan.Omitted) {
            $lines.Add("- $($task.Id) | $($task.Label) | key: $($task.Key) | reason: $($task.OmissionReason)")
        }
    }
    $lines.Add('')
    $lines.Add('Projected waves:')
    if ($Plan.Waves.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($wave in $Plan.Waves) {
            $lines.Add("- Wave $($wave.Number) ($($wave.TaskIds.Count)): $($wave.TaskIds -join ', ')")
        }
    }
    $readyOrder = if ($Plan.ReadyOrder.Count -eq 0) { '(none)' } else { $Plan.ReadyOrder -join ' -> ' }
    $lines.Add("Ready order: $readyOrder")

    return $lines -join "`n"
}

function ConvertTo-FleetDispatchWaveResults {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ExpectedTask,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result
    )

    $expectedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($task in $ExpectedTask) {
        [void]$expectedIds.Add($task.Id)
    }

    $resultById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Result) {
        if ($null -eq $item) {
            throw 'Fleet dispatch wave returned a null task result.'
        }
        $taskId = Assert-FleetDispatchText `
            -Value (Get-FleetDispatchProperty -InputObject $item -Name TaskId -Required) `
            -Label 'Fleet dispatch wave result TaskId'
        if (-not $expectedIds.Contains($taskId)) {
            throw "Fleet dispatch wave returned undeclared task '$taskId'."
        }
        if ($resultById.ContainsKey($taskId)) {
            throw "Fleet dispatch wave returned duplicate result for task '$taskId'."
        }

        $outcome = Assert-FleetDispatchText `
            -Value (Get-FleetDispatchProperty -InputObject $item -Name Outcome -Required) `
            -Label "Fleet dispatch wave result '$taskId' Outcome"
        if ($outcome -cnotin @('completed', 'failed', 'throttled')) {
            throw "Fleet dispatch wave result '$taskId' has unsupported Outcome '$outcome'."
        }
        $detail = Assert-FleetDispatchText `
            -Value (Get-FleetDispatchProperty -InputObject $item -Name Detail) `
            -Label "Fleet dispatch wave result '$taskId' Detail" `
            -AllowEmpty

        $resultById.Add($taskId, [pscustomobject]@{
                TaskId = $taskId
                Outcome = $outcome
                Detail = $detail
            })
    }

    if ($resultById.Count -ne $ExpectedTask.Count) {
        $missing = @($ExpectedTask | Where-Object { -not $resultById.ContainsKey($_.Id) } |
                ForEach-Object { $_.Id })
        throw "Fleet dispatch wave omitted result for task(s): $($missing -join ', ')."
    }

    return @($ExpectedTask | ForEach-Object { $resultById[$_.Id] })
}

function Add-FleetDispatchEvent {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Event,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$Outcome,

        [int]$Attempt = 0,

        [string]$Detail = ''
    )

    $Event.Add([pscustomobject]@{
            Sequence = $Event.Count + 1
            TaskId   = $TaskId
            Outcome  = $Outcome
            Attempt  = $Attempt
            Detail   = $Detail
        })
}

function Invoke-FleetDispatchWave {
    param(
        [Parameter(Mandatory)]
        [object]$Wave,

        [Parameter(Mandatory)]
        [scriptblock]$InvokeWave,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]]$TaskState,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Event
    )

    foreach ($task in $Wave.Tasks) {
        $state = $TaskState[$task.Id]
        $state.Started = $true
        Add-FleetDispatchEvent -Event $Event -TaskId $task.Id -Outcome started -Attempt $Wave.Attempt
    }

    $rawResults = @(& $InvokeWave $Wave)
    $results = @(ConvertTo-FleetDispatchWaveResults -ExpectedTask $Wave.Tasks -Result $rawResults)
    foreach ($result in $results) {
        $state = $TaskState[$result.TaskId]
        $state.Attempts.Add([pscustomobject]@{
                Number  = $Wave.Attempt
                Outcome = $result.Outcome
                Detail  = $result.Detail
            })
        Add-FleetDispatchEvent `
            -Event $Event `
            -TaskId $result.TaskId `
            -Outcome $result.Outcome `
            -Attempt $Wave.Attempt `
            -Detail $result.Detail
    }
    return $results
}

function Format-FleetDispatchResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )

    if ($Result.Schema -cne 'skalary/fleet-dispatch-result@1') {
        throw "Unsupported fleet dispatch result schema '$($Result.Schema)'."
    }

    $attendance = $Result.Attendance
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Fleet dispatch attendance')
    $lines.Add("State: $($Result.State)")
    $lines.Add($Result.Plan.ProviderConcurrencyNote)
    $lines.Add(
        "Attendance: planned=$($attendance.Planned); started=$($attendance.Started); " +
        "completed=$($attendance.Completed); failed=$($attendance.Failed); " +
        "retried=$($attendance.Retried); cancelled=$($attendance.Cancelled)"
    )
    $lines.Add('')
    $lines.Add('Selected tasks:')
    if ($Result.Tasks.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Result.Tasks) {
            $attempts = if ($task.Attempts.Count -eq 0) {
                'none'
            }
            else {
                @($task.Attempts | ForEach-Object { "$($_.Number):$($_.Outcome)" }) -join ', '
            }
            $detail = if ([string]::IsNullOrWhiteSpace($task.Detail)) { '' } else { " | detail: $($task.Detail)" }
            $lines.Add("- $($task.Id) | $($task.Status) | attempts: $attempts$detail")
        }
    }
    $lines.Add('')
    $lines.Add('Omitted tasks:')
    if ($Result.Plan.Omitted.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Result.Plan.Omitted) {
            $lines.Add("- $($task.Id) | omitted | reason: $($task.OmissionReason)")
        }
    }
    $lines.Add('')
    $lines.Add('Degradation:')
    if ($Result.Degradation.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($item in $Result.Degradation) {
            $lines.Add("- $($item.TaskId) | $($item.Reason)")
        }
    }

    return $lines -join "`n"
}

function Invoke-FleetDispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [scriptblock]$InvokeWave,

        [scriptblock]$Render = {
            param([string]$Text, [string]$Stage)
            Write-Host $Text
        }
    )

    if ($Plan.Schema -cne 'skalary/fleet-dispatch-plan@1' -or
        $Plan.AdmissionCap -ne $script:FleetDispatchAdmissionCap) {
        throw 'Invoke-FleetDispatchPlan requires an unmodified skalary/fleet-dispatch-plan@1 plan.'
    }
    if ($Plan.Attendance.Count -ne 0) {
        throw 'Invoke-FleetDispatchPlan requires a plan with empty initial attendance.'
    }

    $preView = Format-FleetDispatchPlan -Plan $Plan
    [void](& $Render $preView 'plan')

    $taskState = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($task in $Plan.Selected) {
        $taskState.Add($task.Id, [pscustomobject]@{
                Id       = $task.Id
                Status   = 'pending'
                Started  = $false
                Retried  = $false
                Attempts = [System.Collections.Generic.List[object]]::new()
                Detail   = ''
            })
    }
    $events = [System.Collections.Generic.List[object]]::new()

    while (@($taskState.Values | Where-Object Status -eq pending).Count -gt 0) {
        do {
            $cancelledAny = $false
            foreach ($task in $Plan.Selected) {
                $state = $taskState[$task.Id]
                if ($state.Status -cne 'pending') { continue }
                $blockingId = @($task.DependsOn | Where-Object {
                        $taskState[$_].Status -in @('failed', 'cancelled')
                    } | Select-Object -First 1)
                if ($blockingId.Count -eq 0) { continue }

                $state.Status = 'cancelled'
                $state.Detail = "dependency '$($blockingId[0])' did not complete"
                Add-FleetDispatchEvent `
                    -Event $events `
                    -TaskId $task.Id `
                    -Outcome cancelled `
                    -Detail $state.Detail
                $cancelledAny = $true
            }
        } while ($cancelledAny)

        $ready = @($Plan.Selected | Where-Object {
                $state = $taskState[$_.Id]
                if ($state.Status -cne 'pending') { return $false }
                foreach ($dependencyId in $_.DependsOn) {
                    if ($taskState[$dependencyId].Status -cne 'completed') { return $false }
                }
                return $true
            } | Select-Object -First $Plan.AdmissionCap)
        if ($ready.Count -eq 0) {
            if (@($taskState.Values | Where-Object Status -eq pending).Count -eq 0) { break }
            throw 'Fleet dispatch execution reached an invalid dependency state.'
        }

        $firstWave = [pscustomobject]@{
            Tasks   = $ready
            TaskIds = @($ready | ForEach-Object { $_.Id })
            Attempt = 1
        }
        $firstResults = @(Invoke-FleetDispatchWave `
                -Wave $firstWave `
                -InvokeWave $InvokeWave `
                -TaskState $taskState `
                -Event $events)
        $retryTasks = [System.Collections.Generic.List[object]]::new()
        foreach ($result in $firstResults) {
            $state = $taskState[$result.TaskId]
            switch ($result.Outcome) {
                completed {
                    $state.Status = 'completed'
                    $state.Detail = $result.Detail
                }
                failed {
                    $state.Status = 'failed'
                    $state.Detail = $result.Detail
                }
                throttled {
                    $state.Retried = $true
                    $retryTasks.Add(@($ready | Where-Object Id -CEQ $result.TaskId)[0])
                    Add-FleetDispatchEvent `
                        -Event $events `
                        -TaskId $result.TaskId `
                        -Outcome retried `
                        -Attempt 2 `
                        -Detail 'one retry admitted after explicit throttle outcome'
                }
            }
        }

        if ($retryTasks.Count -gt 0) {
            $retryWave = [pscustomobject]@{
                Tasks   = $retryTasks.ToArray()
                TaskIds = @($retryTasks | ForEach-Object { $_.Id })
                Attempt = 2
            }
            $retryResults = @(Invoke-FleetDispatchWave `
                    -Wave $retryWave `
                    -InvokeWave $InvokeWave `
                    -TaskState $taskState `
                    -Event $events)
            foreach ($result in $retryResults) {
                $state = $taskState[$result.TaskId]
                if ($result.Outcome -ceq 'completed') {
                    $state.Status = 'completed'
                    $state.Detail = $result.Detail
                }
                else {
                    $state.Status = 'failed'
                    $state.Detail = if ($result.Outcome -ceq 'throttled') {
                        'explicit throttle persisted after the single retry'
                    }
                    else {
                        $result.Detail
                    }
                    if ($result.Outcome -ceq 'throttled') {
                        Add-FleetDispatchEvent `
                            -Event $events `
                            -TaskId $result.TaskId `
                            -Outcome failed `
                            -Attempt 2 `
                            -Detail $state.Detail
                    }
                }
            }
        }
    }

    $taskResults = @($Plan.Selected | ForEach-Object {
            $state = $taskState[$_.Id]
            [pscustomobject]@{
                Id       = $state.Id
                Status   = $state.Status
                Started  = $state.Started
                Retried  = $state.Retried
                Attempts = $state.Attempts.ToArray()
                Detail   = $state.Detail
            }
        })
    $attendance = [pscustomobject]@{
        Planned   = $taskResults.Count
        Started   = @($taskResults | Where-Object Started).Count
        Completed = @($taskResults | Where-Object Status -eq completed).Count
        Failed    = @($taskResults | Where-Object Status -eq failed).Count
        Retried   = @($taskResults | Where-Object Retried).Count
        Cancelled = @($taskResults | Where-Object Status -eq cancelled).Count
    }
    $degradation = [System.Collections.Generic.List[object]]::new()
    foreach ($task in $taskResults) {
        if ($task.Status -in @('failed', 'cancelled')) {
            $degradation.Add([pscustomobject]@{
                    TaskId = $task.Id
                    Reason = "$($task.Status): $($task.Detail)"
                })
        }
        elseif ($task.Retried) {
            $degradation.Add([pscustomobject]@{
                    TaskId = $task.Id
                    Reason = 'recovered after one explicit throttle retry'
                })
        }
    }

    $result = [pscustomobject]@{
        Schema      = 'skalary/fleet-dispatch-result@1'
        Plan        = $Plan
        State       = if ($degradation.Count -eq 0) { 'clean' } else { 'degraded' }
        Attendance  = $attendance
        Tasks       = $taskResults
        Events      = $events.ToArray()
        Degradation = $degradation.ToArray()
        PreView     = $preView
        FinalView   = ''
    }
    $result.FinalView = Format-FleetDispatchResult -Result $result
    [void](& $Render $result.FinalView 'attendance')
    return $result
}

Export-ModuleMember -Function `
    New-FleetDispatchPlan, `
    Format-FleetDispatchPlan, `
    Invoke-FleetDispatchPlan, `
    Format-FleetDispatchResult
