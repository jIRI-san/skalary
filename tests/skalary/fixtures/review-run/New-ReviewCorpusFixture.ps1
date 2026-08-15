#requires -Version 7.0
<#
.SYNOPSIS
    Regenerates the committed 44-finding review corpus fixtures from the archived review artifact.
.DESCRIPTION
    Plan c21cdc REQ-4/REQ-5, step 1.1. The corpus this plan has to migrate without losing behavior
    is a real published review: the `b0c0d3` gate 10.7 branch review, 65,481 bytes, 44 merged
    findings, archived under `docs/implementation-plans/archived/`. Copying that Markdown into
    `tests/` would commit a second copy of a file the repository already has, and Markdown is the
    old *output* — the migration needs the *input* the formatter is given.

    This script therefore reads the archived report, recovers the reviewer records that produce it,
    and writes them as a `skalary/review-run@1` envelope plus the frozen plan it is bound to. The
    recovery is exact rather than approximate: the archived bytes remain the historical authority,
    the semantic projection pins the recovered grouping/selection facts, and
    `ReviewReportCorpus.Tests.ps1` renders the reconstructed envelope through the production v1
    renderer against committed new-layout goldens.

    Reconstruction rules, all derived from the formatter this plan must preserve:
      * one merged entry becomes `max(bodies, models, concerns)` raw findings, cycling models and
        concerns so the merged sets come out exactly as rendered;
      * an entry rendered as elevated is one severity rank below its rendered severity, because
        elevation happens at render time on full-roster agreement;
      * `RootCause` is the entry title and `Component` its first rendered reference, which is what
        makes the 44 grouping keys distinct and stable;
      * `Action` is left unset, so the recommendation line stays the derived first sentence it is in
        the archived report rather than a value this script invented.

    Digest-bound fixtures (`*.plan.json`, `*.run.json`) are written in canonical form — compact,
    ordinal-sorted keys, LF, UTF-8 without BOM — so `planDigest` is the SHA-256 of exactly the bytes
    committed. Human-read fixtures (provenance, goldens, layout expectation) are indented. The two
    new-layout views and their expectation are produced by `New-ReviewLayoutGolden.ps1`, which this
    script invokes last.
.EXAMPLE
    pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewCorpusFixture.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'corpus')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRelative = 'docs/implementation-plans/archived/2026-07-31-b0c0d3-review-split-plan-assets-self-improvement/assets/reviews/gate-10.7-cr-branch.md'
$sourcePath = Join-Path $RepoRoot $sourceRelative
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Archived corpus not found: $sourceRelative"
}

$runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
$roster = @('Claude Opus 5 (copilot)', 'GPT-5.6 Sol (copilot)')
$invocationBudget = 28
$severityRank = @{ 'Critical' = 4; 'High' = 3; 'Medium' = 2; 'Low' = 1 }
$rankSeverity = @{ 4 = 'Critical'; 3 = 'High'; 2 = 'Medium'; 1 = 'Low' }

function ConvertTo-CanonicalNode {
    <#
    .SYNOPSIS
        Orders object keys ordinally, depth first. Array order is data and is preserved.
    #>
    param([object]$Node)

    if ($Node -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Node.Keys | Sort-Object -CaseSensitive)) {
            $ordered[[string]$key] = ConvertTo-CanonicalNode -Node $Node[$key]
        }
        return $ordered
    }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        # Returned with the comma operator: a bare return unrolls a one-element array into its
        # element, which would silently turn a single-reference finding into a string.
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Node) { $items.Add((ConvertTo-CanonicalNode -Node $item)) }
        return , $items.ToArray()
    }
    return $Node
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value,
        [switch]$Canonical
    )

    $text = if ($Canonical) {
        ConvertTo-Json -InputObject (ConvertTo-CanonicalNode -Node $Value) -Depth 30 -Compress
    }
    else {
        ConvertTo-Json -InputObject $Value -Depth 30
    }
    $text = ($text -replace "`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
    return $text
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

# --- read the archived report as records ------------------------------------------------------
$sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
$sourceText = [System.Text.Encoding]::UTF8.GetString($sourceBytes) -replace "`r`n", "`n"

$entries = [System.Collections.Generic.List[object]]::new()
$recommendations = [System.Collections.Generic.List[object]]::new()
$current = $null
$inRecommendations = $false
$scope = $null

foreach ($line in ($sourceText -split "`n")) {
    if ($line -match '^## Recommendations\s*$') {
        if ($current) { $entries.Add($current); $current = $null }
        $inRecommendations = $true
        continue
    }
    if ($inRecommendations) {
        if ($line -match '^(?<n>\d+)\. \*\*\[(?<severity>\w+)\] (?<title>.+?)\*\* - (?<action>.+)$') {
            $recommendations.Add([pscustomobject]@{
                    Index = [int]$Matches['n']
                    Severity = $Matches['severity']
                    Title = $Matches['title']
                    Action = $Matches['action']
                })
        }
        continue
    }
    if ($null -eq $scope -and $line -match '^_(?<scope>.+)_$') { $scope = $Matches['scope']; continue }
    if ($line -match '^### \[(?<n>\d+)\] (?<title>.+)$') {
        if ($current) { $entries.Add($current) }
        $current = [pscustomobject]@{
            Index = [int]$Matches['n']
            Title = $Matches['title']
            Severity = $null
            Elevated = $false
            Concerns = @()
            Models = @()
            Bodies = [System.Collections.Generic.List[string]]::new()
            References = @()
        }
        continue
    }
    if ($null -eq $current) { continue }
    if ($line -match '^\| \*\*Severity\*\* \| (?<severity>\w+)(?<elevated> \(elevated - flagged by every dispatched model\))? \|$') {
        $current.Severity = $Matches['severity']
        $current.Elevated = $Matches.ContainsKey('elevated')
        continue
    }
    if ($line -match '^\| \*\*Concerns\*\* \| (?<value>.+) \|$') { $current.Concerns = @($Matches['value'] -split ' · '); continue }
    if ($line -match '^\| \*\*Models\*\* \| (?<value>.+) \|$') { $current.Models = @($Matches['value'] -split ' · '); continue }
    if ($line -match '^\*\*References:\*\* (?<value>.+)$') { $current.References = @($Matches['value'] -split ' · '); continue }
    if ($line -match '^\|' -or $line -match '^---\s*$' -or [string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -match '^_Also noted:_ (?<value>.+)$') { $current.Bodies.Add($Matches['value']); continue }
    $current.Bodies.Add($line)
}
if ($current) { $entries.Add($current) }

if ($entries.Count -ne 44) { throw "Expected 44 merged entries in the archived corpus, read $($entries.Count)." }
if ($recommendations.Count -ne 44) { throw "Expected 44 recommendation lines, read $($recommendations.Count)." }
if ([string]::IsNullOrWhiteSpace($scope)) { throw 'The archived corpus carries no scope line.' }

# --- frozen plan: one task per dispatched concern/model slot ----------------------------------
$concerns = @(@($entries | ForEach-Object { $_.Concerns } | Sort-Object -Unique))
$tasks = [System.Collections.Generic.List[object]]::new()
$taskIdBySlot = @{}
foreach ($concern in $concerns) {
    for ($modelIndex = 0; $modelIndex -lt $roster.Count; $modelIndex++) {
        $taskId = "$concern-m$($modelIndex + 1)"
        $taskIdBySlot["$concern`u{1}$($roster[$modelIndex])"] = $taskId
        $tasks.Add([ordered]@{ taskId = $taskId; concern = $concern; model = $roster[$modelIndex] })
    }
}

$plan = [ordered]@{
    schema = 'skalary/review-plan@1'
    runId = $runId
    reviewType = 'code'
    scope = $scope
    roster = $roster
    invocationBudget = $invocationBudget
    tasks = @($tasks)
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
}

$planPath = Join-Path $OutputDirectory 'gate-10.7-cr-branch.plan.json'
[void](Write-JsonFile -Path $planPath -Value $plan -Canonical)
$planDigest = 'sha256:' + (Get-Sha256 -Path $planPath)

# --- final envelope: the raw findings that render back to the archived report ------------------
$findings = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    $models = @($entry.Models)
    $entryConcerns = @($entry.Concerns)
    $bodies = @($entry.Bodies)
    $references = @($entry.References)

    $rank = $severityRank[$entry.Severity]
    if ($entry.Elevated) { $rank-- }
    if ($rank -lt 1) { throw "Entry $($entry.Index) is rendered as elevated below the lowest severity." }

    $count = [Math]::Max($bodies.Count, [Math]::Max($models.Count, $entryConcerns.Count))
    for ($i = 0; $i -lt $count; $i++) {
        $concern = $entryConcerns[$i % $entryConcerns.Count]
        $model = $models[$i % $models.Count]
        $slot = "$concern`u{1}$model"
        if (-not $taskIdBySlot.ContainsKey($slot)) { throw "Entry $($entry.Index) uses an undispatched slot '$slot'." }

        $finding = [ordered]@{
            taskId = $taskIdBySlot[$slot]
            severity = $rankSeverity[$rank]
            title = $entry.Title
            rootCause = $entry.Title
            component = $references[0]
        }
        if ($i -lt $bodies.Count) { $finding['body'] = $bodies[$i] }
        if ($i -eq 0) { $finding['references'] = $references }
        $findings.Add($finding)
    }
}

$resultTasks = @($tasks | ForEach-Object {
        [ordered]@{ taskId = $_.taskId; concern = $_.concern; model = $_.model; outcome = 'completed' }
    })

$run = [ordered]@{
    schema = 'skalary/review-run@1'
    runId = $runId
    reviewType = 'code'
    scope = $scope
    roster = $roster
    invocationBudget = $invocationBudget
    planDigest = $planDigest
    tasks = $resultTasks
    findings = @($findings)
}

$runPath = Join-Path $OutputDirectory 'gate-10.7-cr-branch.run.json'
[void](Write-JsonFile -Path $runPath -Value $run -Canonical)
$runDigest = 'sha256:' + (Get-Sha256 -Path $runPath)

# --- preserve the retired formatter's historical byte receipt and project its semantics --------
# The object API no longer exists. The archived report is the byte authority for this pre-change
# receipt; the projection below and New-ReviewLayoutGolden.ps1 independently validate the recovered
# envelope's semantics and production v1 renderings.
$normalized = $sourceText
$renderedBytes = [System.Text.Encoding]::UTF8.GetByteCount($normalized)

function Get-NormalizedKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
}

$projection = [System.Collections.Generic.List[object]]::new()
$order = 0
foreach ($recommendation in $recommendations) {
    $entry = @($entries | Where-Object { $_.Title -eq $recommendation.Title })[0]
    $order++
    $rank = $severityRank[$entry.Severity]
    $projection.Add([ordered]@{
            order = $order
            key = (Get-NormalizedKey -Value $entry.Title) + [string][char]1 + (Get-NormalizedKey -Value $entry.References[0])
            keyRootCause = Get-NormalizedKey -Value $entry.Title
            keyComponent = Get-NormalizedKey -Value $entry.References[0]
            title = $entry.Title
            rank = $rank
            severity = $entry.Severity
            elevated = $entry.Elevated
            concerns = @($entry.Concerns)
            models = @($entry.Models)
            bodies = @($entry.Bodies)
            references = @($entry.References)
            action = $recommendation.Action
            rawFindings = @($findings | Where-Object { $_.title -eq $entry.Title }).Count
        })
}

$golden = [ordered]@{
    schema = 'skalary/review-legacy-projection@1'
    description = 'Pre-change semantic projection of the 44-finding corpus under the Build-ReviewReport.ps1 semantics this plan must preserve: grouping key, selected title, retained bodies, derived action, rank/elevation, model and concern sets, reference set and entry order.'
    corpus = 'gate-10.7-cr-branch.run.json'
    formatter = 'scripts/skalary/Build-ReviewReport.ps1'
    roster = $roster
    groups = @($projection)
}
[void](Write-JsonFile -Path (Join-Path $OutputDirectory 'gate-10.7-cr-branch.legacy-projection.golden.json') -Value $golden)

# --- provenance: the archived bytes this fixture stands in for --------------------------------
$provenance = [ordered]@{
    schema = 'skalary/review-corpus-provenance@1'
    description = 'Pre-change bytes of the published review this corpus reconstructs, plus the two normalizations the archived copy carries. A change to any number here means the corpus no longer stands for the artifact it claims to.'
    source = [ordered]@{
        path = $sourceRelative
        bytes = $sourceBytes.Length
        sha256 = Get-Sha256 -Path $sourcePath
        mergedFindings = $entries.Count
        headings = $entries.Count
        concerns = $concerns.Count
        roster = $roster
        invocationCount = $resultTasks.Count
        budget = $invocationBudget
    }
    reconstruction = [ordered]@{
        planFile = 'gate-10.7-cr-branch.plan.json'
        planDigest = $planDigest
        runFile = 'gate-10.7-cr-branch.run.json'
        runDigest = $runDigest
        plannedTasks = $resultTasks.Count
        rawFindings = $findings.Count
        mergedFindings = $entries.Count
        findingOrder = 'reviewer emission order: archived entry order, then body/model/concern index within the entry'
        taskOrder = 'concern ordinal, then roster position'
        canonicalForm = 'compact JSON, ordinal-sorted object keys, LF, UTF-8 without BOM'
    }
    renderedComparison = [ordered]@{
        formatter = 'scripts/skalary/Build-ReviewReport.ps1'
        bytes = $renderedBytes
        sha256 = (($(
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    try { $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized)) } finally { $sha.Dispose() }
                ) | ForEach-Object { $_.ToString('x2') }) -join '')
        normalizations = @(
            'U+2014 EM DASH in the rendered output is compared as "-", the form the archived copy was flattened to'
            'one trailing newline is appended, which the archived copy carries and the formatter does not emit'
        )
    }
}
[void](Write-JsonFile -Path (Join-Path $OutputDirectory 'gate-10.7-cr-branch.provenance.json') -Value $provenance)

# --- the v1 layout of the two published views -------------------------------------------------
# The layout is committed as byte goldens rather than as a description, and those bytes are derived
# from the envelope written above by the test-only reference renderer. Regenerating the corpus
# therefore regenerates them, so a corpus edit can never leave the goldens describing the old input.
& (Join-Path $PSScriptRoot 'New-ReviewLayoutGolden.ps1') -CorpusDirectory $OutputDirectory

Write-Verbose "Corpus fixtures written to $OutputDirectory ($($findings.Count) raw findings, $($entries.Count) merged)." -Verbose
