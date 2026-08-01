#requires -Version 7.0
<#
.SYNOPSIS
    Pure formatter that merges typed reviewer findings into one review report.
.DESCRIPTION
    Plan b0c0d3 REQ-18. Collating 6-28 reviewer outputs is deterministic formatting, not judgment,
    so it lives in a script instead of being re-derived from prose on every review run. `/cr` and
    `/dr` pass typed finding objects and write the text this returns.

    The script performs NO file I/O: it takes objects in and returns a string. The caller owns
    where the report goes.

    Each finding is an object with:
      * Concern    (required) — the concern id that surfaced it, e.g. 'security'
      * Model      (required) — the model that produced it, e.g. 'Claude Opus 5 (copilot)'
      * Severity   (required) — Critical | High | Medium | Low
      * Title      (required) — one-line summary
      * Body       (optional) — description paragraphs
      * References (optional) — string or string[] of file/step references
      * RootCause  (optional) — explicit grouping key; falls back to the normalized title
      * Component  (optional) — explicit grouping key; falls back to the first reference
      * Action     (optional) — one-sentence recommendation; falls back to the body's first sentence

    Merge rules:
      * findings sharing (root cause, component) collapse into one entry;
      * the merged entry lists every model and every concern that flagged it;
      * an entry flagged by EVERY dispatched model is elevated one severity level (never past
        Critical), because independent agreement is the only corroboration signal available;
      * entries sort severity-descending, then by breadth of agreement, then by title.
.EXAMPLE
    $text = & Build-ReviewReport.ps1 -Finding $findings -Model $roster -Scope '7 changed files'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [object[]]$Finding,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]]$Model,

    [string]$Scope,

    [ValidateSet('Code Review', 'Design Review')]
    [string]$ReportTitle = 'Code Review',

    [int]$InvocationCount = 0,

    [int]$InvocationBudget = 28
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$severityRank = [ordered]@{
    'Critical' = 4
    'High'     = 3
    'Medium'   = 2
    'Low'      = 1
}
$severityByRank = @{ 4 = 'Critical'; 3 = 'High'; 2 = 'Medium'; 1 = 'Low' }

function Get-Field {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-NormalizedKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $lowered = $Value.ToLowerInvariant()
    $stripped = [regex]::Replace($lowered, '[^a-z0-9]+', ' ')
    return $stripped.Trim()
}

function Get-FirstSentence {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $flat = [regex]::Replace($Value.Trim(), '\s+', ' ')
    $match = [regex]::Match($flat, '^(?<sentence>.+?[.!?])(\s|$)')
    if ($match.Success) { return $match.Groups['sentence'].Value }
    return $flat
}

$roster = @($Model | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

function Sort-Ordinal {
    <#
    .SYNOPSIS
    Ordinal string sort. Sort-Object compares with the current culture, which would make the
    report depend on the operator's locale; ordinal keeps the output byte-identical everywhere.
    #>
    param([string[]]$Value)

    $copy = [string[]]@($Value)
    [array]::Sort($copy, [System.StringComparer]::Ordinal)
    # Emitted one element at a time so callers can pipe the result directly.
    return $copy
}

function Get-ModelSortKey {
    param([string]$Value)

    $index = [array]::IndexOf($roster, $Value)
    # Models outside the declared roster sort after it, alphabetically, so an operator override
    # cannot reorder the report non-deterministically.
    if ($index -lt 0) { return "1`u{1}$Value" }
    return ('0{0:d4}' -f $index)
}

$groups = [ordered]@{}

foreach ($item in $Finding) {
    $concern = [string](Get-Field -Object $item -Name 'Concern')
    $model = [string](Get-Field -Object $item -Name 'Model')
    $severity = [string](Get-Field -Object $item -Name 'Severity')
    $title = [string](Get-Field -Object $item -Name 'Title')

    foreach ($pair in @(@('Concern', $concern), @('Model', $model), @('Severity', $severity), @('Title', $title))) {
        if ([string]::IsNullOrWhiteSpace($pair[1])) {
            throw "Each finding requires a non-empty $($pair[0])."
        }
    }

    if (-not $severityRank.Contains($severity)) {
        throw "Finding '$title' has unknown severity '$severity' (expected Critical, High, Medium, or Low)."
    }

    $body = [string](Get-Field -Object $item -Name 'Body')
    $action = [string](Get-Field -Object $item -Name 'Action')
    $references = @(Get-Field -Object $item -Name 'References' | ForEach-Object { $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim() })

    $rootCause = [string](Get-Field -Object $item -Name 'RootCause')
    if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = $title }
    $component = [string](Get-Field -Object $item -Name 'Component')
    if ([string]::IsNullOrWhiteSpace($component) -and $references.Count -gt 0) { $component = $references[0] }

    $key = (Get-NormalizedKey -Value $rootCause) + "`u{1}" + (Get-NormalizedKey -Value $component)

    if (-not $groups.Contains($key)) {
        $groups[$key] = [pscustomobject]@{
            Key        = $key
            Titles     = [System.Collections.Generic.List[string]]::new()
            Bodies     = [System.Collections.Generic.List[string]]::new()
            Actions    = [System.Collections.Generic.List[string]]::new()
            Concerns   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            Models     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            References = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            Rank       = 0
        }
    }

    $group = $groups[$key]
    $group.Titles.Add($title.Trim())
    if (-not [string]::IsNullOrWhiteSpace($body)) { $group.Bodies.Add($body.Trim()) }
    if (-not [string]::IsNullOrWhiteSpace($action)) { $group.Actions.Add($action.Trim()) }
    [void]$group.Concerns.Add($concern.Trim())
    [void]$group.Models.Add($model.Trim())
    foreach ($reference in $references) { [void]$group.References.Add($reference) }
    if ($severityRank[$severity] -gt $group.Rank) { $group.Rank = $severityRank[$severity] }
}

$entries = [System.Collections.Generic.List[object]]::new()

foreach ($group in $groups.Values) {
    $models = @(Sort-Ordinal -Value @($group.Models | ForEach-Object { (Get-ModelSortKey -Value $_) + "`u{1}" + $_ }) |
            ForEach-Object { $_.Substring($_.IndexOf([char]1) + 1) })
    $concerns = @(Sort-Ordinal -Value @($group.Concerns))

    # Unanimity across the dispatched roster is the corroboration signal; a single model agreeing
    # with itself across two concerns is not.
    $unanimous = $roster.Count -ge 2 -and @($roster | Where-Object { $models -notcontains $_ }).Count -eq 0
    $rank = $group.Rank
    if ($unanimous -and $rank -lt 4) { $rank++ }

    # Longest description wins ("preserve the strongest"); ordinal comparison breaks ties so the
    # choice never depends on the order reviewers happened to return in.
    $orderedBodies = @(Sort-Ordinal -Value @($group.Bodies | ForEach-Object { ('{0:d6}' -f (999999 - [Math]::Min($_.Length, 999999))) + "`u{1}" + $_ }) |
            ForEach-Object { $_.Substring($_.IndexOf([char]1) + 1) })
    $distinctBodies = [System.Collections.Generic.List[string]]::new()
    foreach ($body in $orderedBodies) {
        if (-not $distinctBodies.Contains($body)) { $distinctBodies.Add($body) }
    }

    $title = @(Sort-Ordinal -Value @($group.Titles | ForEach-Object { ('{0:d6}' -f (999999 - [Math]::Min($_.Length, 999999))) + "`u{1}" + $_ }) |
            ForEach-Object { $_.Substring($_.IndexOf([char]1) + 1) })[0]

    $action = ''
    if ($group.Actions.Count -gt 0) {
        $action = @(Sort-Ordinal -Value @($group.Actions))[0]
    }
    elseif ($distinctBodies.Count -gt 0) {
        $action = Get-FirstSentence -Value $distinctBodies[0]
    }

    $entries.Add([pscustomobject]@{
            Title      = $title
            Rank       = $rank
            Severity   = $severityByRank[$rank]
            Elevated   = $unanimous
            Models     = $models
            Concerns   = $concerns
            Bodies     = @($distinctBodies)
            Key        = $group.Key
            References = @(Sort-Ordinal -Value @($group.References))
            Action     = $action
        })
}

# One composite ordinal key rather than a multi-property Sort-Object: Sort-Object is neither
# stable nor ordinal, so entries tying on severity, agreement breadth, and title would otherwise
# come out in whatever order the reviewers happened to return. The group key is unique by
# construction, which makes this a total order.
$sortKeys = @{}
foreach ($entry in $entries) {
    $sortKeys[$entry.Key] = ('{0:d2}' -f (9 - $entry.Rank)) + "`u{1}" +
        ('{0:d4}' -f (9999 - [Math]::Min($entry.Models.Count, 9999))) + "`u{1}" +
        $entry.Title + "`u{1}" + $entry.Key
}
$sorted = @(Sort-Ordinal -Value @($entries | ForEach-Object { $sortKeys[$_.Key] }) |
        ForEach-Object { $key = $_; $entries | Where-Object { $sortKeys[$_.Key] -eq $key } })

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("## $ReportTitle")
$lines.Add('')
if (-not [string]::IsNullOrWhiteSpace($Scope)) {
    $lines.Add("_$($Scope.Trim())_")
    $lines.Add('')
}
$modelLine = if ($roster.Count -gt 0) { $roster -join ' · ' } else { 'none declared' }
$lines.Add("Models: $modelLine.")
$lines.Add("Dispatched $InvocationCount of $InvocationBudget budgeted invocations.")
$lines.Add('')

if ($sorted.Count -eq 0) {
    $lines.Add('No findings.')
    $lines.Add('')
    $lines.Add('## Recommendations')
    $lines.Add('')
    $lines.Add('None.')
    return (($lines -join "`n") + "`n")
}

$index = 0
foreach ($entry in $sorted) {
    $index++
    $lines.Add("### [$index] $($entry.Title)")
    $lines.Add('')
    $lines.Add('| | |')
    $lines.Add('|---|---|')
    $severityCell = if ($entry.Elevated) { "$($entry.Severity) (elevated — flagged by every dispatched model)" } else { $entry.Severity }
    $lines.Add("| **Severity** | $severityCell |")
    $lines.Add("| **Concerns** | $($entry.Concerns -join ' · ') |")
    $lines.Add("| **Models** | $($entry.Models -join ' · ') |")
    $lines.Add('')

    if ($entry.Bodies.Count -gt 0) {
        $lines.Add($entry.Bodies[0])
        foreach ($extra in @($entry.Bodies | Select-Object -Skip 1)) {
            $lines.Add('')
            $lines.Add("_Also noted:_ $extra")
        }
        $lines.Add('')
    }

    if ($entry.References.Count -gt 0) {
        $lines.Add("**References:** $($entry.References -join ' · ')")
        $lines.Add('')
    }

    $lines.Add('---')
    $lines.Add('')
}

$lines.Add('## Recommendations')
$lines.Add('')
$index = 0
foreach ($entry in $sorted) {
    $index++
    $action = if ([string]::IsNullOrWhiteSpace($entry.Action)) { $entry.Title } else { $entry.Action }
    $lines.Add("$index. **[$($entry.Severity)] $($entry.Title)** — $action")
}

return (($lines -join "`n") + "`n")
