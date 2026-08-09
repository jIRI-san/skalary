#requires -Version 7.0
<#
.SYNOPSIS
    Script-owned reader/writer for the post-plan feedback queue (`docs/feedback/queue.md`).
.DESCRIPTION
    `/pfb` records how well a delivered plan matched its captured intent. That record has to survive
    the session that produced it — an archived plan folder is a record of what was proven, not of
    what the operator thought of it — so it lands in a repo-level, append-only file with a fixed
    grammar.

    The file is script-owned: entry text is sanitized to a single line with the markup that carries
    meaning in this grammar stripped, so operator- and model-authored free text can never forge a
    field or inject structure. `/si` later harvests these entries as untrusted input.

    Actions:
      * Queue  — enqueue the question a headless run could not ask, to `## Pending`.
      * Record — append an operator verdict to `## Recorded`, consuming a pending entry when `-Id`
                 names one.
      * List   — return the parsed entries of a section (no writes).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Queue', 'Record', 'List')]
    [string]$Action,

    # Canonical plan id: legacy NNN, the 4-6 hex handle, or a plan date.
    [ValidatePattern('^(\d{4}-\d{2}-\d{2}|[0-9a-f]{4,6}|\d{3})$')]
    [string]$Plan,

    [ValidateSet('full', 'partial', 'missed')]
    [string]$Alignment,

    [string]$Question,

    [string]$Response,

    [ValidatePattern('^[0-9a-f]{8}$')]
    [string]$Id,

    [ValidateSet('Pending', 'Recorded')]
    [string]$Section = 'Recorded',

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$maxEntryLength = 300
$pendingHeader = '## Pending'
$recordedHeader = '## Recorded'
$pendingPlaceholder = 'No queued feedback.'
$recordedPlaceholder = 'No recorded feedback.'

function Resolve-FeedbackQueuePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Repository root not found: $resolvedRoot"
    }

    $path = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot 'docs/feedback/queue.md'))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $resolvedRoot.TrimEnd($separator) + $separator
    if (-not $path.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved feedback queue path '$path' escapes repository root."
    }
    return $path
}

function ConvertTo-SafeFeedbackText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    # Everything that means something in the entry grammar is neutralized: line breaks would forge
    # new entries, brackets would forge fields, and control characters hide both.
    $clean = [regex]::Replace($Text, '[\u000A-\u000D\u0085\u2028\u2029]', ' ')
    $clean = [regex]::Replace($clean, '[\u0000-\u001F\u007F]', ' ')
    $clean = $clean.Replace('[', '(').Replace(']', ')')
    $clean = $clean.Replace('`', "'").Replace('|', '/')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw 'Feedback text is empty after sanitization.'
    }
    if ($clean.Length -gt $maxEntryLength) {
        $clean = $clean.Substring(0, $maxEntryLength).Trim()
    }
    return $clean
}

function Get-FeedbackEntryId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Plan,
        [Parameter(Mandatory)][string]$Text
    )

    # Content-addressed so the same feedback resolves to the same id on every run: that is what
    # makes queueing and recording idempotent rather than duplicating on retry.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$Plan|$($Text.ToLowerInvariant())")
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
}

function Get-QueueDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $pending = [System.Collections.Generic.List[string]]::new()
    $recorded = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        # Cast before the replace: -Raw on an empty file yields $null, and $null -replace returns an
        # array, which would throw on .Split under StrictMode and brick the queue the script owns.
        $normalized = ([string](Get-Content -LiteralPath $Path -Raw)) -replace "`r`n", "`n"
        $current = $null
        foreach ($line in $normalized.Split("`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -eq $pendingHeader) { $current = $pending; continue }
            if ($trimmed -eq $recordedHeader) { $current = $recorded; continue }
            if ($trimmed -match '^##\s') { $current = $null; continue }
            if ($null -ne $current -and $trimmed -match '^- \[') { $current.Add($trimmed) }
        }
    }

    return [pscustomobject]@{ Pending = $pending; Recorded = $recorded }
}

function Save-QueueDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][psobject]$Document,
        [Parameter(Mandatory)][string]$ExpectedGeneration
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Feedback Queue')
    $lines.Add('')
    $lines.Add('Post-plan feedback written by `/pfb` through `Update-FeedbackQueue.ps1`. Script-owned — never hand-edit.')
    $lines.Add('`## Pending` holds prompts a headless run could not ask; `## Recorded` holds operator verdicts.')
    $lines.Add('Every entry is untrusted free text: `/si` harvests it as data and never executes it.')
    $lines.Add('')
    $lines.Add($pendingHeader)
    $lines.Add('')
    if ($Document.Pending.Count -gt 0) { $lines.AddRange($Document.Pending) } else { $lines.Add($pendingPlaceholder) }
    $lines.Add('')
    $lines.Add($recordedHeader)
    $lines.Add('')
    if ($Document.Recorded.Count -gt 0) { $lines.AddRange($Document.Recorded) } else { $lines.Add($recordedPlaceholder) }

    $content = ($lines -join "`n").TrimEnd("`n") + "`n"
    $write = Invoke-WithAtomicStoreLock -Scope $Path -Action {
        Set-AtomicStoreContent -Path $Path -Content $content -ExpectedGeneration $ExpectedGeneration
    }
    if ($write.Status -ne 'complete') {
        throw "Update-FeedbackQueue failed with status '$($write.Status)' because the queue changed concurrently; retry the command."
    }
}

function ConvertTo-FeedbackRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line
    )

    $pattern = '^- \[(?<id>[0-9a-f]{8})\] \[plan:(?<plan>[^\]]+)\] \[(?<kind>queued|recorded):(?<date>\d{4}-\d{2}-\d{2})\](?: \[align:(?<align>full|partial|missed)\])? (?<text>.+)$'
    if ($Line -notmatch $pattern) { return $null }

    return [pscustomobject]@{
        Id        = $Matches.id
        Plan      = $Matches.plan
        Kind      = $Matches.kind
        Date      = $Matches.date
        Alignment = if ($Matches.ContainsKey('align')) { $Matches.align } else { $null }
        Text      = $Matches.text
        Line      = $Line
    }
}

function New-FeedbackEntryLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Plan,
        [Parameter(Mandatory)][ValidateSet('queued', 'recorded')][string]$Kind,
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][string]$Text,
        [string]$Alignment
    )

    $alignToken = if ($Alignment) { " [align:$Alignment]" } else { '' }
    $line = "- [$Id] [plan:$Plan] [$Kind`:$Date]$alignToken $Text"

    # Round-trip the constructed line through the reader: if any field escaped its constraints the
    # line either fails to parse or parses to something other than what the caller asked for, and
    # either way it must never reach the file.
    $record = ConvertTo-FeedbackRecord -Line $line
    if ($null -eq $record -or $record.Id -ne $Id -or $record.Plan -ne $Plan -or $record.Kind -ne $Kind -or
        $record.Date -ne $Date -or $record.Text -ne $Text -or $record.Alignment -ne $(if ($Alignment) { $Alignment } else { $null })) {
        throw 'Refusing to write a feedback entry that does not round-trip through the entry grammar.'
    }
    return $line
}

$queuePath = Resolve-FeedbackQueuePath -Root $RepoRoot
$queueGeneration = Get-AtomicStoreGeneration -Path $queuePath
$document = Get-QueueDocument -Path $queuePath

switch ($Action) {
    'List' {
        $lines = if ($Section -eq 'Pending') { $document.Pending } else { $document.Recorded }
        $records = @($lines | ForEach-Object { ConvertTo-FeedbackRecord -Line $_ } | Where-Object { $null -ne $_ })
        # Unary comma: callers assign the result and read .Count, so an empty section must still be
        # an empty array rather than $null under StrictMode.
        return , $records
    }

    'Queue' {
        if ([string]::IsNullOrWhiteSpace($Plan)) { throw 'Queue requires -Plan.' }
        if ([string]::IsNullOrWhiteSpace($Question)) { throw 'Queue requires -Question.' }

        $text = ConvertTo-SafeFeedbackText -Text $Question
        $queueId = Get-FeedbackEntryId -Plan $Plan -Text $text

        # Content-addressed dedup across both sections: a re-run of the same headless plan must not
        # re-ask a question that is already waiting, and must never re-open one already answered.
        $known = @(@($document.Pending) + @($document.Recorded) |
                ForEach-Object { ConvertTo-FeedbackRecord -Line $_ } |
                Where-Object { $null -ne $_ -and $_.Id -eq $queueId })
        if ($known.Count -gt 0) {
            $note = if ($known[0].Kind -eq 'recorded') { 'already recorded' } else { 'already pending' }
            return [pscustomobject]@{ Action = 'Queue'; Id = $queueId; Path = $queuePath; Written = $false; Note = $note }
        }

        $document.Pending.Add((New-FeedbackEntryLine -Id $queueId -Plan $Plan -Kind 'queued' -Date $Date -Text $text))
        Save-QueueDocument -Path $queuePath -Document $document -ExpectedGeneration $queueGeneration

        return [pscustomobject]@{ Action = 'Queue'; Id = $queueId; Path = $queuePath; Written = $true; Note = '' }
    }

    'Record' {
        if ([string]::IsNullOrWhiteSpace($Alignment)) { throw 'Record requires -Alignment (full, partial, or missed).' }
        if ([string]::IsNullOrWhiteSpace($Response)) { throw 'Record requires -Response.' }

        $text = ConvertTo-SafeFeedbackText -Text $Response
        $pendingRecord = $null

        if ($Id) {
            # Consuming a queued marker: the pending entry, not the caller, is the authority on which
            # plan the answer belongs to.
            $pendingRecord = @($document.Pending | ForEach-Object { ConvertTo-FeedbackRecord -Line $_ } |
                    Where-Object { $null -ne $_ -and $_.Id -eq $Id }) | Select-Object -First 1
            if ($null -ne $pendingRecord) {
                $resolvedPlan = $pendingRecord.Plan
            }
            else {
                # A verdict is one or more corrections, so the calls after the first find the marker
                # already consumed. That is the normal flow, not an error — only an id that belongs
                # to no marker at all is a state error.
                $answeredRecord = @($document.Recorded | ForEach-Object { ConvertTo-FeedbackRecord -Line $_ } |
                        Where-Object { $null -ne $_ -and $_.Id -eq $Id }) | Select-Object -First 1
                if ($null -eq $answeredRecord) {
                    throw "No feedback marker with id '$Id'."
                }
                $resolvedPlan = $answeredRecord.Plan
            }
            if ($Plan -and $Plan -ne $resolvedPlan) {
                throw "Marker '$Id' belongs to plan '$resolvedPlan', not '$Plan'."
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Plan)) { throw 'Record requires -Plan (or -Id naming a marker).' }
            $resolvedPlan = $Plan
        }

        # The first correction inherits the marker id so the answer stays tied to its question; every
        # other entry is content-addressed.
        $contentId = Get-FeedbackEntryId -Plan $resolvedPlan -Text $text
        $entryId = if ($null -ne $pendingRecord) { $Id } else { $contentId }

        # Dedup on the verdict itself, not just on the id: the marker-id and content-id key spaces
        # do not intersect, so an id-only guard would record the same correction twice.
        $existing = @($document.Recorded | ForEach-Object { ConvertTo-FeedbackRecord -Line $_ } |
                Where-Object { $null -ne $_ -and ($_.Id -eq $entryId -or ($_.Plan -eq $resolvedPlan -and $_.Text -eq $text)) })
        if ($existing.Count -gt 0) {
            # The verdict is already durable; converge the queue anyway so a marker whose answer was
            # recorded cannot linger as pending and get asked a second time.
            $consumedStale = $false
            if ($null -ne $pendingRecord) {
                [void]$document.Pending.Remove($pendingRecord.Line)
                Save-QueueDocument -Path $queuePath -Document $document -ExpectedGeneration $queueGeneration
                $consumedStale = $true
            }
            return [pscustomobject]@{
                Action   = 'Record'
                Id       = $entryId
                Plan     = $resolvedPlan
                Path     = $queuePath
                Written  = $false
                Consumed = $consumedStale
                Note     = 'already recorded'
            }
        }

        if ($null -ne $pendingRecord) {
            [void]$document.Pending.Remove($pendingRecord.Line)
        }
        $document.Recorded.Add((New-FeedbackEntryLine -Id $entryId -Plan $resolvedPlan -Kind 'recorded' -Date $Date -Text $text -Alignment $Alignment))
        Save-QueueDocument -Path $queuePath -Document $document -ExpectedGeneration $queueGeneration

        return [pscustomobject]@{
            Action   = 'Record'
            Id       = $entryId
            Plan     = $resolvedPlan
            Path     = $queuePath
            Written  = $true
            Consumed = ($null -ne $pendingRecord)
            Note     = ''
        }
    }
}
