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
.EXAMPLE
    & Build-ReviewReport.ps1 -Mode Freeze -RunId $uuid -PlanDir docs/implementation-plans/<plan>
.EXAMPLE
    & Build-ReviewReport.ps1 -Mode Publish -RunId $uuid
.NOTES
    Plan c21cdc step 1.2 adds the `Freeze`/`Publish` persistence modes beside the legacy object
    formatter. Those modes derive every root from this script's installed location and delegate all
    file I/O, validation, canonicalization, rendering and publication to `ReviewRun.psm1`, so this
    script itself performs no file I/O and stays the pure formatter the b0c0d3 contract pins. The
    legacy `-Finding`/`-Model` invocation is unchanged and is retired only in the phase 2 caller
    migration (REQ-13).
#>
[CmdletBinding(DefaultParameterSetName = 'Legacy')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Legacy')]
    [AllowEmptyCollection()]
    [object[]]$Finding,

    [Parameter(Mandatory, ParameterSetName = 'Legacy')]
    [AllowEmptyCollection()]
    [string[]]$Model,

    [Parameter(ParameterSetName = 'Legacy')]
    [string]$Scope,

    [Parameter(ParameterSetName = 'Legacy')]
    [ValidateSet('Code Review', 'Design Review')]
    [string]$ReportTitle = 'Code Review',

    [Parameter(ParameterSetName = 'Legacy')]
    [int]$InvocationCount = 0,

    [Parameter(ParameterSetName = 'Legacy')]
    [int]$InvocationBudget = 28,

    # Persistence modes: the only inputs a caller may choose are a run id and, for a plan run, a
    # confined plan directory. Repo, schema and output roots are computed by the module.
    [Parameter(Mandatory, ParameterSetName = 'Persist')]
    [ValidateSet('Freeze', 'Publish')]
    [string]$Mode,

    [Parameter(Mandatory, ParameterSetName = 'Persist')]
    [string]$RunId,

    [Parameter(ParameterSetName = 'Persist')]
    [string]$PlanDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Persist') {
    # Everything the persistence modes touch — the filesystem, the schemas, the lock — lives in the
    # module, so this script's own text carries no file I/O and stdout is exactly one bounded
    # terminal-status object followed by the mode's exit code.
    #
    # The module path is built with named Join-Path parameters on purpose: phase 1 ships the engine
    # in scripts/skalary/ only, and the phase-1 bundle closure scanner keys off the bare
    # `$PSScriptRoot '<name>.psm1'` form. Step 2.1 (REQ-8) is what distributes ReviewRun.psm1, the
    # reader, the cleanup helper and the schemas into the installed plugins, mapping them explicitly.
    $moduleName = 'ReviewRun.psm1'
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath $moduleName

    # Last resort, not a fallback: the module bounds every expected failure itself, so anything that
    # reaches here (a broken install, an unreadable schema directory, an unexpected host error) is
    # reported as an explicit exit 4 with one terminal-status object. Nothing is retried, nothing is
    # swallowed, and no other exit can escape this script.
    try {
        Import-Module $modulePath -Force -DisableNameChecking
        $result = if ($Mode -eq 'Freeze') {
            Invoke-ReviewFreeze -RunId $RunId -PlanDir $PlanDir
        }
        else {
            Invoke-ReviewPublish -RunId $RunId -PlanDir $PlanDir
        }
        $exit = Write-ReviewTerminalStatus -Mode ($Mode.ToLowerInvariant()) -ExitCode $result.ExitCode `
            -State $result.State -Message $result.Message -RunId $result.RunId -Diagnostic $result.Diagnostics
        exit $exit
    }
    catch {
        $failure = ([string]$_.Exception.Message) -replace '\s+', ' '
        if ($failure.Length -gt 512) { $failure = $failure.Substring(0, 512) }
        $status = [ordered]@{
            diagnostics = @($failure)
            exitCode    = 4
            message     = "$Mode failed unexpectedly before it could report a bounded status."
            mode        = $Mode.ToLowerInvariant()
        }
        # A run id that is not a UUID is never echoed: it is caller-controlled, unbounded text and the
        # status schema admits only a UUID here.
        if ($RunId -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { $status['runId'] = $RunId }
        else { $status['runIdRejected'] = $true; $status['exitCode'] = 2; $status['message'] = 'Run id must be a lowercase UUID.' }
        $status['schema'] = 'skalary/review-terminal-status@1'
        $status['state'] = $(if ($status['exitCode'] -eq 4) { 'failed' } else { 'invalid' })

        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $status -Depth 4 -Compress) + "`n")
        $stdout = [Console]::OpenStandardOutput()
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
        exit $status['exitCode']
    }
}


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
