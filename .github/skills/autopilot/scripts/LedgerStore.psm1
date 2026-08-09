#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$script:LedgerCategories = @(
    'security',
    'performance',
    'error-handling',
    'consistency',
    'plan-structure',
    'testing',
    'observability'
)
$script:LedgerSources = @('cip', 'dr', 'cr', 'code-review', 'ci', 'autopilot')
$script:LedgerSeverities = @('Critical', 'High', 'Med', 'Low')
$script:MaxEntryLength = 220
$script:MaxTagLength = 40
$script:MaxTagCount = 12
$script:MaxRecords = 10000
$script:MaxCategoryBytes = 4MB
$script:MaxAttempts = 3

function Normalize-LedgerLesson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$MaxLength
    )

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()
    $normalized = [regex]::Replace($normalized, '\s*([,.:;!?])\s*', '$1 ')
    $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()
    if ($normalized.Length -gt $MaxLength) {
        $normalized = $normalized.Substring(0, $MaxLength).Trim()
    }
    return $normalized
}

function ConvertTo-SafeLedgerText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$MaxLength
    )

    $sanitized = [regex]::Replace($Text, '[\u000A-\u000D\u0085\u2028\u2029\u000B\u000C]', ' ')
    $sanitized = [regex]::Replace($sanitized, '[\u0000-\u001F\u007F]', ' ')
    $sanitized = [regex]::Replace($sanitized, '(?i)src\s*:', 'src-')
    $sanitized = [regex]::Replace($sanitized, '(?i)sev\s*:', 'sev-')
    $sanitized = [regex]::Replace($sanitized, '(?i)\[recurrence\s*:\s*\d+\]', ' recurrence- ')
    $sanitized = [regex]::Replace($sanitized, '[(),#\[\]|]', ' ')
    $sanitized = [regex]::Replace($sanitized, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        throw 'Entry text is empty after sanitization.'
    }
    if ($sanitized.Length -gt $MaxLength) {
        $sanitized = $sanitized.Substring(0, $MaxLength).Trim()
    }
    return $sanitized
}

function Resolve-LedgerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$CategorySlug
    )

    if ($script:LedgerCategories -notcontains $CategorySlug) {
        throw "Ledger category '$CategorySlug' is not in the closed category set."
    }
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $path = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot "docs/review-ledger/$CategorySlug.md"))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $resolvedRoot.TrimEnd($separator) + $separator
    if (-not $path.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved ledger path '$path' escapes repository root."
    }
    $physicalRoot = Resolve-PhysicalRepoPath -Path $resolvedRoot
    $physicalPath = Resolve-PhysicalRepoPath -Path $path
    $physicalPrefix = $physicalRoot.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $physicalPath.StartsWith($physicalPrefix, $pathComparison)) {
        throw "Resolved ledger path '$path' escapes repository root through a link or reparse point."
    }
    return $path
}

function Get-LedgerTagSet {
    [CmdletBinding()]
    param([string[]]$InputTags)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($tag in @($InputTags)) {
        if ($null -eq $tag) { continue }
        $sanitizedTag = ConvertTo-SafeLedgerText -Text ([string]$tag) -MaxLength $script:MaxTagLength
        if ($sanitizedTag -match '\s') {
            throw "Tag '$tag' is invalid after sanitization. Tags must not contain spaces."
        }
        [void]$set.Add('#' + $sanitizedTag.ToLowerInvariant())
    }

    $ordered = [string[]]@($set)
    [Array]::Sort($ordered, [System.StringComparer]::Ordinal)
    if ($ordered.Count -gt $script:MaxTagCount) {
        throw "Too many tags ($($ordered.Count)); max is $($script:MaxTagCount)."
    }
    return , $ordered
}

function ConvertTo-LedgerRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line,
        [Parameter(Mandatory)][string]$Category
    )

    $pattern = '^- \[(?<date>\d{4}-\d{2}-\d{2})\] (?<lesson>.+?) \(plan-(?<plan>[0-9a-f]{6}|\d{3}), src:(?<src>cip|dr|cr|code-review|ci|autopilot), sev:(?<severity>Critical|High|Med|Low)\)(?<tags>(?:\s+#\S+)*)$'
    if ($Line -notmatch $pattern) { return $null }

    $tagList = @()
    if (-not [string]::IsNullOrWhiteSpace($Matches.tags)) {
        $tagList = @($Matches.tags.Trim().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
        [Array]::Sort($tagList, [System.StringComparer]::Ordinal)
    }

    $lesson = [string]$Matches.lesson
    $lessonForKey = [regex]::Replace($lesson, '\s*\[recurrence:\d+\]\s*$', '').Trim()
    $normalizedLesson = Normalize-LedgerLesson -Text $lessonForKey -MaxLength $script:MaxEntryLength
    $sortedTags = if ($tagList.Count -eq 0) { '' } else { $tagList -join '|' }

    return [pscustomobject]@{
        Line = $Line
        Date = [string]$Matches.date
        Plan = [string]$Matches.plan
        Src = [string]$Matches.src
        Severity = [string]$Matches.severity
        Lesson = $lesson
        LessonForKey = $lessonForKey
        NormalizedLesson = $normalizedLesson
        Tags = $tagList
        SortedTags = $sortedTags
        IdempotenceKey = "$Category|$normalizedLesson|$($Matches.plan)|$($Matches.src)|$($Matches.severity)|$sortedTags"
        RecurrenceKey = "$Category|$normalizedLesson|$sortedTags"
    }
}

function Get-DeterministicLedgerOrder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records)

    return , @(
        $Records | Sort-Object `
            @{ Expression = { $_.NormalizedLesson } },
            @{ Expression = { $_.SortedTags } },
            @{ Expression = { $_.Plan } },
            @{ Expression = { $_.Src } },
            @{ Expression = { $_.Severity } },
            @{ Expression = { $_.Date } },
            @{ Expression = { $_.Line } }
    )
}

function Get-LedgerHeaderLines {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)

    $firstEntryIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($Lines[$i])) { continue }
        foreach ($category in $script:LedgerCategories) {
            if ($null -ne (ConvertTo-LedgerRecord -Line $Lines[$i] -Category $category)) {
                $firstEntryIndex = $i
                break
            }
        }
        if ($firstEntryIndex -ge 0) { break }
    }

    $candidate = if ($firstEntryIndex -eq 0) {
        @()
    }
    elseif ($firstEntryIndex -gt 0) {
        @($Lines[0..($firstEntryIndex - 1)])
    }
    else {
        @($Lines)
    }

    $header = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $candidate) {
        if ([string]::Equals($line.Trim(), 'No entries yet.', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $header.Add($line)
    }
    while ($header.Count -gt 0 -and [string]::IsNullOrWhiteSpace($header[0])) {
        $header.RemoveAt(0)
    }
    while ($header.Count -gt 0 -and [string]::IsNullOrWhiteSpace($header[$header.Count - 1])) {
        $header.RemoveAt($header.Count - 1)
    }
    return , @($header.ToArray())
}

function Build-LedgerContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$HeaderLines,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$EntryLines
    )

    $builder = [System.Collections.Generic.List[string]]::new()
    if ($HeaderLines.Count -gt 0) { $builder.AddRange([string[]]$HeaderLines) }
    if ($EntryLines.Count -gt 0) {
        if ($builder.Count -gt 0) { $builder.Add('') }
        $builder.AddRange([string[]]$EntryLines)
    }
    elseif ($HeaderLines.Count -gt 0) {
        $builder.Add('')
        $builder.Add('No entries yet.')
    }
    if ($builder.Count -eq 0) { return '' }
    return ($builder -join "`n") + "`n"
}

function Resolve-LedgerPlanId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$Root
    )

    $writablePattern = '^([0-9a-f]{6}|\d{3})$'
    $inventory = @()
    try { $inventory = @(Get-PlanInventory -RepoRoot $Root) } catch { $inventory = @() }
    if ($inventory.Count -gt 0) {
        try {
            $resolved = Resolve-Plan -Reference $Reference -RepoRoot $Root -Inventory $inventory
            if ($resolved -and $resolved.Id -and ([string]$resolved.Id -match $writablePattern)) {
                return [string]$resolved.Id
            }
        }
        catch {
            # A literal canonical id remains valid in consumer repositories without plan inventory.
        }
    }
    if ($Reference -match $writablePattern) { return $Reference }
    throw "Plan reference '$Reference' could not be resolved to a canonical writable id (no matching plan; not a 6-hex or 3-digit id)."
}

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function ConvertTo-LedgerCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Root
    )

    $category = [string](Get-ObjectProperty -Object $InputObject -Name Category)
    $plan = [string](Get-ObjectProperty -Object $InputObject -Name Plan)
    $src = [string](Get-ObjectProperty -Object $InputObject -Name Src)
    $severity = [string](Get-ObjectProperty -Object $InputObject -Name Severity)
    $entry = [string](Get-ObjectProperty -Object $InputObject -Name Entry)
    $date = [string](Get-ObjectProperty -Object $InputObject -Name Date -Default (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))
    $tags = [string[]]@(Get-ObjectProperty -Object $InputObject -Name Tags -Default @())
    $sourceId = [string](Get-ObjectProperty -Object $InputObject -Name SourceId -Default '')

    if ($script:LedgerCategories -notcontains $category) { throw "Invalid ledger category '$category'." }
    if ($script:LedgerSources -notcontains $src) { throw "Invalid ledger source '$src'." }
    if ($script:LedgerSeverities -notcontains $severity) { throw "Invalid ledger severity '$severity'." }
    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date '$date' must match yyyy-MM-dd." }

    $canonicalPlan = Resolve-LedgerPlanId -Reference $plan -Root $Root
    $entrySanitized = ConvertTo-SafeLedgerText -Text $entry -MaxLength $script:MaxEntryLength
    $tagSet = Get-LedgerTagSet -InputTags $tags
    $sortedTags = if ($tagSet.Count -eq 0) { '' } else { $tagSet -join '|' }
    $normalizedLesson = Normalize-LedgerLesson -Text $entrySanitized -MaxLength $script:MaxEntryLength

    return [pscustomobject]@{
        Category = $category
        Plan = $canonicalPlan
        Src = $src
        Severity = $severity
        Entry = $entrySanitized
        NormalizedLesson = $normalizedLesson
        Tags = $tagSet
        SortedTags = $sortedTags
        Date = $date
        SourceId = $sourceId
        IdempotenceKey = "$category|$normalizedLesson|$canonicalPlan|$src|$severity|$sortedTags"
        RecurrenceKey = "$category|$normalizedLesson|$sortedTags"
    }
}

function New-LedgerCategoryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidate
    )

    $path = Resolve-LedgerPath -Root $Root -CategorySlug $Category
    $generation = Get-AtomicStoreGeneration -Path $path
    $existingContent = if ($generation -eq 'absent') {
        $title = (Get-Culture).TextInfo.ToTitleCase($Category.Replace('-', ' '))
        "# $title Ledger`n`nNo entries yet.`n"
    }
    else {
        [System.IO.File]::ReadAllText($path)
    }
    $normalizedExisting = $existingContent -replace "`r`n", "`n"
    $lines = if ($normalizedExisting.Length -eq 0) {
        @()
    }
    else {
        @($normalizedExisting.TrimEnd("`n").Split("`n"))
    }
    $headerLines = Get-LedgerHeaderLines -Lines $lines
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $record = ConvertTo-LedgerRecord -Line $line -Category $Category
        if ($null -ne $record) { $records.Add($record) }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Candidate) {
        $existingMatch = @($records | Where-Object { $_.IdempotenceKey -eq $item.IdempotenceKey })
        if ($existingMatch.Count -gt 0) {
            $results.Add([pscustomobject]@{
                    SourceId = $item.SourceId
                    Added = $false
                    Reason = 'idempotence-duplicate'
                    Line = $null
                    Category = $Category
                })
            continue
        }

        $nextRecurrence = @($records | Where-Object { $_.RecurrenceKey -eq $item.RecurrenceKey }).Count + 1
        $lesson = if ($nextRecurrence -gt 1) { "$($item.Entry) [recurrence:$nextRecurrence]" } else { $item.Entry }
        $tagSuffix = if ($item.Tags.Count -eq 0) { '' } else { ' ' + ($item.Tags -join ' ') }
        $line = "- [$($item.Date)] $lesson (plan-$($item.Plan), src:$($item.Src), sev:$($item.Severity))$tagSuffix"
        $record = ConvertTo-LedgerRecord -Line $line -Category $Category
        if ($null -eq $record) { throw 'Failed to construct parseable ledger entry.' }
        $records.Add($record)
        $results.Add([pscustomobject]@{
                SourceId = $item.SourceId
                Added = $true
                Reason = 'added'
                Line = $line
                Category = $Category
            })
    }

    $ordered = Get-DeterministicLedgerOrder -Records @($records)
    $content = Build-LedgerContent -HeaderLines $headerLines -EntryLines @($ordered | ForEach-Object { $_.Line })
    $contentBytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    if ($records.Count -gt $script:MaxRecords -or $contentBytes -gt $script:MaxCategoryBytes) {
        return [pscustomobject]@{
            Status = 'capacity-blocked'
            Category = $Category
            Path = $path
            Reason = "ledger category exceeds $($script:MaxRecords) records or $($script:MaxCategoryBytes) bytes"
        }
    }

    return [pscustomobject]@{
        Status = 'complete'
        Category = $Category
        Path = $path
        Generation = $generation
        ExistingContent = $normalizedExisting
        Content = $content
        Results = @($results)
    }
}

function Invoke-LedgerBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if ($Entry.Count -eq 0) {
        return [pscustomobject]@{ Status = 'complete'; Added = 0; Duplicate = 0; Results = @(); Categories = @() }
    }

    $candidates = @($Entry | ForEach-Object { ConvertTo-LedgerCandidate -InputObject $_ -Root $root })
    $candidates = @(
        $candidates | Sort-Object `
            @{ Expression = { $_.Category } },
            @{ Expression = { $_.NormalizedLesson } },
            @{ Expression = { $_.SortedTags } },
            @{ Expression = { $_.Plan } },
            @{ Expression = { $_.Src } },
            @{ Expression = { $_.Severity } },
            @{ Expression = { $_.Date } },
            @{ Expression = { $_.SourceId } }
    )
    $categories = [string[]]@($candidates.Category | Select-Object -Unique)
    $normalizedLockRoot = Resolve-PhysicalRepoPath -Path $root
    if ($IsWindows) { $normalizedLockRoot = $normalizedLockRoot.ToLowerInvariant() }
    $lockScope = "$normalizedLockRoot|ledger-store"

    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        $states = [System.Collections.Generic.List[object]]::new()
        foreach ($category in $categories) {
            $state = New-LedgerCategoryState -Root $root -Category $category `
                -Candidate @($candidates | Where-Object { $_.Category -eq $category })
            if ($state.Status -eq 'capacity-blocked') {
                return [pscustomobject]@{
                    Status = 'capacity-blocked'
                    Added = 0
                    Duplicate = 0
                    Results = @()
                    Categories = $categories
                    Category = $state.Category
                    Reason = $state.Reason
                    Attempts = $attempt
                }
            }
            $states.Add($state)
        }

        try {
            $writeResult = Invoke-WithAtomicStoreLock -Scope $lockScope -TimeoutSeconds 30 -Action {
                $activeStates = $states
                $generationChanged = $false
                foreach ($state in $states) {
                    $actual = Get-AtomicStoreGeneration -Path $state.Path
                    if (-not [string]::Equals($actual, $state.Generation, [System.StringComparison]::Ordinal)) {
                        $generationChanged = $true
                        break
                    }
                }
                if ($generationChanged) {
                    $activeStates = [System.Collections.Generic.List[object]]::new()
                    foreach ($category in $categories) {
                        $refreshed = New-LedgerCategoryState -Root $root -Category $category `
                            -Candidate @($candidates | Where-Object { $_.Category -eq $category })
                        if ($refreshed.Status -eq 'capacity-blocked') {
                            return [pscustomobject]@{
                                Status = 'capacity-blocked'
                                Category = $refreshed.Category
                                Reason = $refreshed.Reason
                            }
                        }
                        $activeStates.Add($refreshed)
                    }
                }

                foreach ($state in $activeStates) {
                    if ([string]::Equals($state.ExistingContent, $state.Content, [System.StringComparison]::Ordinal) -and
                        $state.Generation -ne 'absent') {
                        continue
                    }
                    $write = Set-AtomicStoreContent -Path $state.Path -Content $state.Content `
                        -ExpectedGeneration $state.Generation
                    if ($write.Status -eq 'cas-conflict') {
                        return [pscustomobject]@{ Status = 'cas-conflict' }
                    }
                    if ($write.Status -ne 'complete') {
                        throw "Ledger category '$($state.Category)' write failed with status '$($write.Status)'."
                    }
                }
                return [pscustomobject]@{ Status = 'complete'; States = @($activeStates) }
            }
        }
        catch [System.TimeoutException] {
            return [pscustomobject]@{
                Status = 'lock-timeout'
                Added = 0
                Duplicate = 0
                Results = @()
                Categories = $categories
                Attempts = $attempt
            }
        }

        if ($writeResult.Status -eq 'cas-conflict') { continue }
        if ($writeResult.Status -eq 'capacity-blocked') {
            return [pscustomobject]@{
                Status = 'capacity-blocked'
                Added = 0
                Duplicate = 0
                Results = @()
                Categories = $categories
                Category = $writeResult.Category
                Reason = $writeResult.Reason
                Attempts = $attempt
            }
        }
        $results = @($writeResult.States | ForEach-Object { $_.Results })
        return [pscustomobject]@{
            Status = 'complete'
            Added = @($results | Where-Object Added).Count
            Duplicate = @($results | Where-Object { -not $_.Added }).Count
            Results = $results
            Categories = $categories
            Attempts = $attempt
        }
    }

    return [pscustomobject]@{
        Status = 'cas-exhausted'
        Added = 0
        Duplicate = 0
        Results = @()
        Categories = $categories
        Attempts = $script:MaxAttempts
    }
}

function Invoke-LedgerScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Plan,
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Severity,
        [Parameter(Mandatory)][string]$Entry,
        [string[]]$Tags = @(),
        [string]$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    )

    return Invoke-LedgerBatch -RepoRoot $RepoRoot -Entry @([pscustomobject]@{
            Category = $Category
            Plan = $Plan
            Src = $Src
            Severity = $Severity
            Entry = $Entry
            Tags = $Tags
            Date = $Date
        })
}

Export-ModuleMember -Function Resolve-LedgerPath, ConvertTo-SafeLedgerText,
    Invoke-LedgerBatch, Invoke-LedgerScalar
