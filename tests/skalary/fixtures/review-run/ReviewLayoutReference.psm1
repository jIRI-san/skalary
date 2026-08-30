#requires -Version 7.0
<#
.SYNOPSIS
    Test-only reference renderer for the v1 `summary` and `full` review views.
.DESCRIPTION
    Plan c21cdc REQ-4/REQ-5/D5/D15, extended by plan ca8ba8 step 2.1.

    Step 1.1 owns the data contract and the layout the two published views must have; step 1.2 owns
    the production renderer, `Freeze`/`Publish` and the module that carries them. That leaves a gap
    a committed golden cannot close on its own: a `.md` file compared against itself proves nothing.

    This module closes it. It derives both views from a `skalary/review-run@1` envelope using only
    the contract — merge, corroboration, elevation, ordering, attendance, and encoding rules — and
    returns exact strings.
    `ReviewReportCorpus.Tests.ps1` renders the committed corpus through it under four cultures and
    shuffled input and requires the bytes to equal the committed goldens; the goldens are the
    fixture, the renderer is the derivation, and neither is read from the other.

    It is deliberately *not* production code: no file I/O, no publication, no schema loading, no
    `Freeze`/`Publish`. It renders, and it is loaded only from `tests/`.

    Determinism rules, all of which the culture case in the suite exercises:
      * every sort is `[System.StringComparer]::Ordinal`, never `Sort-Object`;
      * every case fold is `ToLowerInvariant`;
      * every number is formatted with `InvariantCulture`;
      * arrays are treated as sets wherever the contract says they are, so input order cannot reach
        the output.

    Untrusted-field rules (D5, D15, decisions/review-run-contract.md):
      * scope, model names, titles, actions, references and diagnostics are rendered inline, so they
        are NFC-normalized, whitespace-collapsed, HTML-encoded and Markdown-escaped;
      * bodies are rendered as blocks, so they are NFC-normalized, LF-normalized, HTML-encoded and
        wrapped in a fence longer than any backtick run they contain;
      * ids the schema constrains by pattern (run id, task id, concern, outcome, digest) are the
        only values rendered as code spans, because they are the only values that cannot break out.
#>

Set-StrictMode -Version Latest

$script:SeverityRank = @{ 'Critical' = 4; 'High' = 3; 'Medium' = 2; 'Low' = 1 }
$script:SeverityByRank = @{ 4 = 'Critical'; 3 = 'High'; 2 = 'Medium'; 1 = 'Low' }
$script:Outcomes = @('completed', 'failed', 'timed-out', 'omitted', 'cancelled', 'pending')
$script:Unit = [string][char]1

function Get-Value {
    <#
    .SYNOPSIS
        Reads one property from a parsed JSON node, returning $null when it is absent.
    #>
    param([object]$Node, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Node) { return $null }
    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name)) { return $Node[$Name] }
        return $null
    }
    if ($Node.PSObject.Properties.Name -contains $Name) { return $Node.$Name }
    return $null
}

function Format-Invariant {
    param([Parameter(Mandatory)][int]$Value)

    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Sort-Ordinal {
    <#
    .SYNOPSIS
        Ordinal string sort. `Sort-Object` compares with the current culture, which is exactly the
        dependency the culture case exists to catch.
    #>
    param([AllowEmptyCollection()][string[]]$Value)

    $copy = [string[]]@($Value)
    [array]::Sort($copy, [System.StringComparer]::Ordinal)
    # Emitted one element at a time so callers can pipe the result directly.
    return $copy
}

function Get-OrdinalTupleKey {
    param([AllowEmptyCollection()][string[]]$Value)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($item in @($Value)) {
        $text = [string]$item
        [void]$builder.Append((Format-Invariant -Value $text.Length))
        [void]$builder.Append(':')
        [void]$builder.Append($text)
        [void]$builder.Append(';')
    }
    return $builder.ToString()
}

function Get-ReviewNormalizedKey {
    <#
    .SYNOPSIS
        The grouping normalization the contract preserves: lower-invariant, runs of
        non-alphanumerics collapsed to one space, trimmed.
    #>
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $canonical = $Value.Normalize([System.Text.NormalizationForm]::FormC)
    return ([regex]::Replace($canonical.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
}

function Get-FindingSimilarityProfile {
    param([Parameter(Mandatory)][object]$Finding)

    $normalized = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('Title', 'Body', 'Action')) {
        $value = [string](Get-Value -Node $Finding -Name $name)
        $canonical = $value.Normalize([System.Text.NormalizationForm]::FormC)
        $canonical = $canonical -replace "`r`n", "`n" -replace "`r", "`n"
        $normalized.Add(([regex]::Replace($canonical.ToLowerInvariant(), '[^\p{L}\p{Nd}]+', ' ')).Trim())
    }

    $content = ([regex]::Replace(($normalized -join ' '), '\s+', ' ')).Trim()
    $tokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($token in $content.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        [void]$tokens.Add($token)
    }
    return [pscustomobject]@{
        ExactKey = Get-OrdinalTupleKey -Value $normalized.ToArray()
        Content = $content
        Tokens = $tokens
    }
}

function Get-FindingSimilarity {
    param(
        [Parameter(Mandatory)][object]$Left,
        [Parameter(Mandatory)][object]$Right
    )

    if ([string]::Equals($Left.ExactKey, $Right.ExactKey, [System.StringComparison]::Ordinal)) {
        return 'exact'
    }
    if ($Left.Content.Length -lt 48 -or $Right.Content.Length -lt 48 -or
        $Left.Tokens.Count -lt 8 -or $Right.Tokens.Count -lt 8) {
        return 'none'
    }
    $intersection = 0
    foreach ($token in $Left.Tokens) {
        if ($Right.Tokens.Contains($token)) { $intersection++ }
    }
    $union = $Left.Tokens.Count + $Right.Tokens.Count - $intersection
    if ($union -gt 0 -and ($intersection * 10) -ge ($union * 9)) { return 'near-duplicate' }
    return 'none'
}

function ConvertTo-ReviewInlineText {
    <#
    .SYNOPSIS
        One untrusted string rendered as inline Markdown: no structure of its own, no raw HTML, no
        table-cell break-out.
    #>
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }

    $text = $Value.Normalize([System.Text.NormalizationForm]::FormC)
    $text = ([regex]::Replace($text, '\s+', ' ')).Trim()
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $text = $text.Replace('\', '\\')
    foreach ($char in @('`', '*', '_', '[', ']', '|', '~', '!', '#')) {
        $text = $text.Replace($char, '\' + $char)
    }
    return $text
}

function ConvertTo-ReviewCodeSpan {
    <#
    .SYNOPSIS
        A schema-patterned identifier rendered as a code span. Anything the schema does not
        constrain by pattern goes through ConvertTo-ReviewInlineText instead.
    #>
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value -notmatch '^[A-Za-z0-9:._-]+$') {
        throw "Refusing to render '$Value' as a code span: it is not a schema-patterned identifier."
    }
    return '`' + $Value + '`'
}

function ConvertTo-ReviewFencedBlock {
    <#
    .SYNOPSIS
        One untrusted body rendered as an explicit untrusted-data block: HTML-encoded content inside
        a fence longer than any backtick run it contains, so no body can close its own fence.
    #>
    param([AllowEmptyString()][string]$Value)

    $text = ([string]$Value).Normalize([System.Text.NormalizationForm]::FormC)
    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')

    $longestRun = 0
    foreach ($match in [regex]::Matches($text, '`+')) {
        if ($match.Length -gt $longestRun) { $longestRun = $match.Length }
    }
    $fence = '`' * ([Math]::Max(3, $longestRun + 1))

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($fence + 'text')
    foreach ($line in ($text -split "`n")) { $lines.Add($line) }
    $lines.Add($fence)
    return , $lines.ToArray()
}

function ConvertTo-ReviewProjection {
    <#
    .SYNOPSIS
        The whole derived view model of one envelope: tasks in id order, attendance totals, run
        state and the merged findings in contract order.
    .DESCRIPTION
        Everything a view can show is derived here, once, from the envelope alone. The two renderers
        below only lay this out, which is what keeps the summary and the full view from disagreeing
        about what the run contained.
    #>
    param([Parameter(Mandatory)][object]$Run)

    $tasks = @(Get-Value -Node $Run -Name 'tasks')
    $findings = @(Get-Value -Node $Run -Name 'findings')
    $roster = @(Get-Value -Node $Run -Name 'roster' | ForEach-Object { [string]$_ })

    $taskById = @{}
    foreach ($task in $tasks) { $taskById[[string](Get-Value -Node $task -Name 'taskId')] = $task }

    $findingsByTask = @{}
    foreach ($finding in $findings) {
        $taskId = [string](Get-Value -Node $finding -Name 'taskId')
        if (-not $findingsByTask.ContainsKey($taskId)) { $findingsByTask[$taskId] = 0 }
        $findingsByTask[$taskId]++
    }

    # Task ids are unique by contract, so ordering by id is a total order that no input shuffle can
    # disturb — and it is the order the frozen plan is written in.
    $orderedTasks = [System.Collections.Generic.List[object]]::new()
    foreach ($taskId in (Sort-Ordinal -Value @($taskById.Keys | ForEach-Object { [string]$_ }))) {
        $task = $taskById[$taskId]
        $diagnostic = [string](Get-Value -Node $task -Name 'diagnostic')
        $orderedTasks.Add([pscustomobject]@{
                TaskId = $taskId
                Concern = [string](Get-Value -Node $task -Name 'concern')
                Model = [string](Get-Value -Node $task -Name 'model')
                Outcome = [string](Get-Value -Node $task -Name 'outcome')
                Diagnostic = $diagnostic
                RawFindings = $(if ($findingsByTask.ContainsKey($taskId)) { [int]$findingsByTask[$taskId] } else { 0 })
            })
    }

    $attendance = [ordered]@{}
    foreach ($outcome in $script:Outcomes) {
        $attendance[$outcome] = @($orderedTasks | Where-Object { $_.Outcome -eq $outcome }).Count
    }
    # D4: only an all-completed run is clean; every other valid mix is degraded.
    $state = $(if ([int]$attendance['completed'] -eq $orderedTasks.Count) { 'clean' } else { 'degraded' })

    $groups = [ordered]@{}
    foreach ($finding in $findings) {
        $taskId = [string](Get-Value -Node $finding -Name 'taskId')
        $task = $taskById[$taskId]
        $title = ([string](Get-Value -Node $finding -Name 'title')).Trim()
        $severity = [string](Get-Value -Node $finding -Name 'severity')
        $body = [string](Get-Value -Node $finding -Name 'body')
        $action = [string](Get-Value -Node $finding -Name 'action')
        $references = @(@(Get-Value -Node $finding -Name 'references') |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { ([string]$_).Trim() })

        $rootCause = [string](Get-Value -Node $finding -Name 'rootCause')
        if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = $title }
        $component = [string](Get-Value -Node $finding -Name 'component')
        if ([string]::IsNullOrWhiteSpace($component) -and $references.Count -gt 0) { $component = $references[0] }

        $key = (Get-ReviewNormalizedKey -Value $rootCause) + $script:Unit + (Get-ReviewNormalizedKey -Value $component)
        if (-not $groups.Contains($key)) {
            $groups[$key] = [pscustomobject]@{
                Key = $key
                Titles = [System.Collections.Generic.List[string]]::new()
                Bodies = [System.Collections.Generic.List[string]]::new()
                Actions = [System.Collections.Generic.List[string]]::new()
                Concerns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Models = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                References = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Raw = [System.Collections.Generic.List[object]]::new()
                Rank = 0
            }
        }

        $group = $groups[$key]
        $group.Titles.Add($title)
        if (-not [string]::IsNullOrWhiteSpace($body)) { $group.Bodies.Add($body.Trim()) }
        if (-not [string]::IsNullOrWhiteSpace($action)) { $group.Actions.Add($action.Trim()) }
        [void]$group.Concerns.Add(([string](Get-Value -Node $task -Name 'concern')).Trim())
        [void]$group.Models.Add([string](Get-Value -Node $task -Name 'model'))
        foreach ($reference in $references) { [void]$group.References.Add($reference) }
        if ($script:SeverityRank[$severity] -gt $group.Rank) { $group.Rank = $script:SeverityRank[$severity] }
        $group.Raw.Add([pscustomobject]@{
                TaskId = $taskId
                Concern = [string](Get-Value -Node $task -Name 'concern')
                Model = [string](Get-Value -Node $task -Name 'model')
                Severity = $severity
                Title = $title
                Body = $body
                Action = $action
                RootCause = $rootCause
                Component = $component
                References = $references
            })
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $groups.Values) {
        $models = @($roster | Where-Object { $group.Models.Contains([string]$_) })
        $concerns = @(Sort-Ordinal -Value @($group.Concerns))

        $observedModels = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$models,
            [System.StringComparer]::Ordinal
        )
        $unanimous = $roster.Count -ge 2 -and
        @($roster | Where-Object { -not $observedModels.Contains([string]$_) }).Count -eq 0

        # Longest first ("preserve the strongest"), ordinal for ties, so the choice never depends on
        # the order reviewers returned in.
        $orderedBodies = @(Sort-Ordinal -Value @($group.Bodies | ForEach-Object {
                    (Format-Invariant -Value (999999 - [Math]::Min($_.Length, 999999))).PadLeft(6, '0') + $script:Unit + $_
                }) | ForEach-Object { $_.Substring($_.IndexOf([char]1) + 1) })
        $distinctBodies = [System.Collections.Generic.List[string]]::new()
        foreach ($body in $orderedBodies) {
            if (-not $distinctBodies.Contains($body)) { $distinctBodies.Add($body) }
        }

        $title = @(Sort-Ordinal -Value @($group.Titles | ForEach-Object {
                    (Format-Invariant -Value (999999 - [Math]::Min($_.Length, 999999))).PadLeft(6, '0') + $script:Unit + $_
                }) | ForEach-Object { $_.Substring($_.IndexOf([char]1) + 1) })[0]

        $action = ''
        if ($group.Actions.Count -gt 0) { $action = @(Sort-Ordinal -Value @($group.Actions))[0] }
        elseif ($distinctBodies.Count -gt 0) {
            $flat = [regex]::Replace($distinctBodies[0].Trim(), '\s+', ' ')
            $match = [regex]::Match($flat, '^(?<sentence>.+?[.!?])(\s|$)')
            $action = $(if ($match.Success) { $match.Groups['sentence'].Value } else { $flat })
        }

        $rawByKey = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($record in $group.Raw) {
            $referenceKey = Get-OrdinalTupleKey -Value @($record.References | ForEach-Object { [string]$_ })
            $key = Get-OrdinalTupleKey -Value @(
                $record.TaskId, $record.Concern, $record.Model, $record.Severity, $record.Title,
                $record.Body, $record.Action, $record.RootCause, $record.Component, $referenceKey
            )
            $rawByKey.Add($key, $record)
        }
        $raw = @(Sort-Ordinal -Value @($rawByKey.Keys))
        $rawRecords = @($raw | ForEach-Object { $rawByKey[$_] })

        $profiles = @($rawRecords | ForEach-Object { Get-FindingSimilarityProfile -Finding $_ })
        $similarity = 'none'
        $modelsByExactKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new(
            [System.StringComparer]::Ordinal
        )
        for ($index = 0; $index -lt $rawRecords.Count; $index++) {
            $exactKey = [string]$profiles[$index].ExactKey
            if (-not $modelsByExactKey.ContainsKey($exactKey)) {
                $modelsByExactKey[$exactKey] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
            $exactModels = $modelsByExactKey[$exactKey]
            if ($exactModels.Count -gt 0 -and -not $exactModels.Contains([string]$rawRecords[$index].Model)) {
                $similarity = 'exact'
                break
            }
            [void]$exactModels.Add([string]$rawRecords[$index].Model)
        }
        for ($leftIndex = 0; $leftIndex -lt $rawRecords.Count -and $similarity -eq 'none'; $leftIndex++) {
            for ($rightIndex = $leftIndex + 1; $rightIndex -lt $rawRecords.Count; $rightIndex++) {
                if ([string]::Equals($rawRecords[$leftIndex].Model, $rawRecords[$rightIndex].Model, [System.StringComparison]::Ordinal)) {
                    continue
                }
                $similarity = Get-FindingSimilarity -Left $profiles[$leftIndex] -Right $profiles[$rightIndex]
                if ($similarity -ne 'none') { break }
            }
        }

        $corroborationState = if ($similarity -ne 'none') {
            'suspicious'
        }
        elseif ($state -ne 'clean') {
            'degraded'
        }
        elseif ($models.Count -ge 2) {
            'corroborated'
        }
        else {
            'single-source'
        }
        $elevated = $corroborationState -eq 'corroborated' -and $unanimous -and $group.Rank -lt 4
        $rank = $group.Rank + $(if ($elevated) { 1 } else { 0 })
        $reason = switch ($corroborationState) {
            'suspicious' {
                "needs-review: $similarity normalized finding text appears under distinct declared model labels; severity elevation suppressed"
            }
            'degraded' {
                'review attendance is degraded; severity elevation suppressed'
            }
            'corroborated' {
                if ($unanimous) {
                    'every declared model label reported this finding with complete attendance; no suspicious similarity observed'
                }
                else {
                    'multiple declared model labels reported this finding with complete attendance; no suspicious similarity observed'
                }
            }
            default {
                'one declared model label reported this finding with complete attendance'
            }
        }

        $entries.Add([pscustomobject]@{
                Key = $group.Key
                Title = $title
                Rank = $rank
                Severity = $script:SeverityByRank[$rank]
                Elevated = $elevated
                Concerns = $concerns
                Models = $models
                Bodies = @($distinctBodies)
                References = @(Sort-Ordinal -Value @($group.References))
                Action = $action
                Raw = $rawRecords
                RawCount = $group.Raw.Count
                Similarity = $similarity
                CorroborationState = $corroborationState
                SupportCount = $models.Count
                AttendanceState = $state
                RawSeverity = $script:SeverityByRank[$group.Rank]
                EffectiveSeverity = $script:SeverityByRank[$rank]
                NeedsReview = $corroborationState -eq 'suspicious'
                Reason = $reason
            })
    }

    # One composite ordinal key: severity, then breadth of agreement, then title, then the grouping
    # key, which is unique by construction and therefore makes this a total order.
    $sortKeys = @{}
    foreach ($entry in $entries) {
        $sortKeys[$entry.Key] = (Format-Invariant -Value (9 - $entry.Rank)).PadLeft(2, '0') + $script:Unit +
        (Format-Invariant -Value (9999 - [Math]::Min($entry.Models.Count, 9999))).PadLeft(4, '0') + $script:Unit +
        $entry.Title + $script:Unit + $entry.Key
    }
    $byKey = @{}
    foreach ($entry in $entries) { $byKey[$sortKeys[$entry.Key]] = $entry }
    $sorted = @(Sort-Ordinal -Value @($sortKeys.Values | ForEach-Object { [string]$_ }) | ForEach-Object { $byKey[$_] })

    return [pscustomobject]@{
        RunId = [string](Get-Value -Node $Run -Name 'runId')
        ReviewType = [string](Get-Value -Node $Run -Name 'reviewType')
        ContentTrust = [string](Get-Value -Node $Run -Name 'contentTrust')
        Scope = [string](Get-Value -Node $Run -Name 'scope')
        ScopeAuthority = Get-Value -Node $Run -Name 'scopeAuthority'
        PlanDigest = [string](Get-Value -Node $Run -Name 'planDigest')
        InvocationBudget = [int](Get-Value -Node $Run -Name 'invocationBudget')
        ModelSelection = @(Get-Value -Node $Run -Name 'modelSelection')
        Roster = $roster
        Tasks = @($orderedTasks)
        Attendance = $attendance
        State = $state
        Findings = $sorted
        RawFindingCount = $findings.Count
    }
}

function Get-ReportTitle {
    param([Parameter(Mandatory)][string]$ReviewType)

    return $(if ($ReviewType -eq 'design') { 'Design Review' } else { 'Code Review' })
}

function Get-HeaderTable {
    <#
    .SYNOPSIS
        The identity block both views open with, so a summary and a full view of the same run can
        never disagree about which run they describe.
    #>
    param([Parameter(Mandatory)][object]$Projection)

    $models = @($Projection.ModelSelection | ForEach-Object {
            $requested = ConvertTo-ReviewInlineText -Value ([string](Get-Value -Node $_ -Name 'requested'))
            $declared = ConvertTo-ReviewInlineText -Value ([string](Get-Value -Node $_ -Name 'declared'))
            $preflight = ConvertTo-ReviewInlineText -Value ([string](Get-Value -Node $_ -Name 'preflight'))
            $degradation = ConvertTo-ReviewInlineText -Value ([string](Get-Value -Node $_ -Name 'degradation'))
            "$requested → $declared (preflight: $preflight; degradation: $degradation; served identity: unverified)"
        })
    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add('| | |')
    $rows.Add('|---|---|')
    $rows.Add("| **Run** | $(ConvertTo-ReviewCodeSpan -Value $Projection.RunId) |")
    $rows.Add("| **Review type** | $(ConvertTo-ReviewCodeSpan -Value $Projection.ReviewType) |")
    $rows.Add("| **State** | $(ConvertTo-ReviewCodeSpan -Value $Projection.State) |")
    $rows.Add("| **Plan digest** | $(ConvertTo-ReviewCodeSpan -Value $Projection.PlanDigest) |")
    $rows.Add("| **Scope digest** | $(ConvertTo-ReviewCodeSpan -Value ([string](Get-Value -Node $Projection.ScopeAuthority -Name 'digest'))) |")
    $rows.Add("| **Scope** | $(ConvertTo-ReviewInlineText -Value $Projection.Scope) |")
    $rows.Add("| **Content trust** | $(ConvertTo-ReviewCodeSpan -Value $Projection.ContentTrust) |")
    $rows.Add("| **Requested → declared models** | $($models -join ' · ') |")
    $rows.Add("| **Invocations** | $(Format-Invariant -Value $Projection.Tasks.Count) of $(Format-Invariant -Value $Projection.InvocationBudget) budgeted |")
    return , $rows.ToArray()
}

function Get-SeverityCell {
    param([Parameter(Mandatory)][object]$Entry)

    if ($Entry.Elevated) { return "$($Entry.EffectiveSeverity) (elevated — flagged under every declared model label)" }
    return [string]$Entry.EffectiveSeverity
}

function Get-SeverityCode {
    param([Parameter(Mandatory)][string]$Severity)

    return [string]@{ Critical = 'C'; High = 'H'; Medium = 'M'; Low = 'L' }[$Severity]
}

function Get-EvidenceCode {
    param(
        [Parameter(Mandatory)][ValidateSet('Attendance', 'Similarity', 'Corroboration')][string]$Kind,
        [Parameter(Mandatory)][string]$Value
    )

    $codes = switch ($Kind) {
        'Attendance' { @{ clean = 'C'; degraded = 'D' } }
        'Similarity' { @{ none = 'N'; 'near-duplicate' = '~'; exact = 'X' } }
        default { @{ corroborated = 'C'; 'single-source' = '1'; suspicious = 'S'; degraded = 'D' } }
    }
    return [string]$codes[$Value]
}

function New-ReviewSummaryView {
    <#
    .SYNOPSIS
        The v1 summary view: at most 32 KiB, naming every merged finding by severity and title, and
        reporting the attendance totals for every outcome the contract defines.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Run)

    $projection = ConvertTo-ReviewProjection -Run $Run
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# $(Get-ReportTitle -ReviewType $projection.ReviewType) — summary")
    $lines.Add('')
    $lines.Add('<!-- skalary/review-summary@1 -->')
    $lines.Add('')
    foreach ($row in (Get-HeaderTable -Projection $projection)) { $lines.Add($row) }
    $lines.Add('')

    $lines.Add('## Attendance')
    $lines.Add('')
    $lines.Add('| Outcome | Tasks |')
    $lines.Add('|---|---|')
    foreach ($outcome in $script:Outcomes) {
        $lines.Add("| $(ConvertTo-ReviewCodeSpan -Value $outcome) | $(Format-Invariant -Value ([int]$projection.Attendance[$outcome])) |")
    }
    $lines.Add("| **planned** | $(Format-Invariant -Value $projection.Tasks.Count) |")
    $lines.Add('')

    $merged = @($projection.Findings)
    $lines.Add("## Merged findings ($(Format-Invariant -Value $merged.Count) of $(Format-Invariant -Value $projection.RawFindingCount) raw)")
    $lines.Add('')
    if ($merged.Count -eq 0) {
        $lines.Add('None.')
        $lines.Add('')
        return (($lines -join "`n") + "`n")
    }

    $lines.Add('| # | Raw severity → effective severity | Support / attendance / similarity / corroboration | Title | Reason |')
    $lines.Add('|---|---|---|---|---|')
    $reasonIds = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    $index = 0
    foreach ($entry in $merged) {
        $index++
        if (-not $reasonIds.Contains($entry.Reason)) {
            $reasonIds[$entry.Reason] = 'R' + (Format-Invariant -Value ($reasonIds.Count + 1))
        }
        $lines.Add("| $(Format-Invariant -Value $index) | $(Get-SeverityCode -Severity $entry.RawSeverity)→" +
            "$(Get-SeverityCode -Severity $entry.EffectiveSeverity) | $(Format-Invariant -Value $entry.SupportCount)/" +
            "$(Get-EvidenceCode -Kind Attendance -Value $entry.AttendanceState)/" +
            "$(Get-EvidenceCode -Kind Similarity -Value $entry.Similarity)/" +
            "$(Get-EvidenceCode -Kind Corroboration -Value $entry.CorroborationState) | " +
            "$(ConvertTo-ReviewInlineText -Value $entry.Title) | " +
            "$(ConvertTo-ReviewCodeSpan -Value ([string]$reasonIds[$entry.Reason])) |")
    }
    $lines.Add('')
    $lines.Add('### Reason legend')
    $lines.Add('')
    $lines.Add('Severity: C = Critical; H = High; M = Medium; L = Low.')
    $lines.Add('Evidence: support count / attendance (C = clean, D = degraded) / similarity (N = none, ~ = near-duplicate, X = exact) / corroboration (C = corroborated, 1 = single-source, S = suspicious, D = degraded).')
    $lines.Add('')
    foreach ($reason in $reasonIds.Keys) {
        $lines.Add("- $(ConvertTo-ReviewCodeSpan -Value ([string]$reasonIds[$reason])) — $(ConvertTo-ReviewInlineText -Value ([string]$reason))")
    }
    $lines.Add('')

    return (($lines -join "`n") + "`n")
}

function New-ReviewFullView {
    <#
    .SYNOPSIS
        The v1 full view: at most 1 MiB, listing every planned task and every merged finding with
        the raw records behind it, so no task and no reviewer record is silently absent.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Run)

    $projection = ConvertTo-ReviewProjection -Run $Run
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# $(Get-ReportTitle -ReviewType $projection.ReviewType) — full report")
    $lines.Add('')
    $lines.Add('<!-- skalary/review-full@1 -->')
    $lines.Add('<!-- content-trust: reviewer-authored-data -->')
    $lines.Add('')
    foreach ($row in (Get-HeaderTable -Projection $projection)) { $lines.Add($row) }
    $lines.Add('')

    $lines.Add("## Tasks ($(Format-Invariant -Value $projection.Tasks.Count))")
    $lines.Add('')
    $lines.Add('| # | Task | Concern | Declared model | Outcome | Raw findings | Diagnostic |')
    $lines.Add('|---|---|---|---|---|---|---|')
    $index = 0
    foreach ($task in $projection.Tasks) {
        $index++
        $diagnostic = $(if ([string]::IsNullOrWhiteSpace($task.Diagnostic)) { '—' } else { ConvertTo-ReviewInlineText -Value $task.Diagnostic })
        $lines.Add("| $(Format-Invariant -Value $index) | $(ConvertTo-ReviewCodeSpan -Value $task.TaskId) | " +
            "$(ConvertTo-ReviewCodeSpan -Value $task.Concern) | $(ConvertTo-ReviewInlineText -Value $task.Model) | " +
            "$(ConvertTo-ReviewCodeSpan -Value $task.Outcome) | $(Format-Invariant -Value $task.RawFindings) | $diagnostic |")
    }
    $lines.Add('')

    $merged = @($projection.Findings)
    $lines.Add("## Merged findings ($(Format-Invariant -Value $merged.Count) of $(Format-Invariant -Value $projection.RawFindingCount) raw)")
    $lines.Add('')
    if ($merged.Count -eq 0) {
        $lines.Add('None.')
        $lines.Add('')
        $lines.Add('## Recommendations')
        $lines.Add('')
        $lines.Add('None.')
        $lines.Add('')
        return (($lines -join "`n") + "`n")
    }

    $index = 0
    foreach ($entry in $merged) {
        $index++
        $lines.Add("### [$(Format-Invariant -Value $index)] $(ConvertTo-ReviewInlineText -Value $entry.Title)")
        $lines.Add('')
        $lines.Add('| | |')
        $lines.Add('|---|---|')
        $lines.Add("| **Raw severity** | $(ConvertTo-ReviewCodeSpan -Value $entry.RawSeverity) |")
        $lines.Add("| **Effective severity** | $(Get-SeverityCell -Entry $entry) |")
        $lines.Add("| **Support count** | $(Format-Invariant -Value $entry.SupportCount) |")
        $lines.Add("| **Attendance state** | $(ConvertTo-ReviewCodeSpan -Value $entry.AttendanceState) |")
        $lines.Add("| **Similarity** | $(ConvertTo-ReviewCodeSpan -Value $entry.Similarity) |")
        $lines.Add("| **Corroboration state** | $(ConvertTo-ReviewCodeSpan -Value $entry.CorroborationState) |")
        $lines.Add("| **Reason** | $(ConvertTo-ReviewInlineText -Value $entry.Reason) |")
        $lines.Add("| **Concerns** | $(@($entry.Concerns | ForEach-Object { ConvertTo-ReviewCodeSpan -Value $_ }) -join ' · ') |")
        $lines.Add("| **Declared model labels** | $(@($entry.Models | ForEach-Object { ConvertTo-ReviewInlineText -Value $_ }) -join ' · ') |")
        $lines.Add("| **Raw findings** | $(Format-Invariant -Value $entry.RawCount) |")
        $lines.Add('')

        if ($entry.Bodies.Count -gt 0) {
            $lines.Add('**Description:**')
            $lines.Add('')
            foreach ($line in (ConvertTo-ReviewFencedBlock -Value $entry.Bodies[0])) { $lines.Add($line) }
            $lines.Add('')
            foreach ($extra in @($entry.Bodies | Select-Object -Skip 1)) {
                $lines.Add('**Also noted:**')
                $lines.Add('')
                foreach ($line in (ConvertTo-ReviewFencedBlock -Value $extra)) { $lines.Add($line) }
                $lines.Add('')
            }
        }

        if ($entry.References.Count -gt 0) {
            $lines.Add('**References:**')
            $lines.Add('')
            foreach ($reference in $entry.References) { $lines.Add("- $(ConvertTo-ReviewInlineText -Value $reference)") }
            $lines.Add('')
        }

        $lines.Add('**Raw records:**')
        $lines.Add('')
        $lines.Add('| Task | Severity | Title |')
        $lines.Add('|---|---|---|')
        foreach ($record in $entry.Raw) {
            $lines.Add("| $(ConvertTo-ReviewCodeSpan -Value $record.TaskId) | $(ConvertTo-ReviewCodeSpan -Value $record.Severity) | " +
                "$(ConvertTo-ReviewInlineText -Value $record.Title) |")
        }
        $lines.Add('')
        $lines.Add('---')
        $lines.Add('')
    }

    $lines.Add('## Recommendations')
    $lines.Add('')
    $index = 0
    foreach ($entry in $merged) {
        $index++
        $action = $(if ([string]::IsNullOrWhiteSpace($entry.Action)) { $entry.Title } else { $entry.Action })
        $lines.Add("$(Format-Invariant -Value $index). **\[$($entry.EffectiveSeverity)\] $(ConvertTo-ReviewInlineText -Value $entry.Title)** — $(ConvertTo-ReviewInlineText -Value $action)")
    }
    $lines.Add('')

    return (($lines -join "`n") + "`n")
}

Export-ModuleMember -Function @(
    'ConvertTo-ReviewProjection', 'ConvertTo-ReviewInlineText', 'ConvertTo-ReviewFencedBlock',
    'Get-ReviewNormalizedKey', 'New-ReviewSummaryView', 'New-ReviewFullView'
)
