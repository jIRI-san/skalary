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

    [ValidateRange(1, 30)]
    [int]$LockTimeoutSeconds = 30,

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$placeholder = 'No entries for this phase.'
$overflowSchema = 'workflow-learning-overflow/v1'
$maxRecordBytes = 16KB
$maxBatchRecords = 64
$maxBatchBytes = 512KB
$maxActiveBatches = 64
$maxOverflowBytes = 32MB
$maxActiveLogBytes = 4MB
$atomicStatus = Get-AtomicStoreStatus

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
        Record = $Record
    }
}

function Write-OverflowBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][psobject]$Batch
    )

    foreach ($record in @($Batch.Record)) {
        if ([System.Text.Encoding]::UTF8.GetByteCount($record) -gt $maxRecordBytes) {
            throw 'capacity-blocked: learning overflow record exceeds 16 KiB.'
        }
    }
    if ($Batch.Count -gt $maxBatchRecords -or
        [System.Text.Encoding]::UTF8.GetByteCount($Batch.Content) -gt $maxBatchBytes) {
        throw 'capacity-blocked: learning overflow batch exceeds its record or byte ceiling.'
    }

    $path = Join-Path $Root "$($Batch.Digest).md"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = [System.IO.File]::ReadAllText($path)
        if (-not [string]::Equals($existing, $Batch.Content, [System.StringComparison]::Ordinal)) {
            throw "Learning overflow digest collision at '$path'."
        }
        return $path
    }

    $existing = @(if (Test-Path -LiteralPath $Root -PathType Container) {
            Get-ChildItem -LiteralPath $Root -File -Filter '*.md'
        })
    $existingBytes = [long]0
    foreach ($file in $existing) { $existingBytes += $file.Length }
    $batchBytes = [System.Text.Encoding]::UTF8.GetByteCount($Batch.Content)
    if ($existing.Count -ge $maxActiveBatches -or ($existingBytes + $batchBytes) -gt $maxOverflowBytes) {
        throw 'capacity-blocked: learning overflow active-set ceiling reached.'
    }

    $write = Set-AtomicStoreContent -Path $path -Content $Batch.Content -ExpectedGeneration 'absent'
    if ($write.Status -ne 'complete') {
        throw "Add-WorkflowNote overflow write failed with status '$($write.Status)'."
    }
    return $path
}

function Read-OverflowBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$PlanId
    )

    $content = [System.IO.File]::ReadAllText($File.FullName)
    $lines = $content.TrimEnd("`r", "`n") -split "`r?`n"
    if ($lines.Count -lt 7 -or $lines[0] -ne '# Learning Overflow Batch' -or
        $lines[1] -ne "Schema: $overflowSchema" -or $lines[2] -ne "Plan: $PlanId" -or
        $lines[3] -notmatch '^Digest: [0-9a-f]{64}$' -or
        $lines[4] -notmatch '^Count: \d+$' -or $lines[5] -ne '') {
        throw "invalid: malformed learning overflow batch '$($File.FullName)'."
    }
    $digest = $lines[3].Substring('Digest: '.Length)
    $count = [int]($lines[4].Substring('Count: '.Length))
    $records = [string[]]@($lines[6..($lines.Count - 1)])
    if ($records.Count -ne $count -or $File.BaseName -ne $digest) {
        throw "invalid: learning overflow count or filename mismatch in '$($File.FullName)'."
    }
    $expected = New-OverflowBatch -PlanId $PlanId -Record $records
    if ($expected.Digest -ne $digest -or
        -not [string]::Equals($expected.Content, $content, [System.StringComparison]::Ordinal)) {
        throw "invalid: learning overflow digest mismatch in '$($File.FullName)'."
    }
    foreach ($record in $records) {
        if ([System.Text.Encoding]::UTF8.GetByteCount($record) -gt $maxRecordBytes) {
            throw "invalid: oversized learning overflow record in '$($File.FullName)'."
        }
    }
    return [pscustomobject]@{ Content = $content; Records = $records; Digest = $digest }
}

function Remove-StaleAtomicTemp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Root)

    $cutoff = [DateTime]::UtcNow.AddSeconds(-30)
    foreach ($directory in @($Root | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($temp in @(Get-ChildItem -LiteralPath $directory -Force -File -Filter '.atomic-*.tmp')) {
            if ($temp.LastWriteTimeUtc -le $cutoff) {
                Remove-Item -LiteralPath $temp.FullName -Force
            }
        }
    }
}

function Get-SourceRecordIdFromLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)

    if ($Line -match '\[source-record:(?<id>[0-9a-f]{64})\]') {
        return $Matches.id
    }
    return $null
}

function Get-OverflowSnapshot {
    [CmdletBinding()]
    param(    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$PlanId)

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $legacyLoss = 0
    $files = if (Test-Path -LiteralPath $Root -PathType Container) {
        @(Get-ChildItem -LiteralPath $Root -File -Filter '*.md' | Sort-Object Name)
    }
    else {
        @()
    }
    foreach ($file in $files) {
        $batch = Read-OverflowBatch -File $file -PlanId $PlanId
        $content = $batch.Content
        foreach ($match in [regex]::Matches($content, '\[source-record:(?<id>[0-9a-f]{64})\]')) {
            [void]$ids.Add($match.Groups['id'].Value)
        }
        $legacyLoss += [regex]::Matches($content, '\[trigger:overflow-summary\]').Count
    }
    return [pscustomobject]@{ Files = $files; SourceIds = $ids; LegacyLossCount = $legacyLoss }
}

function Assert-OverflowCapacity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Batch
    )

    $files = @(if (Test-Path -LiteralPath $Root -PathType Container) {
            Get-ChildItem -LiteralPath $Root -File -Filter '*.md'
        })
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $totalBytes = [long]0
    foreach ($file in $files) {
        [void]$names.Add($file.BaseName)
        $totalBytes += $file.Length
    }
    $count = $files.Count
    foreach ($candidate in $Batch) {
        if ($candidate.Count -gt $maxBatchRecords -or
            [System.Text.Encoding]::UTF8.GetByteCount($candidate.Content) -gt $maxBatchBytes) {
            throw 'capacity-blocked: learning overflow batch exceeds its record or byte ceiling.'
        }
        foreach ($record in @($candidate.Record)) {
            if ([System.Text.Encoding]::UTF8.GetByteCount($record) -gt $maxRecordBytes) {
                throw 'capacity-blocked: learning overflow record exceeds 16 KiB.'
            }
        }
        if ($names.Add($candidate.Digest)) {
            $count++
            $totalBytes += [System.Text.Encoding]::UTF8.GetByteCount($candidate.Content)
        }
    }
    if ($count -gt $maxActiveBatches -or $totalBytes -gt $maxOverflowBytes) {
        throw 'capacity-blocked: learning overflow active-set ceiling reached.'
    }
}

function Stop-CapacityBlocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Reason
    )

    Write-Output ([pscustomobject]@{
            Kind = $Kind
            File = $Path
            Phase = $Phase
            Appended = $false
            Status = $atomicStatus.CapacityBlocked
            Note = $Reason
        })
    exit 4
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
if ($formattedEntry -and
    [System.Text.Encoding]::UTF8.GetByteCount($formattedEntry.Line) -gt $maxRecordBytes) {
    Stop-CapacityBlocked -Path $filePath -Reason 'workflow-note record exceeds 16 KiB'
}

$result = try {
    Invoke-WithAtomicStoreLock -Scope $planDirFull -TimeoutSeconds $LockTimeoutSeconds -Action {
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

        $overflowSnapshot = Get-OverflowSnapshot -Root $overflowRoot -PlanId $planId
        $pendingBatches = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $removeIndexes = [System.Collections.Generic.List[int]]::new()
        $legacyRecords = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*-\s.*\[trigger:overflow-summary\]') {
                $legacyRecords.Add($lines[$i])
                $removeIndexes.Add($i)
                continue
            }
            $sourceId = Get-SourceRecordIdFromLine -Line $lines[$i]
            if ($sourceId -and
                ($overflowSnapshot.SourceIds.Contains($sourceId) -or -not $seen.Add($sourceId))) {
                $removeIndexes.Add($i)
            }
        }

        $overflowPath = $null
        $overflowCount = 0
        if ($legacyRecords.Count -gt 0) {
            $legacyBatch = New-OverflowBatch -PlanId $planId -Record ([string[]]$legacyRecords.ToArray())
            $pendingBatches.Add($legacyBatch)
            $overflowCount += $legacyRecords.Count
        }
        foreach ($index in @($removeIndexes | Sort-Object -Descending)) {
            $lines.RemoveAt($index)
        }
        if ($removeIndexes.Count -gt 0) {
            Repair-EmptyLearningsSections -Lines $lines -Header $config.Header -Placeholder $placeholder
        }

        $alreadyDurable = $formattedEntry -and (
            $overflowSnapshot.SourceIds.Contains($formattedEntry.SourceRecordId) -or
            $seen.Contains($formattedEntry.SourceRecordId)
        )
        $range = Find-SectionRange -Lines $lines -Header $config.Header -Phase $Phase
        if (-not $range) {
            if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
                $lines.Add('')
            }
            $lines.Add($config.Header)
            $lines.Add("Phase: $Phase")
            $lines.Add('')
            $lines.Add($(if ($formattedEntry -and -not $alreadyDurable) { $formattedEntry.Line } else { $placeholder }))
        }
        elseif ($formattedEntry -and -not $alreadyDurable) {
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

        if ($Kind -eq 'Learnings' -and $formattedEntry -and -not $alreadyDurable) {
            $entryIndexes = [System.Collections.Generic.List[int]]::new()
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*-\s\[') { $entryIndexes.Add($i) }
            }
            $moveCount = [Math]::Max(0, $entryIndexes.Count - $MaxLearnings)
            if ($moveCount -gt 0) {
                $overflowIndexes = @($entryIndexes | Select-Object -First $moveCount)
                $overflowRecords = [string[]]@($overflowIndexes | ForEach-Object { $lines[$_] })
                $batch = New-OverflowBatch -PlanId $planId -Record $overflowRecords
                $pendingBatches.Add($batch)
                $overflowCount += $moveCount
                foreach ($index in @($overflowIndexes | Sort-Object -Descending)) {
                    $lines.RemoveAt($index)
                }
                Repair-EmptyLearningsSections -Lines $lines -Header $config.Header -Placeholder $placeholder
            }
        }

        $content = ($lines -join "`n").TrimEnd("`n") + "`n"
        if ([System.Text.Encoding]::UTF8.GetByteCount($content) -gt $maxActiveLogBytes) {
            throw 'capacity-blocked: active workflow log exceeds 4 MiB.'
        }
        Assert-OverflowCapacity -Root $overflowRoot -Batch ([object[]]$pendingBatches.ToArray())
        foreach ($pendingBatch in $pendingBatches) {
            $overflowPath = Write-OverflowBatch -Root $overflowRoot -Batch $pendingBatch
        }
        if (-not [string]::Equals($content, $normalized, [System.StringComparison]::Ordinal)) {
            $write = Set-AtomicStoreContent -Path $filePath -Content $content -ExpectedGeneration $fileGeneration
            if ($write.Status -ne $atomicStatus.Complete) {
                throw "Add-WorkflowNote active-log write failed with status '$($write.Status)'."
            }
        }
        Remove-StaleAtomicTemp -Root @((Split-Path -Parent $filePath), $overflowRoot)

        $legacyLossCount = $overflowSnapshot.LegacyLossCount + $legacyRecords.Count
        return [pscustomobject]@{
            Kind = $Kind
            File = $filePath
            Phase = $Phase
            Appended = [bool]($formattedEntry -and -not $alreadyDurable)
            SourceRecordId = if ($formattedEntry) { $formattedEntry.SourceRecordId } else { $null }
            OverflowFile = $overflowPath
            OverflowCount = $overflowCount
            Status = if ($legacyLossCount -gt 0) { 'legacy-loss' } else { $atomicStatus.Complete }
            LegacyLossCount = $legacyLossCount
            Note = if ($alreadyDurable) { 'source record already durable' } else { '' }
        }
    }
}
catch [System.TimeoutException] {
    [pscustomobject]@{
        Kind = $Kind
        File = $filePath
        Phase = $Phase
        Appended = $false
        Status = $atomicStatus.LockTimeout
        Note = $_.Exception.Message
    }
}
catch {
    if ($_.Exception.Message.StartsWith('capacity-blocked:', [System.StringComparison]::Ordinal)) {
        Stop-CapacityBlocked -Path $filePath -Reason $_.Exception.Message
    }
    throw
}

return $result
