#requires -Version 7.0
<#
.SYNOPSIS
    Regenerates the committed v1 summary/full goldens and the layout expectation from the corpus.
.DESCRIPTION
    Plan c21cdc REQ-4/REQ-5, step 1.1. The two published views need goldens now — separate from the
    legacy report, across culture and platform — but the production renderer is step 1.2. The
    goldens are therefore derived from the committed `skalary/review-run@1` envelope through the
    test-only reference renderer in `ReviewLayoutReference.psm1`, which implements the contract
    rather than reading any golden.

    This script writes:
      * `corpus/new-layout.summary.golden.md` — exact committed bytes of the summary view;
      * `corpus/new-layout.full.golden.md` — exact committed bytes of the full view;
      * `corpus/new-layout.expectation.json` — the closed content contract plus the exact sizes and
        digests of the two files above, which is what `ReviewReportCorpus.Tests.ps1` compares the
        freshly rendered bytes against;
      * the `newLayout` block of `corpus/gate-10.7-cr-branch.provenance.json`, so the corpus records
        the two goldens beside the archived report it reconstructs.

    It refuses to write a golden that does not render identically under `tr-TR`, `cs-CZ`, `de-DE`
    and the invariant culture, or with the task and finding arrays reversed: a fixture that is a
    function of the operator's machine would pin the machine, not the contract.

    Both files are written LF, UTF-8 without BOM.
.EXAMPLE
    pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewLayoutGolden.ps1
#>
[CmdletBinding()]
param(
    [string]$CorpusDirectory = (Join-Path $PSScriptRoot 'corpus')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReviewLayoutReference.psm1') -Force -DisableNameChecking

function Read-Json {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fixture not found: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 40)
}

function Get-Sha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)

    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-ShuffledRun {
    <#
    .SYNOPSIS
        The same envelope with task, finding and object-property order reversed.
    #>
    param([Parameter(Mandatory)][hashtable]$Run)

    $clone = [ordered]@{}
    foreach ($key in @($Run.Keys | Sort-Object -Descending)) { $clone[[string]$key] = $Run[$key] }
    $clone['tasks'] = @(@($Run['tasks'])[(@($Run['tasks']).Count - 1)..0])
    $clone['findings'] = @(@($Run['findings'])[(@($Run['findings']).Count - 1)..0])
    return $clone
}

$runPath = Join-Path $CorpusDirectory 'gate-10.7-cr-branch.run.json'
$run = Read-Json -Path $runPath
$summary = New-ReviewSummaryView -Run $run
$full = New-ReviewFullView -Run $run

# A golden that only holds on this machine's culture would pin the machine. Proven here as well as
# in the suite, because a regenerated golden must never be the thing that introduces the drift.
$originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
$originalUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
try {
    foreach ($culture in @('tr-TR', 'cs-CZ', 'de-DE', '')) {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
        [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new($culture)
        if ((New-ReviewSummaryView -Run $run) -ne $summary) { throw "Summary view is not stable under the '$culture' culture." }
        if ((New-ReviewFullView -Run $run) -ne $full) { throw "Full view is not stable under the '$culture' culture." }
    }
}
finally {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
}

$shuffled = Get-ShuffledRun -Run $run
if ((New-ReviewSummaryView -Run $shuffled) -ne $summary) { throw 'Summary view depends on input order.' }
if ((New-ReviewFullView -Run $shuffled) -ne $full) { throw 'Full view depends on input order.' }

$summaryBytes = [System.Text.Encoding]::UTF8.GetBytes($summary)
$fullBytes = [System.Text.Encoding]::UTF8.GetBytes($full)
$maxSummaryBytes = 32768
$maxFullBytes = 1048576
if ($summaryBytes.Length -gt $maxSummaryBytes) { throw "Summary view is $($summaryBytes.Length) bytes, over the 32 KiB budget." }
if ($fullBytes.Length -gt $maxFullBytes) { throw "Full view is $($fullBytes.Length) bytes, over the 1 MiB budget." }

Write-Utf8NoBom -Path (Join-Path $CorpusDirectory 'new-layout.summary.golden.md') -Text $summary
Write-Utf8NoBom -Path (Join-Path $CorpusDirectory 'new-layout.full.golden.md') -Text $full

$projection = ConvertTo-ReviewProjection -Run $run
$expectationPath = Join-Path $CorpusDirectory 'new-layout.expectation.json'
$expectation = Read-Json -Path $expectationPath

$expectation['schema'] = 'skalary/review-layout-expectation@1'
$expectation['ownedByStep'] = '1.1'
$expectation['status'] = 'committed'
$expectation['description'] = 'The v1 layout of the two published views, pinned as committed byte goldens beside the closed content contract they satisfy. The goldens are produced from `gate-10.7-cr-branch.run.json` by the test-only reference renderer `ReviewLayoutReference.psm1`; the production renderer, publication and the `Freeze`/`Publish` CLI remain step 1.2 and must reproduce these bytes. Regenerate with `pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewLayoutGolden.ps1`.'
$expectation['corpus'] = 'gate-10.7-cr-branch.run.json'
$expectation['renderer'] = 'ReviewLayoutReference.psm1'
$expectation['bounds'] = [ordered]@{
    summaryMaxBytes = $maxSummaryBytes
    fullMaxBytes = $maxFullBytes
    maxMergedFindings = 128
}
$expectation['encoding'] = [ordered]@{
    newline = 'LF'
    byteOrderMark = $false
    normalizationForm = 'NFC'
    cultureInvariant = $true
    untrustedFields = [ordered]@{
        inline = 'scope, model names, titles, actions, references and task diagnostics are NFC-normalized, whitespace-collapsed, HTML-encoded and Markdown-escaped before they reach a line or a table cell'
        block = 'bodies are NFC/LF-normalized, HTML-encoded and wrapped in a backtick fence longer than any backtick run they contain, under an explicit untrusted-data warning'
        code = 'only schema-patterned identifiers (run id, task id, concern, outcome, severity, digest) are rendered as code spans'
    }
}

$summaryGolden = [ordered]@{
    file = 'new-layout.summary.golden.md'
    bytes = $summaryBytes.Length
    sha256 = (Get-Sha256 -Bytes $summaryBytes)
    lines = @($summary -split "`n").Count - 1
}
$fullGolden = [ordered]@{
    file = 'new-layout.full.golden.md'
    bytes = $fullBytes.Length
    sha256 = (Get-Sha256 -Bytes $fullBytes)
    lines = @($full -split "`n").Count - 1
}

$summarySection = [ordered]@{
    golden = $summaryGolden
    requiredAttendance = [ordered]@{
        plannedTasks = @($projection.Tasks).Count
        completed = [int]$projection.Attendance['completed']
        failed = [int]$projection.Attendance['failed']
        timedOut = [int]$projection.Attendance['timed-out']
        omitted = [int]$projection.Attendance['omitted']
        cancelled = [int]$projection.Attendance['cancelled']
        pending = [int]$projection.Attendance['pending']
        invocationBudget = [int]$projection.InvocationBudget
        runState = [string]$projection.State
    }
    requiredMergedFindings = @($projection.Findings | ForEach-Object {
            [ordered]@{ severity = [string]$_.Severity; title = [string]$_.Title }
        })
}
$expectation['summary'] = $summarySection

$fullSection = [ordered]@{
    golden = $fullGolden
    requiredTaskIds = @($projection.Tasks | ForEach-Object { [string]$_.TaskId })
    requiredMergedTitles = @($projection.Findings | ForEach-Object { [string]$_.Title })
    requiredRawFindings = [int]$projection.RawFindingCount
    requiredRawRecords = @($projection.Findings | ForEach-Object { @($_.Raw).Count })
    retainsDistinctBodies = $true
}
$expectation['full'] = $fullSection

$ordered = [ordered]@{}
foreach ($key in @('schema', 'ownedByStep', 'status', 'description', 'corpus', 'renderer', 'bounds', 'encoding', 'summary', 'full')) {
    $ordered[$key] = $expectation[$key]
}
Write-Utf8NoBom -Path $expectationPath -Text (((ConvertTo-Json -InputObject $ordered -Depth 20) -replace "`r`n", "`n").TrimEnd() + "`n")

# The provenance file is the one place the corpus records what it stands for, so the two goldens are
# recorded there as well as in the expectation. `ReviewReportCorpus.Tests.ps1` compares both against
# the freshly rendered bytes, which is what stops one of them being updated without the other.
$provenancePath = Join-Path $CorpusDirectory 'gate-10.7-cr-branch.provenance.json'
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json -Depth 40
$newLayout = [ordered]@{
    description = 'The v1 summary and full views of the same run, committed as byte goldens. They are derived from `gate-10.7-cr-branch.run.json` by the test-only reference renderer and are not a second copy of the archived Markdown: the archived report is the pre-change layout, these are the layout step 1.2 must reproduce.'
    renderer = 'tests/skalary/fixtures/review-run/ReviewLayoutReference.psm1'
    generator = 'tests/skalary/fixtures/review-run/New-ReviewLayoutGolden.ps1'
    expectation = 'new-layout.expectation.json'
    summary = [ordered]@{ file = $summaryGolden.file; bytes = $summaryGolden.bytes; sha256 = $summaryGolden.sha256 }
    full = [ordered]@{ file = $fullGolden.file; bytes = $fullGolden.bytes; sha256 = $fullGolden.sha256 }
    mergedFindings = @($projection.Findings).Count
    rawFindings = [int]$projection.RawFindingCount
    encoding = 'LF, UTF-8 without BOM, NFC, culture-invariant'
}
Add-Member -InputObject $provenance -NotePropertyName 'newLayout' -NotePropertyValue ([pscustomobject]$newLayout) -Force
Write-Utf8NoBom -Path $provenancePath -Text (((ConvertTo-Json -InputObject $provenance -Depth 40) -replace "`r`n", "`n").TrimEnd() + "`n")

Write-Host "summary: $($summaryBytes.Length) bytes, $($summaryGolden.sha256)"
Write-Host "full:    $($fullBytes.Length) bytes, $($fullGolden.sha256)"
