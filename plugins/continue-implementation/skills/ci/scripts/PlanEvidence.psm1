#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ReviewResultReceipt.psm1') -DisableNameChecking

$script:PlanEvidenceOutcomes = @('passed', 'failed', 'skipped', 'unrun', 'stale', 'degraded', 'waived')

function Get-PlanEvidenceField {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    return $null
}

function ConvertTo-PlanEvidenceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )

    process {
        $req = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Req')
        $marker = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Marker')
        if ([string]::IsNullOrWhiteSpace($req) -or $req -notmatch '^REQ-\d+$') {
            throw "Evidence result has invalid requirement '$req'."
        }
        if ([string]::IsNullOrWhiteSpace($marker)) {
            throw 'Evidence result requires a non-empty Marker.'
        }

        $hasStatus = $InputObject.PSObject.Properties.Name -contains 'Status'
        $hasSuccess = $InputObject.PSObject.Properties.Name -contains 'Success'
        $status = if ($hasStatus) {
            [string]$InputObject.Status
        }
        elseif ($hasSuccess) {
            if ($InputObject.Success -eq $true) { 'passed' }
            elseif ($InputObject.Success -eq $false) { 'failed' }
            else { 'unrun' }
        }
        else {
            'unrun'
        }
        if ($status -cnotin $script:PlanEvidenceOutcomes) {
            throw "Evidence result for '$marker' has invalid status '$status'."
        }

        if ($hasStatus -and $hasSuccess) {
            $expectedSuccess = $status -in @('passed', 'waived')
            if ($null -ne $InputObject.Success -and [bool]$InputObject.Success -ne $expectedSuccess) {
                throw "Evidence result for '$marker' has conflicting Status and Success fields."
            }
        }

        $note = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Note')
        if ([string]::IsNullOrWhiteSpace($note)) {
            $note = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Message')
        }
        foreach ($value in @($req, $marker, $note)) {
            if ($value -match "[`r`n]" -or $value.Contains(" $([char]0x2014) ")) {
                throw "Evidence result for '$marker' contains a receipt delimiter or line break."
            }
        }

        $reviewRunId = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'ReviewRunId')
        if (-not [string]::IsNullOrWhiteSpace($reviewRunId) -and
            $reviewRunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            throw "Evidence result for '$marker' has invalid ReviewRunId '$reviewRunId'."
        }

        return [pscustomobject]@{
            Req = $req
            Marker = $marker
            Status = $status
            Success = ($status -in @('passed', 'waived'))
            Note = $note.Trim()
            ReviewRunId = $reviewRunId
        }
    }
}

function Get-ReviewCycleSourceRecordId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][ValidateRange(0, 999)][int]$Phase,
        [Parameter(Mandatory)][string]$Label
    )

    $pattern = '^- \[(?<step>-|[0-9]+\.[0-9]+[a-z]?)\] ' +
        '\[src:(?<src>code-review|discovery|note)\] ' +
        '\[sev:(?<sev>Critical|High|Med|Low)\] ' +
        '\[concern:(?<concern>security|correctness-reliability|architecture-patterns|performance|testing-evidence|maintainability-consistency|operability-observability)\] ' +
        '\[req:(?<req>-|REQ-[1-9][0-9]*(?:,REQ-[1-9][0-9]*)*)\] ' +
        '\[review:(?<review>cr|dr|none)\] ' +
        '\[source-record:(?<record>[0-9a-f]{64})\] (?<body>.+)$'
    $match = [regex]::Match($Line, $pattern)
    if (-not $match.Success) {
        throw "$Label is not a supported typed workflow source record."
    }

    $fields = @(
        $PlanId,
        [string]$Phase,
        $match.Groups['step'].Value,
        $match.Groups['concern'].Value,
        $match.Groups['req'].Value,
        $match.Groups['review'].Value,
        $match.Groups['src'].Value,
        $match.Groups['sev'].Value,
        '-',
        $match.Groups['body'].Value
    )
    $framed = 'workflow-note/crlog/source-record/v1' + [char]0 + ($fields -join [char]0)
    $expected = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($framed)
        )
    ).ToLowerInvariant()
    $actual = $match.Groups['record'].Value
    if ($expected -cne $actual) {
        throw "$Label source-record digest does not match plan '$PlanId' phase $Phase."
    }
    return $actual
}

function Get-PlanReviewCycleState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanDir,
        [Parameter(Mandatory)]
        [ValidatePattern('^(?:step-[0-9]+\.[0-9]+[a-z]?|phase-[0-9]+|plan-finalization)$')]
        [string]$Stage,
        [string]$RepoRoot,
        [ValidateRange(0, 999)]
        [int]$SourcePhase,
        [switch]$ValidateSourceRecords
    )

    if ($ValidateSourceRecords -and
        ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not $PSBoundParameters.ContainsKey('SourcePhase'))) {
        throw 'Source-record validation requires explicit -RepoRoot and -SourcePhase.'
    }

    $assetArgs = @{ PlanDir = $PlanDir; Kind = 'CrLog' }
    $planId = ''
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
        $inventory = @(Get-PlanInventory -RepoRoot $repoRootFull)
        $assetArgs.RepoRoot = $repoRootFull
        $assetArgs.Inventory = $inventory
        if ($ValidateSourceRecords) {
            $planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
            $comparison = if ($IsWindows) {
                [System.StringComparison]::OrdinalIgnoreCase
            }
            else {
                [System.StringComparison]::Ordinal
            }
            $planRecord = @($inventory | Where-Object {
                    $_.Path -and [string]::Equals(
                        [System.IO.Path]::GetFullPath([string]$_.Path),
                        $planDirFull,
                        $comparison
                    )
                })
            if ($planRecord.Count -ne 1) {
                throw "Plan folder '$planDirFull' is not a unique member of the repository plan inventory."
            }
            $planId = [string]$planRecord[0].Id
        }
    }

    $logPath = Resolve-PlanAssetPath @assetArgs
    $raw = if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Get-Content -LiteralPath $logPath -Raw
    }
    else {
        ''
    }
    $raw = $raw -replace "`r`n?", "`n"
    $stagePattern = [regex]::Escape($Stage)
    $provenancePattern = '(?: \[[^\]]+\])*'
    $cycleMatches = [regex]::Matches(
        $raw,
        "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle stage=$stagePattern cycle=(?<cycle>[0-9]+) outcome=(?<outcome>clean|findings)(?: run=(?<runId>[0-9a-f-]+))?(?: summary=.*)?$"
    )
    $cycles = @($cycleMatches | ForEach-Object { [int]$_.Groups['cycle'].Value })
    $count = $cycles.Count
    if ($count -gt 0 -and (($cycles -join ',') -ne ((1..$count) -join ','))) {
        throw "Review-cycle history for '$Stage' is not the append-only sequence 1..$count."
    }

    $events = [System.Collections.Generic.List[object]]::new()
    $decisionMatches = [regex]::Matches(
        $raw,
        "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle-decision stage=$stagePattern after=(?<after>[0-9]+) action=(?<action>continue|wrap)$"
    )
    foreach ($match in $decisionMatches) {
        $eventId = 'sha256:' + [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($match.Value)
            )
        ).ToLowerInvariant()
        $events.Add([pscustomobject]@{
                Index = $match.Index
                After = [int]$match.Groups['after'].Value
                Action = [string]$match.Groups['action'].Value
                Authorization = ''
                EventId = $eventId
                Reason = ''
                TargetEventId = ''
                Timestamp = ''
            })
    }
    $remediationMatches = [regex]::Matches(
        $raw,
        "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle-remediation stage=$stagePattern after=(?<after>[0-9]+) action=reopen authorization=(?<authorization>[A-Za-z0-9][A-Za-z0-9._:-]{0,127}) reason=(?<reason>.+)$"
    )
    foreach ($match in $remediationMatches) {
        $eventIdMatches = [regex]::Matches($match.Value, '\[source-record:(?<id>[0-9a-f]{64})\]')
        $eventId = if ($eventIdMatches.Count -eq 1) {
            [string]$eventIdMatches[0].Groups['id'].Value
        }
        else {
            ''
        }
        if ($ValidateSourceRecords) {
            $eventId = Get-ReviewCycleSourceRecordId -Line $match.Value -PlanId $planId `
                -Phase $SourcePhase -Label "Reopen event for '$Stage'"
        }
        $events.Add([pscustomobject]@{
                Index = $match.Index
                After = [int]$match.Groups['after'].Value
                Action = 'reopen'
                Authorization = [string]$match.Groups['authorization'].Value
                EventId = $eventId
                Reason = [string]$match.Groups['reason'].Value
                TargetEventId = ''
                Timestamp = ''
            })
    }
    $invalidationMatches = [regex]::Matches(
        $raw,
        "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle-remediation stage=$stagePattern after=(?<after>[0-9]+) action=invalidate-continue target=(?<target>sha256:[0-9a-f]{64}) authorization=(?<authorization>[A-Za-z0-9][A-Za-z0-9._:-]{0,127}) timestamp=(?<timestamp>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{7}Z) reason=(?<reason>.+)$"
    )
    foreach ($match in $invalidationMatches) {
        $events.Add([pscustomobject]@{
                Index = $match.Index
                After = [int]$match.Groups['after'].Value
                Action = 'invalidate-continue'
                Authorization = [string]$match.Groups['authorization'].Value
                EventId = ''
                Reason = [string]$match.Groups['reason'].Value
                TargetEventId = [string]$match.Groups['target'].Value
                Timestamp = [string]$match.Groups['timestamp'].Value
            })
    }
    $reopenInvalidationMatches = [regex]::Matches(
        $raw,
        "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle-remediation stage=$stagePattern after=(?<after>[0-9]+) action=invalidate-reopen target=(?<target>[0-9a-f]{64}) authorization=(?<authorization>[A-Za-z0-9][A-Za-z0-9._:-]{0,127}) timestamp=(?<timestamp>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{7}Z) reason=(?<reason>.+)$"
    )
    foreach ($match in $reopenInvalidationMatches) {
        $eventIdMatches = [regex]::Matches($match.Value, '\[source-record:(?<id>[0-9a-f]{64})\]')
        $eventId = if ($eventIdMatches.Count -eq 1) {
            [string]$eventIdMatches[0].Groups['id'].Value
        }
        else {
            ''
        }
        if ($ValidateSourceRecords) {
            $eventId = Get-ReviewCycleSourceRecordId -Line $match.Value -PlanId $planId `
                -Phase $SourcePhase -Label "Reopen invalidation for '$Stage'"
        }
        $events.Add([pscustomobject]@{
                Index = $match.Index
                After = [int]$match.Groups['after'].Value
                Action = 'invalidate-reopen'
                Authorization = [string]$match.Groups['authorization'].Value
                EventId = $eventId
                Reason = [string]$match.Groups['reason'].Value
                TargetEventId = [string]$match.Groups['target'].Value
                Timestamp = [string]$match.Groups['timestamp'].Value
            })
    }
    $orderedEvents = @($events | Sort-Object Index)
    foreach ($invalidation in @($orderedEvents | Where-Object Action -eq 'invalidate-continue')) {
        $priorEvents = @($orderedEvents | Where-Object Index -lt $invalidation.Index)
        $priorEvent = @($priorEvents | Select-Object -Last 1)
        $targets = @($orderedEvents | Where-Object {
                $_.Action -eq 'continue' -and $_.EventId -ceq $invalidation.TargetEventId
            })
        if ($targets.Count -ne 1) {
            throw "Review-cycle invalidation for '$Stage' has an ambiguous or missing Continue target '$($invalidation.TargetEventId)'."
        }
        if ($priorEvent.Count -ne 1 -or
            $priorEvent[0].Action -ne 'continue' -or
            $priorEvent[0].Index -ne $targets[0].Index) {
            throw "Review-cycle invalidation for '$Stage' does not target the latest event."
        }
        $cyclesBeforeInvalidation = @($cycleMatches | Where-Object Index -lt $invalidation.Index)
        $interveningCycles = @($cycleMatches | Where-Object {
                $_.Index -gt $targets[0].Index -and $_.Index -lt $invalidation.Index
            })
        if ($targets[0].After -ne $invalidation.After -or
            $cyclesBeforeInvalidation.Count -ne $invalidation.After -or
            $interveningCycles.Count -gt 0) {
            throw "Review-cycle invalidation for '$Stage' is stale or follows a later review result."
        }
    }
    foreach ($invalidation in @($orderedEvents | Where-Object Action -eq 'invalidate-reopen')) {
        $priorEvents = @($orderedEvents | Where-Object Index -lt $invalidation.Index)
        $priorEvent = @($priorEvents | Select-Object -Last 1)
        $targets = @($orderedEvents | Where-Object {
                $_.Action -eq 'reopen' -and $_.EventId -ceq $invalidation.TargetEventId
            })
        if ($targets.Count -ne 1) {
            throw "Review-cycle invalidation for '$Stage' has an ambiguous or missing Reopen source record '$($invalidation.TargetEventId)'."
        }
        if ($priorEvent.Count -ne 1 -or
            $priorEvent[0].Action -ne 'reopen' -or
            $priorEvent[0].Index -ne $targets[0].Index) {
            throw "Review-cycle Reopen invalidation for '$Stage' does not target the latest event."
        }
        $eventsBeforeTarget = @($orderedEvents | Where-Object Index -lt $targets[0].Index)
        $wrappedEvent = @($eventsBeforeTarget | Select-Object -Last 1)
        if ($wrappedEvent.Count -ne 1 -or
            $wrappedEvent[0].Action -ne 'wrap' -or
            $wrappedEvent[0].After -ne $targets[0].After) {
            throw "Review-cycle Reopen invalidation for '$Stage' does not restore a prior Wrap."
        }
        $cyclesBeforeInvalidation = @($cycleMatches | Where-Object Index -lt $invalidation.Index)
        $interveningCycles = @($cycleMatches | Where-Object {
                $_.Index -gt $targets[0].Index -and $_.Index -lt $invalidation.Index
            })
        if ($targets[0].After -ne $invalidation.After -or
            $cyclesBeforeInvalidation.Count -ne $invalidation.After -or
            $interveningCycles.Count -gt 0) {
            throw "Review-cycle Reopen invalidation for '$Stage' is stale or follows a later review result."
        }
    }
    $latestEvent = @($orderedEvents | Select-Object -Last 1)
    $latestEvent = if ($latestEvent.Count -eq 1) { $latestEvent[0] } else { $null }
    $previousEvent = if ($orderedEvents.Count -gt 1) {
        $orderedEvents[$orderedEvents.Count - 2]
    }
    else {
        $null
    }

    $latestCycle = if ($cycleMatches.Count -gt 0) { $cycleMatches[$cycleMatches.Count - 1] } else { $null }
    $latestCycleIndex = if ($null -ne $latestCycle) { $latestCycle.Index } else { -1 }
    $currentContinueCount = @($orderedEvents | Where-Object {
            $_.Action -eq 'continue' -and $_.After -eq $count -and $_.Index -gt $latestCycleIndex
        }).Count
    $currentReopenCount = @($orderedEvents | Where-Object {
            $_.Action -eq 'reopen' -and $_.After -eq $count -and $_.Index -gt $latestCycleIndex
        }).Count
    $latestOutcome = if ($null -ne $latestCycle) { [string]$latestCycle.Groups['outcome'].Value } else { '' }
    $reviewRunId = if ($null -ne $latestCycle -and $latestCycle.Groups['runId'].Success) {
        [string]$latestCycle.Groups['runId'].Value
    }
    else {
        ''
    }

    $state = if ($latestOutcome -eq 'clean' -and
        $reviewRunId -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        'complete'
    }
    elseif ($latestOutcome -eq 'clean') {
        'legacy-clean'
    }
    elseif ($count -lt 3) {
        'allow'
    }
    elseif ($null -ne $latestEvent -and $latestEvent.After -eq $count) {
        if ($latestEvent.Action -in @('continue', 'reopen')) {
            'allow'
        }
        elseif ($latestEvent.Action -eq 'invalidate-continue') {
            'operator-decision'
        }
        elseif ($latestEvent.Action -eq 'invalidate-reopen') {
            'wrap'
        }
        else {
            'wrap'
        }
    }
    else {
        'operator-decision'
    }

    return [pscustomobject]@{
        State = $state
        Cycles = $count
        LatestEvent = $latestEvent
        PreviousEvent = $previousEvent
        LatestCycleIndex = $latestCycleIndex
        CurrentContinueCount = $currentContinueCount
        CurrentReopenCount = $currentReopenCount
        LatestOutcome = $latestOutcome
        ReviewRunId = $reviewRunId
        LogPath = $logPath
    }
}

function Assert-ReviewResultReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReceiptContent,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')]
        [string]$ReviewRunId,
        [Parameter(Mandatory)][string]$ReportName,
        [Parameter(Mandatory)][byte[]]$ReportBytes
    )

    return ReviewResultReceipt\Assert-ReviewResultReceipt @PSBoundParameters
}

function Assert-PlanReviewResultReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanDir,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')]
        [string]$ReviewRunId,
        [string]$Commit,
        [switch]$RequireBranchScope,
        [string]$RepoRoot
    )

    $store = Resolve-PlanAssetPath -PlanDir $PlanDir -Kind ReviewRuns
    $receiptPath = Join-Path $store "$ReviewRunId.receipt.json"
    $reportPath = Join-Path $store "$ReviewRunId.review.md"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Clean review evidence for run '$ReviewRunId' is missing its retained report/receipt pair."
    }
    if ((Get-Item -LiteralPath $receiptPath -Force).Length -gt 65536) {
        throw "Review result receipt for run '$ReviewRunId' exceeds 65536 bytes."
    }

    $reportBytes = [System.IO.File]::ReadAllBytes($reportPath)
    $receipt = Assert-ReviewResultReceipt `
        -ReceiptContent (Get-Content -LiteralPath $receiptPath -Raw -Force) `
        -ReviewRunId $ReviewRunId `
        -ReportName "$ReviewRunId.review.md" `
        -ReportBytes $reportBytes
    if ($receipt['reviewType'] -cne 'code' -or
        $receipt['state'] -cne 'clean' -or
        $receipt['verdict'] -cne 'approved') {
        throw "Review run '$ReviewRunId' is not qualifying clean code-review evidence."
    }
    if ([int]$receipt['findings']['merged'] -ne 0 -or [int]$receipt['findings']['raw'] -ne 0) {
        throw "Review run '$ReviewRunId' still contains findings."
    }
    if ([int]$receipt['attendance']['completed'] -lt 1) {
        throw "Review run '$ReviewRunId' has no completed attendance."
    }
    foreach ($name in @('critical', 'high', 'medium', 'low')) {
        if ([int]$receipt['findings']['severity'][$name] -ne 0) {
            throw "Review run '$ReviewRunId' still contains $name findings."
        }
    }
    foreach ($name in @('failed', 'timed-out', 'omitted', 'cancelled', 'pending')) {
        if ([int]$receipt['attendance'][$name] -ne 0) {
            throw "Review run '$ReviewRunId' has non-completed attendance."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Commit) -and $receipt['source']['head'] -cne $Commit) {
        throw "Review run '$ReviewRunId' reviewed commit '$($receipt['source']['head'])', not '$Commit'."
    }
    if ($RequireBranchScope -and $receipt['source']['mode'] -cne 'branch') {
        throw "Review run '$ReviewRunId' is not whole-branch evidence."
    }
    if ($RequireBranchScope) {
        if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
            throw 'Whole-branch review evidence requires -RepoRoot.'
        }
        $repoFull = [System.IO.Path]::GetFullPath($RepoRoot)
        $defaultRef = (& git -C $repoFull symbolic-ref refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($defaultRef)) {
            throw "Whole-branch review evidence could not resolve refs/remotes/origin/HEAD under '$repoFull'."
        }
        $mergeBase = (& git -C $repoFull merge-base $Commit $defaultRef.Trim() 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mergeBase)) {
            throw "Whole-branch review evidence could not resolve the default-branch merge base for '$Commit'."
        }
        $mergeBase = $mergeBase.Trim().ToLowerInvariant()
        if ($receipt['source']['base'] -cne $mergeBase) {
            throw "Review run '$ReviewRunId' used base '$($receipt['source']['base'])', not canonical merge base '$mergeBase'."
        }
        $changedPaths = @(& git -C $repoFull diff --name-only "$mergeBase..$Commit" 2>$null)
        if ($LASTEXITCODE -ne 0 -or [int]$receipt['source']['pathCount'] -ne $changedPaths.Count) {
            throw "Review run '$ReviewRunId' does not cover the canonical whole-branch path count."
        }
    }
    return [pscustomobject]@{ Receipt = $receipt; ReceiptPath = $receiptPath; ReportPath = $reportPath }
}

function Assert-PlanCleanReviewEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanDir,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$ReviewRunId,
        [string]$RepoRoot
    )

    $cycle = Get-PlanReviewCycleState -PlanDir $PlanDir -Stage $Stage
    if ($cycle.State -ne 'complete') {
        throw "review:cr cannot pass while review-cycle stage '$Stage' is '$($cycle.State)'."
    }
    if ($cycle.ReviewRunId -cne $ReviewRunId) {
        throw "review:cr run '$ReviewRunId' does not match the durable clean cycle '$($cycle.ReviewRunId)'."
    }
    return Assert-PlanReviewResultReceipt -PlanDir $PlanDir -ReviewRunId $ReviewRunId -Commit $Commit `
        -RequireBranchScope:($Stage -ceq 'plan-finalization') -RepoRoot $RepoRoot
}

function Resolve-PlanEvidenceAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PlanMetadata,
        [Parameter(Mandatory)]
        [ValidateSet('Evidence', 'EvidenceWaivers')]
        [string]$Kind
    )

    $repoRoot = [System.IO.Path]::GetFullPath($PlanMetadata.RepoRoot)
    $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'docs/implementation-plans'))
    $plansPrefix = $plansRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $planDir = [System.IO.Path]::GetFullPath($PlanMetadata.PlanDir)
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($planDir.StartsWith($plansPrefix, $comparison)) {
        return Resolve-PlanAssetPath -PlanDir $planDir -Kind $Kind -RepoRoot $repoRoot
    }

    # Unit fixtures may exercise the pure parser outside the repository inventory.
    return Resolve-PlanAssetPath -PlanDir $planDir -Kind $Kind
}

function Get-PlanEvidenceWaiver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PlanMetadata,
        [Parameter(Mandatory)][string]$PlanDirectory
    )

    if (-not [string]::Equals(
            [System.IO.Path]::GetFullPath($PlanMetadata.PlanDir),
            [System.IO.Path]::GetFullPath($PlanDirectory),
            $(if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal })
        )) {
        throw "Evidence waiver plan directory '$PlanDirectory' does not match the parsed plan."
    }
    $path = Resolve-PlanEvidenceAssetPath -PlanMetadata $PlanMetadata -Kind EvidenceWaivers
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    if ((Get-Item -LiteralPath $path -Force).Length -gt 65536) {
        throw "Evidence waiver file '$path' exceeds 65536 bytes."
    }

    try {
        $policy = Get-Content -LiteralPath $path -Raw -Force | ConvertFrom-Json -Depth 20
    }
    catch {
        throw "Evidence waiver file '$path' is malformed JSON: $($_.Exception.Message)"
    }

    $topProperties = @($policy.PSObject.Properties.Name | Sort-Object)
    if (($topProperties -join ',') -cne 'schema,waivers' -or
        [string]$policy.schema -cne 'skalary/evidence-waivers@1' -or
        $null -eq $policy.waivers) {
        throw "Evidence waiver file '$path' must contain only schema 'skalary/evidence-waivers@1' and a waivers array."
    }

    $header = Get-PlanHeaderMarkers -Content $PlanMetadata.Content
    $planId = [string]$header.All['plan-id']
    if ([string]::IsNullOrWhiteSpace($planId) -and
        $PlanMetadata.Content -match '(?m)^#\s+(?<id>\d{3}|[0-9a-f]{6}):') {
        $planId = $Matches.id
    }
    if ([string]::IsNullOrWhiteSpace($planId)) {
        throw 'Evidence waiver validation could not resolve the canonical plan id.'
    }
    $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $waivers = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($policy.waivers)) {
        $properties = @($entry.PSObject.Properties.Name | Sort-Object)
        $required = @('marker', 'outcome', 'plan', 'reason', 'requirement')
        $allowed = @($required + 'platform' | Sort-Object)
        if (@($required | Where-Object { $_ -cnotin $properties }).Count -gt 0 -or
            @($properties | Where-Object { $_ -cnotin $allowed }).Count -gt 0) {
            throw "Evidence waiver file '$path' contains an entry with missing or unknown fields."
        }

        $entryPlan = [string]$entry.plan
        $requirement = [string]$entry.requirement
        $marker = [string]$entry.marker
        $outcome = [string]$entry.outcome
        $reason = [string]$entry.reason
        $entryPlatform = if ($properties -contains 'platform') { [string]$entry.platform } else { $null }
        if ($entryPlan -cne $planId) {
            throw "Evidence waiver targets plan '$entryPlan', expected '$planId'."
        }
        if ($requirement -notmatch '^REQ-\d+$' -or
            @($PlanMetadata.Requirements.Keys | Where-Object { [string]$_ -ceq $requirement }).Count -ne 1) {
            throw "Evidence waiver targets unknown requirement '$requirement'."
        }
        $declaredMarkers = @(
            Get-TypedEvidenceMarkers -AcceptanceCriteria $PlanMetadata.Requirements[$requirement].AcceptanceCriteria |
                ForEach-Object { $_ }
        )
        if ([string]::IsNullOrWhiteSpace($marker) -or $marker.Contains('*') -or $declaredMarkers -cnotcontains $marker) {
            throw "Evidence waiver targets undeclared or wildcard marker '$marker' for '$requirement' (declared: $($declaredMarkers -join ', '))."
        }
        if ($outcome -cnotin @('skipped', 'degraded')) {
            throw "Evidence waiver for '$marker' may target only skipped or degraded, not '$outcome'."
        }
        if ([string]::IsNullOrWhiteSpace($reason) -or $reason.Length -gt 500 -or
            $reason -match "[`r`n\x00-\x1f]" -or $reason.Contains(" $([char]0x2014) ")) {
            throw "Evidence waiver for '$marker' has an invalid reason."
        }
        if ($entryPlatform -and $entryPlatform -cnotin @('Windows', 'Linux', 'MacOS')) {
            throw "Evidence waiver for '$marker' has invalid platform '$entryPlatform'."
        }

        $key = "$requirement|$marker|$outcome|$entryPlatform"
        if (-not $seen.Add($key)) {
            throw "Evidence waiver file '$path' contains duplicate binding '$key'."
        }
        $waivers.Add([pscustomobject]@{
                Requirement = $requirement
                Marker = $marker
                Outcome = $outcome
                Reason = $reason.Trim()
                Platform = $entryPlatform
                Applies = (-not $entryPlatform -or $entryPlatform -ceq $platform)
            })
    }

    return $waivers.ToArray()
}

function Read-PlanEvidenceReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Evidence receipt is missing: '$Path'."
    }
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 262144) {
        throw "Evidence receipt '$Path' exceeds 262144 bytes."
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $Path -Force)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^Phase \d+ Crosscheck:$') {
            continue
        }
        if ($line -notmatch '^(?<glyph>[✓✗⊘]) (?<req>REQ-\d+) — (?<marker>.+?) — (?<status>passed|failed|skipped|unrun|stale|degraded|waived)(?:: (?<note>.*))? — (?<commit>[0-9a-fA-F]{7,40})$') {
            throw "Malformed evidence receipt line $lineNumber in '$Path'."
        }

        $status = $Matches.status
        $expectedGlyph = if ($status -eq 'passed') { '✓' } elseif ($status -eq 'waived') { '⊘' } else { '✗' }
        if ($Matches.glyph -ne $expectedGlyph) {
            throw "Evidence receipt line $lineNumber uses glyph '$($Matches.glyph)' for status '$status'."
        }
        $entries.Add([pscustomobject]@{
                Req = $Matches.req
                Marker = $Matches.marker
                Status = $status
                Note = if ($Matches.ContainsKey('note')) { $Matches.note } else { '' }
                Commit = $Matches.commit.ToLowerInvariant()
                LineNumber = $lineNumber
            })
    }

    return $entries.ToArray()
}

function Resolve-PlanEvidencePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Evidence path is empty.'
    }

    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        throw "Evidence path '$RelativePath' must be relative."
    }

    if ($RelativePath -match '^[A-Za-z]:') {
        throw "Evidence path '$RelativePath' cannot be absolute."
    }

    if ($RelativePath -match '\\\\') {
        throw "Evidence path '$RelativePath' cannot be UNC."
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $repoRootFullPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFullPath ($RelativePath -replace '/', $separator)))
    $repoRootPrefix = $repoRootFullPath.TrimEnd($separator) + $separator
    if (-not $candidatePath.StartsWith($repoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Evidence path '$RelativePath' resolves outside repository root."
    }

    if (Test-Path -LiteralPath $candidatePath) {
        $resolved = (Resolve-Path -LiteralPath $candidatePath -Force).Path
        if (-not $resolved.StartsWith($repoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Evidence path '$RelativePath' escapes repository root via symlink."
        }
        return $resolved
    }

    return $candidatePath
}

function Parse-PlanFileEvidenceMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Marker
    )

    if ($Marker -notmatch '^file:(?<path>[^#]+)#(?<assertion>.+)$') {
        throw "Invalid file evidence marker '$Marker'. Expected file:<path>#<assertion>."
    }

    $relativePath = $Matches.path.Trim()
    $assertion = $Matches.assertion.Trim()
    if ($assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'exists'
            Threshold = $null
            Regex = $null
        }
    }

    if ($assertion -like 'contains:*') {
        $pattern = $assertion.Substring('contains:'.Length)
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid contains assertion in '$Marker'."
        }
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'contains'
            Threshold = $null
            Regex = $pattern
        }
    }

    if ($assertion -match '^count>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'count'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    if ($assertion -match '^dircount>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'dircount'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    throw "Invalid file evidence assertion '$assertion' in '$Marker'. Allowed: exists, contains:, count>=N, dircount>=N."
}

function Get-PathWithinRootPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    return [System.IO.Path]::GetFullPath($Root).TrimEnd($separator) + $separator
}

function Get-FileRegexMatchCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [int]$PerMatchTimeoutMs = 100,

        [int]$PerFileBudgetMs = 750
    )

    $content = Get-Content -LiteralPath $Path -Raw -Force
    $remaining = [TimeSpan]::FromMilliseconds($PerFileBudgetMs)
    $start = [DateTimeOffset]::UtcNow
    $matchCount = 0
    $offset = 0
    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::None,
        [TimeSpan]::FromMilliseconds($PerMatchTimeoutMs)
    )
    while ($offset -le $content.Length) {
        if ($remaining.TotalMilliseconds -le 0) {
            throw "Regex budget exhausted while scanning '$Path'."
        }

        $match = $regex.Match($content, $offset)
        if (-not $match.Success) {
            break
        }

        $matchCount++
        $offset = if ($match.Length -gt 0) { $match.Index + $match.Length } else { $match.Index + 1 }
        $elapsed = [DateTimeOffset]::UtcNow - $start
        $remaining = [TimeSpan]::FromMilliseconds($PerFileBudgetMs) - $elapsed
    }

    return $matchCount
}

function Invoke-PlanFileEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Marker,

        [ValidateSet('Draft', 'PhaseCrosscheck', 'PlanCrosscheck')]
        [string]$Stage = 'Draft',

        [long]$MaxFileBytes = 1048576,

        [int]$PerMatchTimeoutMs = 100,

        [int]$PerFileRegexBudgetMs = 750
    )

    $parsed = Parse-PlanFileEvidenceMarker -Marker $Marker
    $resolvedPath = Resolve-PlanEvidencePath -RepoRoot $RepoRoot -RelativePath $parsed.RelativePath
    $isBlockingStage = $Stage -ne 'Draft'
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'failed'
            Success = $false
            Blocking = $isBlockingStage
            Message = "Missing target '$($parsed.RelativePath)'."
        }
    }

    if ($parsed.Assertion -eq 'dircount') {
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
            return [pscustomobject]@{
                Marker = $Marker
                Status = 'failed'
                Success = $false
                Blocking = $isBlockingStage
                Message = "Target '$($parsed.RelativePath)' is not a directory."
            }
        }

        $rootPrefix = Get-PathWithinRootPrefix -Root $RepoRoot
        $seenDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($resolvedPath)
        $count = 0
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $items = Get-ChildItem -LiteralPath $current -Force
            foreach ($item in $items) {
                if ($item.LinkType) {
                    continue
                }

                if ($item.PSIsContainer) {
                    $childPath = [System.IO.Path]::GetFullPath($item.FullName)
                    if (-not $childPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Directory walk escaped repository root through '$childPath'."
                    }
                    if ($seenDirectories.Add($childPath)) {
                        $queue.Enqueue($childPath)
                        $count++
                    }
                    continue
                }

                $count++
            }
        }

        return [pscustomobject]@{
            Marker = $Marker
            Status = if ($count -ge $parsed.Threshold) { 'passed' } else { 'failed' }
            Success = $count -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "Counted $count item(s), required >= $($parsed.Threshold)."
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'failed'
            Success = $false
            Blocking = $isBlockingStage
            Message = "Target '$($parsed.RelativePath)' is not a file."
        }
    }

    $length = (Get-Item -LiteralPath $resolvedPath -Force).Length
    if ($length -gt $MaxFileBytes) {
        throw "File '$($parsed.RelativePath)' exceeds max size (${MaxFileBytes} bytes)."
    }

    if ($parsed.Assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'passed'
            Success = $true
            Blocking = $isBlockingStage
            Message = "File '$($parsed.RelativePath)' exists."
        }
    }

    if ($parsed.Assertion -eq 'count') {
        $lineCount = @((Get-Content -LiteralPath $resolvedPath -Force)).Count
        return [pscustomobject]@{
            Marker = $Marker
            Status = if ($lineCount -ge $parsed.Threshold) { 'passed' } else { 'failed' }
            Success = $lineCount -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "File has $lineCount line(s), required >= $($parsed.Threshold)."
        }
    }

    $matchCount = Get-FileRegexMatchCount -Path $resolvedPath -Pattern $parsed.Regex -PerMatchTimeoutMs $PerMatchTimeoutMs -PerFileBudgetMs $PerFileRegexBudgetMs
    return [pscustomobject]@{
        Marker = $Marker
        Status = if ($matchCount -gt 0) { 'passed' } else { 'failed' }
        Success = $matchCount -gt 0
        Blocking = $isBlockingStage
        Message = if ($matchCount -gt 0) { 'Regex matched.' } else { 'Regex did not match.' }
    }
}

Export-ModuleMember -Function ConvertTo-PlanEvidenceResult, Resolve-PlanEvidenceAssetPath, Get-PlanEvidenceWaiver, Read-PlanEvidenceReceipt, Parse-PlanFileEvidenceMarker, Invoke-PlanFileEvidence, Get-PlanReviewCycleState, Assert-ReviewResultReceipt, Assert-PlanReviewResultReceipt, Assert-PlanCleanReviewEvidence
