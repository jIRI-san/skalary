#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('CrLog', 'Learnings', 'Capture')]
    [string]$Kind,

    [Parameter(Mandatory)]
    [string]$PlanDir,

    [Parameter(Mandatory)]
    [ValidateRange(1, 999)]
    [int]$Phase,

    [string]$Step,

    [string]$Message,

    [ValidateSet('Critical', 'High', 'Med', 'Low')]
    [string]$Sev,

    [ValidateSet('code-review', 'discovery', 'note')]
    [string]$Src,

    [ValidateSet('rework>1', 'plan-contradiction', 'reusable-pattern')]
    [string]$Trigger,

    [ValidateSet(
        'security',
        'correctness-reliability',
        'architecture-patterns',
        'performance',
        'testing-evidence',
        'maintainability-consistency',
        'operability-observability'
    )]
    [string]$Concern,

    [ValidatePattern('^REQ-[1-9][0-9]*$')]
    [string[]]$Requirement = @(),

    [ValidateSet('cr', 'dr', 'none')]
    [string]$ReviewType = 'none',

    [ValidateRange(1, 100)]
    [int]$MaxLearnings = 10,

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$placeholder = 'No entries for this phase.'
$overflowSchema = 'workflow-learning-overflow/v1'

function Get-NoteConfig {
    param([string]$Kind)

    switch ($Kind) {
        'CrLog' { return [pscustomobject]@{ Header = '## CR Capture' } }
        'Learnings' { return [pscustomobject]@{ Header = '## Learnings Capture' } }
        'Capture' { return [pscustomobject]@{ Header = '## Capture' } }
    }
}

function ConvertTo-SafeNoteBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $clean = [regex]::Replace($Text, '[\u0000-\u001F\u007F\u0085\u2028\u2029]+', ' ')
    $clean = $clean.Replace('[', '(').Replace(']', ')')
    $clean = $clean.Replace('`', "'").Replace('|', '/')
    $clean = $clean.Replace([char]0x00B7, '-')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw 'Workflow-note body is empty after sanitization.'
    }
    return $clean
}

function Get-StepToken {
    param([string]$Step)

    if ([string]::IsNullOrWhiteSpace($Step)) { return '-' }
    $token = $Step.Trim()
    if ($token -notmatch '^[0-9]+\.[0-9]+[a-z]?$') {
        throw "Step '$Step' must look like '<phase>.<step>' (e.g. 1.4 or 2.3a)."
    }
    return $token
}

function Get-SortedRequirement {
    [CmdletBinding()]
    param([string[]]$Value)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        [void]$set.Add($item)
    }
    $sorted = [string[]]@($set)
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return , $sorted
}

function Get-DomainSeparatedId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string[]]$Field
    )

    $framed = $Domain + [char]0 + ($Field -join [char]0)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($framed)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function Format-NoteEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][int]$Phase,
        [string]$Step,
        [string]$Sev,
        [string]$Src,
        [string]$Trigger,
        [Parameter(Mandatory)][string]$Concern,
        [string[]]$Requirement,
        [Parameter(Mandatory)][string]$ReviewType,
        [Parameter(Mandatory)][string]$Body
    )

    $stepToken = Get-StepToken -Step $Step
    $safeBody = ConvertTo-SafeNoteBody -Text $Body
    $requirements = Get-SortedRequirement -Value $Requirement
    $requirementToken = if ($requirements.Count -gt 0) { $requirements -join ',' } else { '-' }
    $effectiveSrc = if ($Kind -eq 'CrLog' -and -not $Src) { 'code-review' } else { $Src }

    if ($Kind -eq 'CrLog' -and -not $Sev) {
        throw 'CrLog notes require -Sev.'
    }
    if ($Kind -eq 'CrLog' -and $ReviewType -eq 'none') {
        throw 'CrLog notes require -ReviewType cr or dr.'
    }
    if ($Kind -eq 'Learnings' -and -not $Trigger) {
        throw 'Learnings notes require -Trigger.'
    }

    $sourceRecordId = Get-DomainSeparatedId -Domain "workflow-note/$($Kind.ToLowerInvariant())/source-record/v1" -Field @(
        $PlanId,
        [string]$Phase,
        $stepToken,
        $Concern,
        $requirementToken,
        $ReviewType,
        $(if ($effectiveSrc) { $effectiveSrc } else { '-' }),
        $(if ($Sev) { $Sev } else { '-' }),
        $(if ($Trigger) { $Trigger } else { '-' }),
        $safeBody
    )
    $provenance = " [concern:$Concern] [req:$requirementToken] [review:$ReviewType] [source-record:$sourceRecordId]"

    $line = switch ($Kind) {
        'CrLog' { "- [$stepToken] [src:$effectiveSrc] [sev:$Sev]$provenance $safeBody" }
        'Learnings' { "- [$stepToken] [trigger:$Trigger]$provenance $safeBody" }
        'Capture' {
            $tokens = ''
            if ($effectiveSrc) { $tokens += " [src:$effectiveSrc]" }
            if ($Sev) { $tokens += " [sev:$Sev]" }
            "- [$stepToken]$tokens$provenance $safeBody"
        }
    }

    return [pscustomobject]@{
        Line = $line
        SourceRecordId = $sourceRecordId
        Requirements = $requirements
    }
}

function Find-SectionRange {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Header,
        [int]$Phase
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $Header -and
            ($i + 1) -lt $Lines.Count -and
            $Lines[$i + 1] -match "^\s*Phase:\s*$Phase\s*$") {
            $end = $Lines.Count
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -match '^##\s') { $end = $j; break }
            }
            return [pscustomobject]@{ Start = $i; End = $end }
        }
    }
    return $null
}

function Repair-EmptyLearningsSections {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Header,
        [string]$Placeholder
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ne $Header) { continue }
        $end = $Lines.Count
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            if ($Lines[$j] -match '^##\s') { $end = $j; break }
        }
        $hasEntry = $false
        for ($k = $i + 1; $k -lt $end; $k++) {
            if ($Lines[$k] -match '^\s*-\s') { $hasEntry = $true; break }
        }
        if (-not $hasEntry) {
            $Lines.Insert([Math]::Min($i + 2, $end), $Placeholder)
        }
    }
}

function New-OverflowBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$Record
    )

    $recordBytes = ($Record -join "`n") + "`n"
    $digest = Get-DomainSeparatedId -Domain $overflowSchema -Field @($PlanId, $recordBytes)
    $content = @(
        '# Learning Overflow Batch'
        "Schema: $overflowSchema"
        "Plan: $PlanId"
        "Digest: $digest"
        "Count: $($Record.Count)"
        ''
        $Record
    ) -join "`n"

    return [pscustomobject]@{
        Digest = $digest
        Content = $content.TrimEnd("`n") + "`n"
        Count = $Record.Count
    }
}

function Write-OverflowBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][psobject]$Batch
    )

    $path = Join-Path $Root "$($Batch.Digest).md"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = [System.IO.File]::ReadAllText($path)
        if (-not [string]::Equals($existing, $Batch.Content, [System.StringComparison]::Ordinal)) {
            throw "Learning overflow digest collision at '$path'."
        }
        return $path
    }

    $write = Set-AtomicStoreContent -Path $path -Content $Batch.Content -ExpectedGeneration 'absent'
    if ($write.Status -ne 'complete') {
        throw "Add-WorkflowNote overflow write failed with status '$($write.Status)'."
    }
    return $path
}

function Test-SourceRecordExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$ActiveLines,
        [Parameter(Mandatory)][string]$OverflowRoot,
        [Parameter(Mandatory)][string]$SourceRecordId
    )

    $token = "[source-record:$SourceRecordId]"
    foreach ($line in $ActiveLines) {
        if ($line.IndexOf($token, [System.StringComparison]::Ordinal) -ge 0) {
            return $true
        }
    }
    if (Test-Path -LiteralPath $OverflowRoot -PathType Container) {
        foreach ($batch in @(Get-ChildItem -LiteralPath $OverflowRoot -File)) {
            $content = [System.IO.File]::ReadAllText($batch.FullName)
            if ($content.Contains($token, [System.StringComparison]::Ordinal)) {
                return $true
            }
        }
    }
    return $false
}

$planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $cursor = [System.IO.DirectoryInfo]::new($planDirFull)
    while ($null -ne $cursor.Parent) {
        if ($cursor.Parent.Name -eq 'implementation-plans' -and
            $null -ne $cursor.Parent.Parent -and
            $cursor.Parent.Parent.Name -eq 'docs') {
            $RepoRoot = $cursor.Parent.Parent.Parent.FullName
            break
        }
        $cursor = $cursor.Parent
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw "Cannot derive repository root from plan folder '$planDirFull'; pass -RepoRoot."
    }
}
$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$inventory = @(Get-PlanInventory -RepoRoot $repoRootFull)
$planRecord = @($inventory | Where-Object {
        $_.Path -and [string]::Equals(
            [System.IO.Path]::GetFullPath([string]$_.Path),
            $planDirFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    })
if ($planRecord.Count -ne 1) {
    throw "Plan folder '$planDirFull' is not a unique member of the repository plan inventory."
}

$planId = [string]$planRecord[0].Id
$config = Get-NoteConfig -Kind $Kind
$filePath = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind $Kind `
    -RepoRoot $repoRootFull -Inventory $inventory
$overflowRoot = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind LearningOverflowRoot `
    -RepoRoot $repoRootFull -Inventory $inventory

$requirements = Get-SortedRequirement -Value $Requirement
if ($requirements.Count -gt 0) {
    $metadata = Get-PlanMetadata -Path (Join-Path $planDirFull 'plan.md') -RepoRoot $repoRootFull
    $knownRequirements = @($metadata.Requirements.Values | ForEach-Object { [string]$_.Id })
    foreach ($requirementId in $requirements) {
        if ($knownRequirements -notcontains $requirementId) {
            throw "Requirement '$requirementId' does not belong to plan '$planId'."
        }
    }
}
if ($Message -and -not $Concern) {
    throw 'Workflow-note entries require -Concern.'
}

$formattedEntry = if ($Message) {
    Format-NoteEntry -Kind $Kind -PlanId $planId -Phase $Phase -Step $Step -Sev $Sev -Src $Src `
        -Trigger $Trigger -Concern $Concern -Requirement $requirements -ReviewType $ReviewType -Body $Message
}
else {
    $null
}

$result = Invoke-WithAtomicStoreLock -Scope $planDirFull -Action {
    $fileGeneration = Get-AtomicStoreGeneration -Path $filePath
    $raw = if (Test-Path -LiteralPath $filePath -PathType Leaf) {
        [System.IO.File]::ReadAllText($filePath)
    }
    else {
        ''
    }
    $normalized = $raw -replace "`r`n", "`n"
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($normalized.Length -gt 0) {
        $lines.AddRange([string[]]($normalized.TrimEnd("`n").Split("`n")))
    }
    $legacySummaryCount = @($lines | Where-Object {
            $_ -match '^\s*-\s.*\[trigger:overflow-summary\]'
        }).Count

    if ($formattedEntry -and
        (Test-SourceRecordExists -ActiveLines ([string[]]$lines.ToArray()) -OverflowRoot $overflowRoot `
            -SourceRecordId $formattedEntry.SourceRecordId)) {
        return [pscustomobject]@{
            Kind = $Kind
            File = $filePath
            Phase = $Phase
            Appended = $false
            SourceRecordId = $formattedEntry.SourceRecordId
            OverflowFile = $null
            OverflowCount = 0
            Status = if ($legacySummaryCount -gt 0) { 'legacy-loss' } else { 'complete' }
            LegacyLossCount = $legacySummaryCount
            Note = 'source record already durable'
        }
    }

    $range = Find-SectionRange -Lines $lines -Header $config.Header -Phase $Phase
    if (-not $range) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add($config.Header)
        $lines.Add("Phase: $Phase")
        $lines.Add('')
        $lines.Add($(if ($formattedEntry) { $formattedEntry.Line } else { $placeholder }))
    }
    elseif ($formattedEntry) {
        $placeholderIndex = -1
        $lastEntryIndex = -1
        for ($i = $range.Start; $i -lt $range.End; $i++) {
            if ($lines[$i].Trim() -eq $placeholder) { $placeholderIndex = $i }
            if ($lines[$i] -match '^\s*-\s') { $lastEntryIndex = $i }
        }
        if ($placeholderIndex -ge 0) {
            $lines[$placeholderIndex] = $formattedEntry.Line
        }
        elseif ($lastEntryIndex -ge 0) {
            $lines.Insert($lastEntryIndex + 1, $formattedEntry.Line)
        }
        else {
            $lines.Insert($range.End, $formattedEntry.Line)
        }
    }

    $overflowPath = $null
    $overflowCount = 0
    if ($Kind -eq 'Learnings' -and $formattedEntry) {
        $entryIndexes = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*-\s\[' -and
                $lines[$i] -notmatch '\[trigger:overflow-summary\]') {
                $entryIndexes.Add($i)
            }
        }
        $activeLegacyCount = $legacySummaryCount
        $overflowCount = [Math]::Max(0, ($entryIndexes.Count + $activeLegacyCount) - $MaxLearnings)
        if ($overflowCount -gt 0) {
            $overflowIndexes = @($entryIndexes | Select-Object -First $overflowCount)
            $overflowRecords = [string[]]@($overflowIndexes | ForEach-Object { $lines[$_] })
            $batch = New-OverflowBatch -PlanId $planId -Record $overflowRecords

            # Overflow is durable before the compact active log changes. A crash can leave an
            # idempotent orphan batch, but it cannot erase the learning that was being compacted.
            $overflowPath = Write-OverflowBatch -Root $overflowRoot -Batch $batch
            foreach ($index in @($overflowIndexes | Sort-Object -Descending)) {
                $lines.RemoveAt($index)
            }
            Repair-EmptyLearningsSections -Lines $lines -Header $config.Header -Placeholder $placeholder
        }
    }

    $content = ($lines -join "`n").TrimEnd("`n") + "`n"
    $write = Set-AtomicStoreContent -Path $filePath -Content $content -ExpectedGeneration $fileGeneration
    if ($write.Status -ne 'complete') {
        throw "Add-WorkflowNote active-log write failed with status '$($write.Status)'."
    }

    return [pscustomobject]@{
        Kind = $Kind
        File = $filePath
        Phase = $Phase
        Appended = [bool]$Message
        SourceRecordId = if ($formattedEntry) { $formattedEntry.SourceRecordId } else { $null }
        OverflowFile = $overflowPath
        OverflowCount = $overflowCount
        Status = if ($legacySummaryCount -gt 0) { 'legacy-loss' } else { 'complete' }
        LegacyLossCount = $legacySummaryCount
    }
}

return $result
