#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1') -Force -DisableNameChecking

$script:FleetDispatchAdmissionCap = 4
$script:FleetDispatchMaximumTaskCount = 64
$script:FleetDispatchIdPattern = '^[a-z0-9][a-z0-9._:-]{0,127}$'
$script:FleetDispatchProviderNote = 'Provider-global concurrency is unobserved.'
$script:FleetDispatchRetryTrigger = 'explicit-throttle-only'
$script:FleetDispatchMaximumRetryCount = 1
$script:FleetDispatchRetryDescription = 'Retry once only when the host or tool explicitly reports throttling.'

function Get-FleetDispatchProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Required,

        [switch]$NoEnumerate
    )

    $found = $false
    $value = $null
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            $found = $true
            $value = $InputObject[$Name]
        }
    }
    elseif ($InputObject.PSObject.Properties.Name -contains $Name) {
        $found = $true
        $value = $InputObject.$Name
    }

    if ($found) {
        if ($NoEnumerate) {
            Write-Output -NoEnumerate $value
        }
        else {
            Write-Output $value
        }
        return
    }

    if ($Required) {
        throw "Fleet dispatch object is missing required property '$Name'."
    }
    return $null
}

function Assert-FleetDispatchText {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Label,

        [switch]$AllowEmpty,

        [ValidateRange(1, 4096)]
        [int]$MaximumLength = 1024
    )

    if ($null -eq $Value) {
        if ($AllowEmpty) { return '' }
        throw "$Label must be a non-empty string."
    }
    if ($Value -isnot [string]) {
        throw "$Label must be a string."
    }

    $text = $Value
    if ($text.Length -gt $MaximumLength) {
        throw "$Label exceeds the $MaximumLength-character limit."
    }
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
        throw "$Label must be a string with visible content."
    }
    for ($index = 0; $index -lt $text.Length; $index++) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($text, $index)
        if ($category -in @(
                [Globalization.UnicodeCategory]::Control,
                [Globalization.UnicodeCategory]::Format,
                [Globalization.UnicodeCategory]::LineSeparator,
                [Globalization.UnicodeCategory]::ParagraphSeparator
            )) {
            throw "$Label contains a prohibited control or formatting character."
        }
    }
    return $text.Trim()
}

function ConvertTo-FleetDispatchDisplayText {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return ConvertTo-Json -InputObject $Value -Compress
}

function ConvertTo-FleetDispatchDiagnosticText {
    param(
        [AllowNull()]
        [object]$Value,

        [string]$Label = 'Fleet dispatch diagnostic',

        [ValidateRange(1, 4096)]
        [int]$MaximumLength = 512
    )

    $text = Assert-FleetDispatchText `
        -Value $Value `
        -Label $Label `
        -AllowEmpty `
        -MaximumLength $MaximumLength
    return Protect-HighConfidenceSecret -Value $text
}

function Get-FleetDispatchBoundedCollection {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateRange(0, 4096)]
        [int]$MaximumCount,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Value) {
        if ($items.Count -ge $MaximumCount) {
            throw "$Label exceeds the $MaximumCount-item limit."
        }
        $items.Add($item)
    }
    return [pscustomobject]@{ Items = $items.ToArray() }
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
        -Label "Fleet task $Order id" `
        -MaximumLength 128
    if ($id -cnotmatch $script:FleetDispatchIdPattern) {
        throw "Fleet task id '$id' must match $script:FleetDispatchIdPattern."
    }

    $label = Assert-FleetDispatchText `
        -Value (Get-FleetDispatchProperty -InputObject $Descriptor -Name Label -Required) `
        -Label "Fleet task '$id' label" `
        -MaximumLength 256
    $key = Assert-FleetDispatchText `
        -Value (Get-FleetDispatchProperty -InputObject $Descriptor -Name Key -Required) `
        -Label "Fleet task '$id' key" `
        -MaximumLength 256

    $selectedValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name Selected -Required
    if ($selectedValue -isnot [bool]) {
        throw "Fleet task '$id' Selected must be a Boolean."
    }

    $reasonValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name OmissionReason
    $omissionReason = Assert-FleetDispatchText `
        -Value $reasonValue `
        -Label "Fleet task '$id' omission reason" `
        -AllowEmpty `
        -MaximumLength 512
    if (-not $selectedValue -and [string]::IsNullOrWhiteSpace($omissionReason)) {
        throw "Omitted fleet task '$id' requires an explicit OmissionReason."
    }
    if ($selectedValue -and -not [string]::IsNullOrWhiteSpace($omissionReason)) {
        throw "Selected fleet task '$id' cannot declare an OmissionReason."
    }

    $dependencies = [System.Collections.Generic.List[string]]::new()
    $dependencySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $dependencyValue = Get-FleetDispatchProperty -InputObject $Descriptor -Name DependsOn -NoEnumerate
    $boundedDependencies = Get-FleetDispatchBoundedCollection `
        -Value $dependencyValue `
        -MaximumCount $script:FleetDispatchMaximumTaskCount `
        -Label "Fleet task '$id' dependencies"
    foreach ($dependency in $boundedDependencies.Items) {
        $dependencyId = Assert-FleetDispatchText `
            -Value $dependency `
            -Label "Fleet task '$id' dependency" `
            -MaximumLength 128
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
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Task
    )

    $descriptors = Get-FleetDispatchBoundedCollection `
        -Value $Task `
        -MaximumCount $script:FleetDispatchMaximumTaskCount `
        -Label 'Fleet dispatch task descriptors'

    $normalized = [System.Collections.Generic.List[object]]::new()
    $taskById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $order = 0
    foreach ($descriptor in $descriptors.Items) {
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
        ProviderConcurrencyNote     = $script:FleetDispatchProviderNote
        RetryPolicy                 = [pscustomobject]@{
            Trigger           = $script:FleetDispatchRetryTrigger
            MaximumRetryCount = $script:FleetDispatchMaximumRetryCount
            Description       = $script:FleetDispatchRetryDescription
        }
        Tasks                       = $tasks
        Selected                    = @($tasks | Where-Object Selected)
        Omitted                     = @($tasks | Where-Object { -not $_.Selected })
        Waves                       = $projection.Waves
        ReadyOrder                  = $projection.ReadyOrder
        Attendance                  = @()
    }
}

function ConvertTo-FleetDispatchPlanCanonicalJson {
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $retryPolicy = Get-FleetDispatchProperty -InputObject $Plan -Name RetryPolicy -Required
    $taskItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Tasks -Required -NoEnumerate) `
            -MaximumCount $script:FleetDispatchMaximumTaskCount `
            -Label 'Fleet dispatch plan Tasks').Items
    $selectedItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Selected -Required -NoEnumerate) `
            -MaximumCount $script:FleetDispatchMaximumTaskCount `
            -Label 'Fleet dispatch plan Selected').Items
    $omittedItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Omitted -Required -NoEnumerate) `
            -MaximumCount $script:FleetDispatchMaximumTaskCount `
            -Label 'Fleet dispatch plan Omitted').Items
    $waveItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Waves -Required -NoEnumerate) `
            -MaximumCount $script:FleetDispatchMaximumTaskCount `
            -Label 'Fleet dispatch plan Waves').Items
    $readyOrderItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name ReadyOrder -Required -NoEnumerate) `
            -MaximumCount $script:FleetDispatchMaximumTaskCount `
            -Label 'Fleet dispatch plan ReadyOrder').Items
    $attendanceItems = (Get-FleetDispatchBoundedCollection `
            -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Attendance -Required -NoEnumerate) `
            -MaximumCount 0 `
            -Label 'Fleet dispatch plan initial Attendance').Items
    $canonical = [ordered]@{
        schema = [string](Get-FleetDispatchProperty -InputObject $Plan -Name Schema -Required)
        admissionCap = Get-FleetDispatchProperty -InputObject $Plan -Name AdmissionCap -Required
        providerConcurrencyObserved = Get-FleetDispatchProperty `
            -InputObject $Plan `
            -Name ProviderConcurrencyObserved `
            -Required
        providerConcurrencyNote = [string](Get-FleetDispatchProperty `
                -InputObject $Plan `
                -Name ProviderConcurrencyNote `
                -Required)
        retryPolicy = [ordered]@{
            trigger = [string](Get-FleetDispatchProperty -InputObject $retryPolicy -Name Trigger -Required)
            maximumRetryCount = Get-FleetDispatchProperty `
                -InputObject $retryPolicy `
                -Name MaximumRetryCount `
                -Required
            description = [string](Get-FleetDispatchProperty `
                    -InputObject $retryPolicy `
                    -Name Description `
                    -Required)
        }
        tasks = @(
            $taskItems | ForEach-Object {
                $dependencies = (Get-FleetDispatchBoundedCollection `
                        -Value (Get-FleetDispatchProperty -InputObject $_ -Name DependsOn -Required -NoEnumerate) `
                        -MaximumCount $script:FleetDispatchMaximumTaskCount `
                        -Label "Fleet dispatch task '$($_.Id)' DependsOn").Items
                [ordered]@{
                    id = [string](Get-FleetDispatchProperty -InputObject $_ -Name Id -Required)
                    label = [string](Get-FleetDispatchProperty -InputObject $_ -Name Label -Required)
                    key = [string](Get-FleetDispatchProperty -InputObject $_ -Name Key -Required)
                    selected = Get-FleetDispatchProperty -InputObject $_ -Name Selected -Required
                    omissionReason = [string](Get-FleetDispatchProperty `
                            -InputObject $_ `
                            -Name OmissionReason `
                            -Required)
                    dependsOn = @($dependencies | ForEach-Object { [string]$_ })
                    order = Get-FleetDispatchProperty -InputObject $_ -Name Order -Required
                }
            }
        )
        selected = @(
            $selectedItems |
                ForEach-Object { [string](Get-FleetDispatchProperty -InputObject $_ -Name Id -Required) }
        )
        omitted = @(
            $omittedItems |
                ForEach-Object { [string](Get-FleetDispatchProperty -InputObject $_ -Name Id -Required) }
        )
        waves = @(
            $waveItems | ForEach-Object {
                $waveTaskIds = (Get-FleetDispatchBoundedCollection `
                        -Value (Get-FleetDispatchProperty -InputObject $_ -Name TaskIds -Required -NoEnumerate) `
                        -MaximumCount $script:FleetDispatchAdmissionCap `
                        -Label 'Fleet dispatch wave TaskIds').Items
                $waveTasks = (Get-FleetDispatchBoundedCollection `
                        -Value (Get-FleetDispatchProperty -InputObject $_ -Name Tasks -Required -NoEnumerate) `
                        -MaximumCount $script:FleetDispatchAdmissionCap `
                        -Label 'Fleet dispatch wave Tasks').Items
                [ordered]@{
                    number = Get-FleetDispatchProperty -InputObject $_ -Name Number -Required
                    taskIds = @($waveTaskIds | ForEach-Object { [string]$_ })
                    tasks = @(
                        $waveTasks |
                            ForEach-Object {
                                [string](Get-FleetDispatchProperty -InputObject $_ -Name Id -Required)
                            }
                    )
                }
            }
        )
        readyOrder = @(
            $readyOrderItems | ForEach-Object { [string]$_ }
        )
        attendance = @($attendanceItems)
    }

    return $canonical | ConvertTo-Json -Depth 12 -Compress
}

function Get-FleetDispatchPlanSnapshot {
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $taskCollection = Get-FleetDispatchBoundedCollection `
        -Value (Get-FleetDispatchProperty -InputObject $Plan -Name Tasks -Required -NoEnumerate) `
        -MaximumCount $script:FleetDispatchMaximumTaskCount `
        -Label 'Fleet dispatch plan Tasks'
    $snapshot = New-FleetDispatchPlan -Task $taskCollection.Items
    $expected = ConvertTo-FleetDispatchPlanCanonicalJson -Plan $snapshot
    $actual = ConvertTo-FleetDispatchPlanCanonicalJson -Plan $Plan
    if ($actual -cne $expected) {
        throw 'Fleet dispatch plan fields are not one coherent planner projection.'
    }
    return $snapshot
}

function Format-FleetDispatchPlanSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

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
            $label = ConvertTo-FleetDispatchDisplayText -Value $task.Label
            $key = ConvertTo-FleetDispatchDisplayText -Value $task.Key
            $lines.Add("- $($task.Id) | $label | key: $key | depends on: $dependencies")
        }
    }
    $lines.Add('')
    $lines.Add('Omitted tasks:')
    if ($Plan.Omitted.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Plan.Omitted) {
            $label = ConvertTo-FleetDispatchDisplayText -Value $task.Label
            $key = ConvertTo-FleetDispatchDisplayText -Value $task.Key
            $reason = ConvertTo-FleetDispatchDisplayText -Value $task.OmissionReason
            $lines.Add("- $($task.Id) | $label | key: $key | reason: $reason")
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

function Format-FleetDispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $snapshot = Get-FleetDispatchPlanSnapshot -Plan $Plan
    return Format-FleetDispatchPlanSnapshot -Plan $snapshot
}

function ConvertTo-FleetDispatchWaveResults {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ExpectedTask,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Result
    )

    if ($null -eq $Result) {
        throw 'Fleet dispatch wave returned a null task result.'
    }

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
            -Label 'Fleet dispatch wave result TaskId' `
            -MaximumLength 128
        if (-not $expectedIds.Contains($taskId)) {
            throw "Fleet dispatch wave returned undeclared task '$taskId'."
        }
        if ($resultById.ContainsKey($taskId)) {
            throw "Fleet dispatch wave returned duplicate result for task '$taskId'."
        }

        $outcome = Assert-FleetDispatchText `
            -Value (Get-FleetDispatchProperty -InputObject $item -Name Outcome -Required) `
            -Label "Fleet dispatch wave result '$taskId' Outcome" `
            -MaximumLength 32
        if ($outcome -cnotin @('completed', 'failed', 'throttled')) {
            throw "Fleet dispatch wave result '$taskId' has unsupported Outcome '$outcome'."
        }
        $detail = ConvertTo-FleetDispatchDiagnosticText `
            -Value (Get-FleetDispatchProperty -InputObject $item -Name Detail) `
            -Label "Fleet dispatch wave result '$taskId' Detail" `
            -MaximumLength 512
        if ($outcome -in @('failed', 'throttled') -and [string]::IsNullOrWhiteSpace($detail)) {
            throw "Fleet dispatch wave result '$taskId' requires Detail for Outcome '$outcome'."
        }

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
        [scriptblock]$InvokeWave
    )

    $launchTasks = @($Wave.Tasks | ForEach-Object {
            [pscustomobject]@{
                Id             = $_.Id
                Label          = $_.Label
                Key            = $_.Key
                Selected       = $_.Selected
                OmissionReason = $_.OmissionReason
                DependsOn      = @($_.DependsOn)
                Order          = $_.Order
            }
        })
    $launchWave = [pscustomobject]@{
        Tasks   = $launchTasks
        TaskIds = @($Wave.TaskIds)
        Attempt = $Wave.Attempt
    }
    $rawResultList = [System.Collections.Generic.List[object]]::new()
    $contractViolation = $null
    try {
        & $InvokeWave $launchWave | ForEach-Object {
            if ($rawResultList.Count -ge $Wave.Tasks.Count) {
                $contractViolation = [InvalidOperationException]::new(
                    'Fleet dispatch wave returned more results than admitted tasks.'
                )
                throw $contractViolation
            }
            $rawResultList.Add($_)
        }
    }
    catch {
        if ($null -ne $contractViolation -and
            [object]::ReferenceEquals($_.Exception, $contractViolation)) {
            throw $_.Exception
        }
        $exceptionType = [string]$_.Exception.GetType().FullName
        if ($exceptionType.Length -gt 128) {
            $exceptionType = $exceptionType.Substring(0, 128)
        }
        $exceptionMessage = [string]$_.Exception.Message
        $safeMessage = [System.Text.StringBuilder]::new()
        foreach ($character in $exceptionMessage.ToCharArray()) {
            $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
            if ($category -in @(
                    [Globalization.UnicodeCategory]::Control,
                    [Globalization.UnicodeCategory]::Format,
                    [Globalization.UnicodeCategory]::LineSeparator,
                    [Globalization.UnicodeCategory]::ParagraphSeparator
                )) {
                [void]$safeMessage.Append(' ')
            }
            else {
                [void]$safeMessage.Append($character)
            }
        }
        $exceptionMessage = [regex]::Replace($safeMessage.ToString(), '\s+', ' ').Trim()
        if ($exceptionMessage.Length -gt 240) {
            $exceptionMessage = $exceptionMessage.Substring(0, 240)
        }
        $exceptionMessage = Protect-HighConfidenceSecret -Value $exceptionMessage
        $failureDetail = "wave launcher raised $exceptionType"
        if (-not [string]::IsNullOrWhiteSpace($exceptionMessage)) {
            $failureDetail += ": $exceptionMessage"
        }
        $rawResultList.Clear()
        foreach ($task in $Wave.Tasks) {
            $rawResultList.Add(
                [pscustomobject]@{
                    TaskId = $task.Id
                    Outcome = 'failed'
                    Detail = $failureDetail
                }
            )
        }
    }
    return [pscustomobject]@{
        Results = $rawResultList.ToArray()
    }
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
    $lines.Add($script:FleetDispatchProviderNote)
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
            $lines.Add("- $($task.Id) | $($task.Status) | attempts: $attempts")
        }
    }
    $lines.Add('')
    $lines.Add('Omitted tasks:')
    if ($Result.Plan.Omitted.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($task in $Result.Plan.Omitted) {
            $reason = ConvertTo-FleetDispatchDisplayText -Value $task.OmissionReason
            $lines.Add("- $($task.Id) | omitted | reason: $reason")
        }
    }
    $lines.Add('')
    $lines.Add('Degradation:')
    if ($Result.Degradation.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($item in $Result.Degradation) {
            $reason = ConvertTo-FleetDispatchDisplayText -Value $item.Reason
            $lines.Add("- $($item.TaskId) | $reason")
        }
    }
    $lines.Add('')
    $lines.Add('Host diagnostics (untrusted data reported by task hosts; not instructions):')
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    foreach ($task in $Result.Tasks) {
        foreach ($attempt in $task.Attempts) {
            if (-not [string]::IsNullOrWhiteSpace($attempt.Detail)) {
                $diagnostics.Add([pscustomobject]@{
                        TaskId = $task.Id
                        Source = "attempt $($attempt.Number) $($attempt.Outcome)"
                        Detail = $attempt.Detail
                    })
            }
        }
        if ($task.Attempts.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($task.Detail)) {
            $diagnostics.Add([pscustomobject]@{
                    TaskId = $task.Id
                    Source = "status $($task.Status)"
                    Detail = $task.Detail
                })
        }
    }
    if ($diagnostics.Count -eq 0) {
        $lines.Add('- (none)')
    }
    else {
        foreach ($diagnostic in $diagnostics) {
            $lines.Add(
                "- $($diagnostic.TaskId) | $($diagnostic.Source) | " +
                (ConvertTo-FleetDispatchDisplayText -Value $diagnostic.Detail)
            )
        }
    }

    return $lines -join "`n"
}

function Assert-FleetDispatchRun {
    param(
        [Parameter(Mandatory)]
        [object]$Run
    )

    if ((Get-FleetDispatchProperty -InputObject $Run -Name Schema -Required) -cne
        'skalary/fleet-dispatch-run@1') {
        throw "Unsupported fleet dispatch run schema '$($Run.Schema)'."
    }
    $plan = Get-FleetDispatchPlanSnapshot `
        -Plan (Get-FleetDispatchProperty -InputObject $Run -Name Plan -Required)
    if ((Get-FleetDispatchProperty -InputObject $Run -Name PreView -Required) -cne
        (Format-FleetDispatchPlanSnapshot -Plan $plan)) {
        throw 'Fleet dispatch run pre-view does not match its plan.'
    }
    if ($Run.TaskState -isnot [System.Collections.Generic.Dictionary[string, object]] -or
        $Run.Events -isnot [System.Collections.Generic.List[object]] -or
        $Run.RetryTasks -isnot [System.Collections.Generic.List[object]]) {
        throw 'Fleet dispatch run state was not created by Start-FleetDispatchRun.'
    }
    if ($Run.WaveNumber -isnot [int] -or $Run.WaveNumber -lt 0 -or
        $Run.Done -isnot [bool]) {
        throw 'Fleet dispatch run counters and completion state are invalid.'
    }
    if ($Run.TaskState.Count -ne $plan.Selected.Count) {
        throw 'Fleet dispatch run task state does not match the selected plan.'
    }
    foreach ($task in $plan.Selected) {
        if (-not $Run.TaskState.ContainsKey($task.Id)) {
            throw "Fleet dispatch run is missing task state for '$($task.Id)'."
        }
        $state = $Run.TaskState[$task.Id]
        if ($state.Id -cne $task.Id -or
            $state.Status -cnotin @('pending', 'completed', 'failed', 'cancelled') -or
            $state.Started -isnot [bool] -or
            $state.Retried -isnot [bool] -or
            $state.RetryCount -isnot [int] -or
            $state.RetryCount -lt 0 -or
            $state.RetryCount -gt $plan.RetryPolicy.MaximumRetryCount -or
            $state.Attempts -isnot [System.Collections.Generic.List[object]]) {
            throw "Fleet dispatch run task state for '$($task.Id)' is invalid."
        }
        $safeDetail = ConvertTo-FleetDispatchDiagnosticText `
            -Value $state.Detail `
            -Label "Fleet dispatch run task '$($task.Id)' Detail"
        if ($safeDetail -cne $state.Detail) {
            throw "Fleet dispatch run task state for '$($task.Id)' contains an unredacted secret."
        }
        if ($state.Attempts.Count -gt ($plan.RetryPolicy.MaximumRetryCount + 1)) {
            throw "Fleet dispatch run task '$($task.Id)' has too many attempts."
        }
        foreach ($attempt in $state.Attempts) {
            if ($attempt.Number -isnot [int] -or $attempt.Number -notin @(1, 2) -or
                $attempt.Outcome -cnotin @('completed', 'failed', 'throttled')) {
                throw "Fleet dispatch run task '$($task.Id)' has invalid attempt state."
            }
            $safeAttemptDetail = ConvertTo-FleetDispatchDiagnosticText `
                -Value $attempt.Detail `
                -Label "Fleet dispatch run task '$($task.Id)' attempt Detail"
            if ($safeAttemptDetail -cne $attempt.Detail) {
                throw "Fleet dispatch run task '$($task.Id)' attempt contains an unredacted secret."
            }
        }
        if (-not $state.Started -and
            ($state.Attempts.Count -ne 0 -or $state.Status -cnotin @('pending', 'cancelled'))) {
            throw "Fleet dispatch run task '$($task.Id)' violates started/attempt conservation."
        }
        if ($state.Status -in @('completed', 'failed') -and
            (-not $state.Started -or $state.Attempts.Count -eq 0)) {
            throw "Fleet dispatch run task '$($task.Id)' has terminal state without an attempt."
        }
        if ($state.Retried -ne ($state.RetryCount -gt 0)) {
            throw "Fleet dispatch run task '$($task.Id)' has incoherent retry state."
        }
    }
    for ($index = 0; $index -lt $Run.Events.Count; $index++) {
        $event = $Run.Events[$index]
        if ($event.Sequence -isnot [int] -or $event.Sequence -ne ($index + 1) -or
            -not $Run.TaskState.ContainsKey([string]$event.TaskId) -or
            $event.Outcome -cnotin @(
                'started',
                'completed',
                'failed',
                'throttled',
                'retried',
                'cancelled'
            ) -or
            $event.Attempt -isnot [int] -or $event.Attempt -lt 0 -or $event.Attempt -gt 2) {
            throw "Fleet dispatch run event $($index + 1) is invalid."
        }
        $safeEventDetail = ConvertTo-FleetDispatchDiagnosticText `
            -Value $event.Detail `
            -Label "Fleet dispatch run event $($index + 1) Detail"
        if ($safeEventDetail -cne $event.Detail) {
            throw "Fleet dispatch run event $($index + 1) contains an unredacted secret."
        }
    }
    if ($Run.Done -and $null -ne $Run.CurrentWave) {
        throw 'Fleet dispatch run cannot be done while a wave is admitted.'
    }
    if ($null -ne $Run.CurrentWave) {
        $wave = $Run.CurrentWave
        if ($wave.Number -isnot [int] -or $wave.Number -ne $Run.WaveNumber -or
            $wave.Attempt -isnot [int] -or $wave.Attempt -notin @(1, 2) -or
            $wave.Tasks.Count -eq 0 -or
            $wave.Tasks.Count -gt $plan.AdmissionCap -or
            $wave.TaskIds.Count -ne $wave.Tasks.Count) {
            throw 'Fleet dispatch run admitted wave metadata is invalid.'
        }
        for ($index = 0; $index -lt $wave.Tasks.Count; $index++) {
            $waveTask = $wave.Tasks[$index]
            if ($wave.TaskIds[$index] -cne $waveTask.Id -or
                -not $Run.TaskState.ContainsKey($waveTask.Id)) {
                throw 'Fleet dispatch run admitted wave tasks are incoherent.'
            }
            $plannedTask = @($plan.Selected | Where-Object Id -CEQ $waveTask.Id)
            if ($plannedTask.Count -ne 1 -or
                (ConvertTo-Json $plannedTask[0] -Depth 5 -Compress) -cne
                (ConvertTo-Json $waveTask -Depth 5 -Compress)) {
                throw "Fleet dispatch run admitted task '$($waveTask.Id)' does not match the plan."
            }
            $state = $Run.TaskState[$waveTask.Id]
            if (-not $state.Started -or $state.Status -cne 'pending') {
                throw "Fleet dispatch run admitted task '$($waveTask.Id)' is not pending and started."
            }
            if ($wave.Attempt -eq 1) {
                foreach ($dependencyId in $waveTask.DependsOn) {
                    if ($Run.TaskState[$dependencyId].Status -cne 'completed') {
                        throw "Fleet dispatch run admitted task '$($waveTask.Id)' has an incomplete dependency."
                    }
                }
            }
            elseif ($state.RetryCount -ne 1 -or $state.Attempts.Count -eq 0 -or
                $state.Attempts[$state.Attempts.Count - 1].Outcome -cne 'throttled') {
                throw "Fleet dispatch run retry admission for '$($waveTask.Id)' is invalid."
            }
        }
    }
}

function Copy-FleetDispatchWave {
    param([AllowNull()][object]$Wave)

    if ($null -eq $Wave) { return $null }
    return [pscustomobject]@{
        Number  = $Wave.Number
        Tasks   = @($Wave.Tasks | ForEach-Object {
                [pscustomobject]@{
                    Id             = $_.Id
                    Label          = $_.Label
                    Key            = $_.Key
                    Selected       = $_.Selected
                    OmissionReason = $_.OmissionReason
                    DependsOn      = @($_.DependsOn)
                    Order          = $_.Order
                }
            })
        TaskIds = @($Wave.TaskIds)
        Attempt = $Wave.Attempt
    }
}

function Update-FleetDispatchCancellations {
    param(
        [Parameter(Mandatory)]
        [object]$Run
    )

    do {
        $cancelledAny = $false
        foreach ($task in $Run.Plan.Selected) {
            $state = $Run.TaskState[$task.Id]
            if ($state.Status -cne 'pending') { continue }
            $blockingId = @($task.DependsOn | Where-Object {
                    $Run.TaskState[$_].Status -in @('failed', 'cancelled')
                } | Select-Object -First 1)
            if ($blockingId.Count -eq 0) { continue }

            $state.Status = 'cancelled'
            $state.Detail = "dependency '$($blockingId[0])' did not complete"
            Add-FleetDispatchEvent `
                -Event $Run.Events `
                -TaskId $task.Id `
                -Outcome cancelled `
                -Detail $state.Detail
            $cancelledAny = $true
        }
    } while ($cancelledAny)
}

function Open-FleetDispatchWave {
    param(
        [Parameter(Mandatory)]
        [object]$Run
    )

    if ($null -ne $Run.CurrentWave) {
        throw "Fleet dispatch wave $($Run.CurrentWave.Number) is already admitted; submit its results instead of dispatching it again."
    }

    $attempt = 1
    if ($Run.RetryTasks.Count -gt 0) {
        $ready = $Run.RetryTasks.ToArray()
        $Run.RetryTasks.Clear()
        $attempt = 2
    }
    else {
        Update-FleetDispatchCancellations -Run $Run
        $pending = @($Run.TaskState.Values | Where-Object Status -eq pending)
        if ($pending.Count -eq 0) {
            $Run.Done = $true
            return $null
        }

        $ready = @($Run.Plan.Selected | Where-Object {
                $state = $Run.TaskState[$_.Id]
                if ($state.Status -cne 'pending') { return $false }
                foreach ($dependencyId in $_.DependsOn) {
                    if ($Run.TaskState[$dependencyId].Status -cne 'completed') { return $false }
                }
                return $true
            } | Select-Object -First $Run.Plan.AdmissionCap)
        if ($ready.Count -eq 0) {
            throw 'Fleet dispatch execution reached an invalid dependency state.'
        }
    }

    $Run.WaveNumber++
    foreach ($task in $ready) {
        $state = $Run.TaskState[$task.Id]
        $state.Started = $true
        Add-FleetDispatchEvent `
            -Event $Run.Events `
            -TaskId $task.Id `
            -Outcome started `
            -Attempt $attempt
    }
    $Run.CurrentWave = [pscustomobject]@{
        Number  = $Run.WaveNumber
        Tasks   = @($ready | ForEach-Object {
                [pscustomobject]@{
                    Id             = $_.Id
                    Label          = $_.Label
                    Key            = $_.Key
                    Selected       = $_.Selected
                    OmissionReason = $_.OmissionReason
                    DependsOn      = @($_.DependsOn)
                    Order          = $_.Order
                }
            })
        TaskIds = @($ready | ForEach-Object { $_.Id })
        Attempt = $attempt
    }
    return $Run.CurrentWave
}

function New-FleetDispatchTransition {
    param(
        [Parameter(Mandatory)]
        [object]$Run,

        [AllowNull()]
        [object]$Wave
    )

    Assert-FleetDispatchRun -Run $Run
    return [pscustomobject]@{
        Schema  = 'skalary/fleet-dispatch-transition@1'
        Run     = $Run
        Wave    = Copy-FleetDispatchWave -Wave $Wave
        Done    = $Run.Done
        PreView = $Run.PreView
    }
}

function Start-FleetDispatchRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $snapshot = Get-FleetDispatchPlanSnapshot -Plan $Plan
    $taskState = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($task in $snapshot.Selected) {
        $taskState.Add($task.Id, [pscustomobject]@{
                Id         = $task.Id
                Status     = 'pending'
                Started    = $false
                Retried    = $false
                RetryCount = 0
                Attempts   = [System.Collections.Generic.List[object]]::new()
                Detail     = ''
            })
    }
    $run = [pscustomobject]@{
        Schema      = 'skalary/fleet-dispatch-run@1'
        Plan        = $snapshot
        PreView     = Format-FleetDispatchPlanSnapshot -Plan $snapshot
        TaskState   = $taskState
        Events      = [System.Collections.Generic.List[object]]::new()
        RetryTasks  = [System.Collections.Generic.List[object]]::new()
        CurrentWave = $null
        WaveNumber  = 0
        Done        = $false
    }

    $wave = Open-FleetDispatchWave -Run $run
    return New-FleetDispatchTransition -Run $run -Wave $wave
}

function Step-FleetDispatchRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Run,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Result
    )

    Assert-FleetDispatchRun -Run $Run
    if ($Run.Done) {
        throw 'Fleet dispatch run is already complete; no further results are accepted.'
    }
    if ($null -eq $Run.CurrentWave) {
        throw 'Fleet dispatch run has no admitted wave to settle.'
    }

    $wave = $Run.CurrentWave
    $results = @(ConvertTo-FleetDispatchWaveResults -ExpectedTask $wave.Tasks -Result $Result)
    foreach ($result in $results) {
        $state = $Run.TaskState[$result.TaskId]
        $state.Attempts.Add([pscustomobject]@{
                Number  = $wave.Attempt
                Outcome = $result.Outcome
                Detail  = $result.Detail
            })
        Add-FleetDispatchEvent `
            -Event $Run.Events `
            -TaskId $result.TaskId `
            -Outcome $result.Outcome `
            -Attempt $wave.Attempt `
            -Detail $result.Detail

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
                $retryAllowed = $Run.Plan.RetryPolicy.Trigger -ceq $script:FleetDispatchRetryTrigger -and
                    $state.RetryCount -lt $Run.Plan.RetryPolicy.MaximumRetryCount
                if ($retryAllowed) {
                    $state.Retried = $true
                    $state.RetryCount++
                    $retryTask = @($Run.Plan.Selected | Where-Object Id -CEQ $result.TaskId)[0]
                    $Run.RetryTasks.Add($retryTask)
                    Add-FleetDispatchEvent `
                        -Event $Run.Events `
                        -TaskId $result.TaskId `
                        -Outcome retried `
                        -Attempt 2 `
                        -Detail $Run.Plan.RetryPolicy.Description
                }
                else {
                    $state.Status = 'failed'
                    $state.Detail = "explicit throttle persisted after $($state.RetryCount) permitted retry"
                    Add-FleetDispatchEvent `
                        -Event $Run.Events `
                        -TaskId $result.TaskId `
                        -Outcome failed `
                        -Attempt $wave.Attempt `
                        -Detail $state.Detail
                }
            }
        }
    }

    $Run.CurrentWave = $null
    $nextWave = Open-FleetDispatchWave -Run $Run
    return New-FleetDispatchTransition -Run $Run -Wave $nextWave
}

function Complete-FleetDispatchRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Run
    )

    Assert-FleetDispatchRun -Run $Run
    if (-not $Run.Done -or $null -ne $Run.CurrentWave -or
        @($Run.TaskState.Values | Where-Object Status -eq pending).Count -gt 0) {
        $wave = if ($null -eq $Run.CurrentWave) { 'none' } else { $Run.CurrentWave.Number }
        throw "Fleet dispatch run is incomplete; admitted wave: $wave. Submit its results before rendering attendance."
    }

    $taskResults = @($Run.Plan.Selected | ForEach-Object {
            $state = $Run.TaskState[$_.Id]
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
                    Reason = if ($task.Status -ceq 'failed') {
                        'failed after an admitted host wave'
                    }
                    else {
                        'cancelled because a dependency did not complete'
                    }
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
        Plan        = $Run.Plan
        State       = if ($degradation.Count -eq 0) { 'clean' } else { 'degraded' }
        Attendance  = $attendance
        Tasks       = $taskResults
        Events      = $Run.Events.ToArray()
        Degradation = $degradation.ToArray()
        PreView     = $Run.PreView
        FinalView   = ''
    }
    $result.FinalView = Format-FleetDispatchResult -Result $result
    return $result
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

    $transition = Start-FleetDispatchRun -Plan $Plan
    [void](& $Render $transition.PreView 'plan')
    while (-not $transition.Done) {
        $waveOutput = Invoke-FleetDispatchWave `
                -Wave $transition.Wave `
                -InvokeWave $InvokeWave
        $transition = Step-FleetDispatchRun `
            -Run $transition.Run `
            -Result $waveOutput.Results
    }

    $result = Complete-FleetDispatchRun -Run $transition.Run
    [void](& $Render $result.FinalView 'attendance')
    return $result
}

Export-ModuleMember -Function `
    New-FleetDispatchPlan, `
    Format-FleetDispatchPlan, `
    Start-FleetDispatchRun, `
    Step-FleetDispatchRun, `
    Complete-FleetDispatchRun, `
    Invoke-FleetDispatchPlan
