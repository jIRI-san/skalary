#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-4/REQ-5, step 1.1. The behavior this plan must not lose is not written down
# anywhere except in the formatter's output, so it is pinned against a real one: the `b0c0d3` gate
# 10.7 branch review, 44 merged findings over 65,481 bytes, archived in this repository.
#
# The corpus is committed as the *input* that produces that report — a frozen plan and a
# `skalary/review-run@1` envelope — rather than as a second copy of the Markdown. That is what makes
# it useful to step 1.2, and it is not taken on trust: the first case below renders the committed
# envelope through the unchanged `Build-ReviewReport.ps1` and requires the bytes to come back
# identical to the archived file. A reconstruction that got any visible field wrong cannot pass it.
#
# Step 1.1 owns data and layout, not the production renderer. The two new views therefore have
# committed byte goldens — `new-layout.summary.golden.md` and `new-layout.full.golden.md` — derived
# from the same envelope by the test-only reference renderer in
# `fixtures/review-run/ReviewLayoutReference.psm1`. The tests render and compare against those
# bytes under four cultures and a shuffled envelope; nothing here compares a file to itself, and
# step 1.2's renderer inherits an exact target rather than a description of one.
Describe 'review report corpus' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:formatter = Join-Path $script:repoRoot 'scripts/skalary/Build-ReviewReport.ps1'
        $script:corpusRoot = Join-Path $PSScriptRoot 'fixtures/review-run/corpus'

        function Script:Read-Json {
            param([Parameter(Mandatory)][string]$Path)

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fixture not found: $Path" }
            return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 40)
        }

        function Script:Get-Sha256 {
            param([Parameter(Mandatory)][byte[]]$Bytes)

            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
            finally { $sha.Dispose() }
        }

        function Script:Get-NormalizedKey {
            <#
            .SYNOPSIS
                The grouping normalization the pre-change formatter applies: lower-invariant, every
                run of non-alphanumerics collapsed to one space, trimmed.
            #>
            param([string]$Value)

            if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
            return ([regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
        }

        $script:provenance = Read-Json -Path (Join-Path $script:corpusRoot 'gate-10.7-cr-branch.provenance.json')
        $script:plan = Read-Json -Path (Join-Path $script:corpusRoot 'gate-10.7-cr-branch.plan.json')
        $script:run = Read-Json -Path (Join-Path $script:corpusRoot 'gate-10.7-cr-branch.run.json')
        $script:golden = Read-Json -Path (Join-Path $script:corpusRoot 'gate-10.7-cr-branch.legacy-projection.golden.json')
        $script:expectation = Read-Json -Path (Join-Path $script:corpusRoot 'new-layout.expectation.json')
        $script:archivedPath = Join-Path $script:repoRoot ([string]$script:provenance.source.path)

        # The v1 layout is committed as bytes. They are read once, as bytes, and never handed to the
        # renderer: the renderer derives both views from the envelope alone.
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewLayoutReference.psm1') -Force -DisableNameChecking
        $script:summaryGoldenBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:corpusRoot 'new-layout.summary.golden.md'))
        $script:fullGoldenBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:corpusRoot 'new-layout.full.golden.md'))

        function Script:Get-ShuffledRun {
            <#
            .SYNOPSIS
                The committed envelope with its object properties and its task and finding arrays
                reversed, re-serialized and re-parsed so the shuffle survives the reader.
            #>
            $reordered = [ordered]@{}
            foreach ($key in @($script:run.Keys | Sort-Object -Descending)) { $reordered[[string]$key] = $script:run[$key] }
            $reordered['tasks'] = @(@($script:run.tasks)[(@($script:run.tasks).Count - 1)..0])
            $reordered['findings'] = @(@($script:run.findings)[(@($script:run.findings).Count - 1)..0])
            return (ConvertTo-Json -InputObject $reordered -Depth 40 | ConvertFrom-Json -AsHashtable -Depth 40)
        }

        # The legacy call shape, derived from the envelope: concern and model come from the task the
        # finding names, which is exactly the attribution REQ-4 moves onto the frozen plan.
        $script:taskById = @{}
        foreach ($task in @($script:run.tasks)) { $script:taskById[[string]$task.taskId] = $task }

        $script:legacyFindings = @(foreach ($finding in @($script:run.findings)) {
                $task = $script:taskById[[string]$finding.taskId]
                [pscustomobject]@{
                    Concern = [string]$task.concern
                    Model = [string]$task.model
                    Severity = [string]$finding.severity
                    Title = [string]$finding.title
                    Body = $(if ($finding.Contains('body')) { [string]$finding.body } else { '' })
                    References = $(if ($finding.Contains('references')) { @($finding.references) } else { @() })
                    RootCause = [string]$finding.rootCause
                    Component = [string]$finding.component
                }
            })

        function Script:Invoke-Formatter {
            param([object[]]$Finding = $script:legacyFindings)

            return & $script:formatter -Finding $Finding -Model @($script:run.roster) `
                -Scope ([string]$script:run.scope) -ReportTitle 'Code Review' `
                -InvocationCount @($script:run.tasks).Count -InvocationBudget ([int]$script:run.invocationBudget)
        }

        function Script:ConvertFrom-RenderedReport {
            <#
            .SYNOPSIS
                The observable semantics of one rendered report: order, title, severity, elevation,
                concerns, models, bodies, references and the recommendation action.
            #>
            param([Parameter(Mandatory)][string]$Text)

            $entries = [System.Collections.Generic.List[object]]::new()
            $actions = @{}
            $current = $null
            $inRecommendations = $false

            foreach ($line in (($Text -replace "`r`n", "`n") -split "`n")) {
                if ($line -match '^## Recommendations\s*$') {
                    if ($current) { $entries.Add($current); $current = $null }
                    $inRecommendations = $true
                    continue
                }
                if ($inRecommendations) {
                    if ($line -match '^\d+\. \*\*\[\w+\] (?<title>.+?)\*\* [-\u2014] (?<action>.+)$') {
                        $actions[$Matches['title']] = $Matches['action']
                    }
                    continue
                }
                if ($line -match '^### \[(?<n>\d+)\] (?<title>.+)$') {
                    if ($current) { $entries.Add($current) }
                    $current = [pscustomobject]@{
                        Order = [int]$Matches['n']
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
                if ($line -match '^\| \*\*Severity\*\* \| (?<severity>\w+)(?<elevated> \([^|]*elevated[^|]*\))? \|$') {
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

            foreach ($entry in $entries) {
                Add-Member -InputObject $entry -NotePropertyName 'Action' -NotePropertyValue ([string]$actions[$entry.Title])
            }
            return $entries.ToArray()
        }
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization pins the pre-change bytes of the review the corpus stands for' {
        Test-Path -LiteralPath $script:archivedPath -PathType Leaf |
            Should -BeTrue -Because 'the corpus is a real published review, not a fabricated one'

        $bytes = [System.IO.File]::ReadAllBytes($script:archivedPath)
        $bytes.Length | Should -Be 65481
        $bytes.Length | Should -Be ([int]$script:provenance.source.bytes)
        (Get-Sha256 -Bytes $bytes) | Should -Be ([string]$script:provenance.source.sha256)

        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        @([regex]::Matches($text, '(?m)^### \[\d+\] ')).Count | Should -Be 44
        @([regex]::Matches($text, '(?m)^### \[\d+\] ')).Count | Should -Be ([int]$script:provenance.source.headings)

        # The committed envelope is bound to the committed plan by digest, so a plan edited without
        # the envelope is caught here rather than in step 1.2.
        $planBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:corpusRoot 'gate-10.7-cr-branch.plan.json'))
        [string]$script:run.planDigest | Should -Be ('sha256:' + (Get-Sha256 -Bytes $planBytes))
        [string]$script:provenance.reconstruction.planDigest | Should -Be ([string]$script:run.planDigest)

        @($script:run.tasks).Count | Should -Be ([int]$script:provenance.reconstruction.plannedTasks)
        @($script:run.findings).Count | Should -Be ([int]$script:provenance.reconstruction.rawFindings)
        @($script:plan.tasks).Count | Should -Be @($script:run.tasks).Count
        @($script:golden.groups).Count | Should -Be ([int]$script:provenance.reconstruction.mergedFindings)
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization renders the committed corpus back to the archived report byte for byte' {
        $rendered = Invoke-Formatter

        # The archived copy carries two normalizations, both recorded in the provenance file: its em
        # dashes were flattened to hyphens, and it ends with one more newline than the formatter
        # emits. Everything else must be identical, which is what makes this corpus the real one.
        $normalized = ($rendered -replace [string][char]0x2014, '-') + "`n"
        $archived = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($script:archivedPath)) -replace "`r`n", "`n"

        $normalized | Should -Be $archived
        [System.Text.Encoding]::UTF8.GetByteCount($normalized) | Should -Be ([int]$script:provenance.renderedComparison.bytes)
        (Get-Sha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($normalized))) |
            Should -Be ([string]$script:provenance.renderedComparison.sha256)
        @($script:provenance.renderedComparison.normalizations).Count | Should -Be 2
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization pins the pre-change semantic projection of every merged finding' {
        $rendered = Invoke-Formatter
        $observed = @(ConvertFrom-RenderedReport -Text $rendered)
        $groups = @($script:golden.groups)

        $observed.Count | Should -Be $groups.Count
        $observed.Count | Should -Be 44

        $failures = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $groups.Count; $i++) {
            $expected = $groups[$i]
            $actual = $observed[$i]

            # Order is part of the contract, so the comparison is positional rather than by title.
            if ([int]$expected.order -ne $actual.Order) { $failures.Add("order $($expected.order) rendered at $($actual.Order)") }
            if ([string]$expected.title -ne $actual.Title) { $failures.Add("title at $($expected.order): '$($actual.Title)'") }
            if ([string]$expected.severity -ne $actual.Severity) { $failures.Add("severity at $($expected.order): '$($actual.Severity)'") }
            if ([bool]$expected.elevated -ne $actual.Elevated) { $failures.Add("elevation at $($expected.order): $($actual.Elevated)") }
            if ((@($expected.concerns) -join '|') -ne (@($actual.Concerns) -join '|')) { $failures.Add("concerns at $($expected.order)") }
            if ((@($expected.models) -join '|') -ne (@($actual.Models) -join '|')) { $failures.Add("models at $($expected.order)") }
            if ((@($expected.references) -join '|') -ne (@($actual.References) -join '|')) { $failures.Add("references at $($expected.order)") }
            if ((@($expected.bodies) -join '|') -ne (@($actual.Bodies) -join '|')) { $failures.Add("bodies at $($expected.order)") }
            if ([string]$expected.action -ne $actual.Action) { $failures.Add("action at $($expected.order)") }
        }
        $failures -join '; ' | Should -BeNullOrEmpty

        # The grouping key is not rendered, so it is pinned from the input side: the key each raw
        # finding computes under the pre-change rules, and the members that key collects.
        $membersByKey = @{}
        foreach ($finding in @($script:run.findings)) {
            $key = (Get-NormalizedKey -Value ([string]$finding.rootCause)) + [string][char]1 +
            (Get-NormalizedKey -Value ([string]$finding.component))
            if (-not $membersByKey.ContainsKey($key)) { $membersByKey[$key] = [System.Collections.Generic.List[object]]::new() }
            $membersByKey[$key].Add($finding)
        }
        $membersByKey.Count | Should -Be $groups.Count -Because 'one grouping key per merged entry, by construction'

        $keyFailures = [System.Collections.Generic.List[string]]::new()
        $severityRank = @{ 'Critical' = 4; 'High' = 3; 'Medium' = 2; 'Low' = 1 }
        foreach ($expected in $groups) {
            $key = [string]$expected.key
            if (-not $membersByKey.ContainsKey($key)) { $keyFailures.Add("no finding computes key for '$($expected.title)'"); continue }

            $members = @($membersByKey[$key])
            if ($members.Count -ne [int]$expected.rawFindings) { $keyFailures.Add("member count for '$($expected.title)'") }

            $models = @(@($members | ForEach-Object { [string]$script:taskById[[string]$_.taskId].model } | Sort-Object -Unique))
            $concerns = @(@($members | ForEach-Object { [string]$script:taskById[[string]$_.taskId].concern } | Sort-Object -Unique))
            if ((@($expected.models | Sort-Object) -join '|') -ne ($models -join '|')) { $keyFailures.Add("model set for '$($expected.title)'") }
            if ((@($expected.concerns | Sort-Object) -join '|') -ne ($concerns -join '|')) { $keyFailures.Add("concern set for '$($expected.title)'") }

            # Elevation is a render-time decision on full-roster agreement, so the stored severity is
            # one rank below the rendered one exactly when the entry is elevated.
            $rawRanks = @(@($members | ForEach-Object { $severityRank[[string]$_.severity] } | Sort-Object -Unique))
            $expectedRawRank = [int]$expected.rank - $(if ([bool]$expected.elevated) { 1 } else { 0 })
            if ($rawRanks.Count -ne 1 -or $rawRanks[0] -ne $expectedRawRank) { $keyFailures.Add("stored severity for '$($expected.title)'") }

            if ([string]$expected.keyRootCause -ne (Get-NormalizedKey -Value ([string]$members[0].rootCause))) { $keyFailures.Add("root-cause key for '$($expected.title)'") }
            if ([string]$expected.keyComponent -ne (Get-NormalizedKey -Value ([string]$members[0].component))) { $keyFailures.Add("component key for '$($expected.title)'") }
        }
        $keyFailures -join '; ' | Should -BeNullOrEmpty
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization returns identical bytes across culture, platform and input order' {
        $reference = Invoke-Formatter

        # Ordinal sorting is the whole reason the formatter does not use Sort-Object. A Turkish
        # locale changes what `i` compares to and a Czech one reorders whole letters, so a report
        # produced under either has to be byte-identical or the artifact is a function of the
        # operator's machine.
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $originalUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
        try {
            foreach ($culture in @('tr-TR', 'cs-CZ', 'de-DE', '')) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new($culture)
                (Invoke-Formatter) | Should -Be $reference -Because "the report must not depend on the '$culture' culture"
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
        }

        # Reviewers return in whatever order they finish in; the artifact must not.
        $shuffled = @($script:legacyFindings[($script:legacyFindings.Count - 1)..0])
        (Invoke-Formatter -Finding $shuffled) | Should -Be $reference

        # Platform: LF, no BOM, no carriage return, on either operating system.
        $reference | Should -Not -Match "`r"
        $reference | Should -Not -Match "`u{feff}"
        foreach ($name in @('gate-10.7-cr-branch.plan.json', 'gate-10.7-cr-branch.run.json',
                'gate-10.7-cr-branch.legacy-projection.golden.json', 'gate-10.7-cr-branch.provenance.json',
                'new-layout.expectation.json', 'new-layout.summary.golden.md', 'new-layout.full.golden.md')) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:corpusRoot $name))
            @($bytes[0], $bytes[1], $bytes[2]) -join ',' | Should -Not -Be '239,187,191' -Because "$name must carry no BOM"
            (@($bytes | Where-Object { $_ -eq 13 })).Count | Should -Be 0 -Because "$name must be LF-only"
        }
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization renders the corpus to the committed new-layout summary and full bytes' {
        # The new views get committed byte goldens, not a promise of one: the bytes below are
        # produced from the envelope by the reference renderer and compared against files this
        # repository carries. Neither side reads the other, so a layout change on either side is a
        # failure here rather than a fixture that agrees with itself.
        $summary = New-ReviewSummaryView -Run $script:run
        $full = New-ReviewFullView -Run $script:run

        $summaryBytes = [System.Text.Encoding]::UTF8.GetBytes($summary)
        $fullBytes = [System.Text.Encoding]::UTF8.GetBytes($full)

        [System.Text.Encoding]::UTF8.GetString($summaryBytes) | Should -Be ([System.Text.Encoding]::UTF8.GetString($script:summaryGoldenBytes))
        [System.Text.Encoding]::UTF8.GetString($fullBytes) | Should -Be ([System.Text.Encoding]::UTF8.GetString($script:fullGoldenBytes))
        (Compare-Object -ReferenceObject $summaryBytes -DifferenceObject $script:summaryGoldenBytes -SyncWindow 0) |
            Should -BeNullOrEmpty -Because 'the summary golden is a byte fixture, not a text one'
        (Compare-Object -ReferenceObject $fullBytes -DifferenceObject $script:fullGoldenBytes -SyncWindow 0) |
            Should -BeNullOrEmpty -Because 'the full golden is a byte fixture, not a text one'

        # Exact sizes and digests, recorded in the expectation and recomputed here.
        $summaryGolden = $script:expectation.summary.golden
        $fullGolden = $script:expectation.full.golden
        [string]$summaryGolden.file | Should -Be 'new-layout.summary.golden.md'
        [string]$fullGolden.file | Should -Be 'new-layout.full.golden.md'
        $summaryBytes.Length | Should -Be ([int]$summaryGolden.bytes)
        $fullBytes.Length | Should -Be ([int]$fullGolden.bytes)
        (Get-Sha256 -Bytes $summaryBytes) | Should -Be ([string]$summaryGolden.sha256)
        (Get-Sha256 -Bytes $fullBytes) | Should -Be ([string]$fullGolden.sha256)
        (@($summary -split "`n").Count - 1) | Should -Be ([int]$summaryGolden.lines)
        (@($full -split "`n").Count - 1) | Should -Be ([int]$fullGolden.lines)

        # The provenance file records the same two numbers, so a golden regenerated without it is
        # caught here rather than believed.
        [int]$script:provenance.newLayout.summary.bytes | Should -Be $summaryBytes.Length
        [int]$script:provenance.newLayout.full.bytes | Should -Be $fullBytes.Length
        [string]$script:provenance.newLayout.summary.sha256 | Should -Be (Get-Sha256 -Bytes $summaryBytes)
        [string]$script:provenance.newLayout.full.sha256 | Should -Be (Get-Sha256 -Bytes $fullBytes)
        [int]$script:provenance.newLayout.mergedFindings | Should -Be @($script:golden.groups).Count
        [int]$script:provenance.newLayout.rawFindings | Should -Be @($script:run.findings).Count

        # D5: both views are bounded, and the bound is the one the schema vocabulary owns.
        $limits = (Get-Content -LiteralPath (Join-Path $script:repoRoot 'schemas/review/review-limits.schema.json') -Raw |
                ConvertFrom-Json -AsHashtable -Depth 20)['x-skalary-limits']
        [int]$script:expectation.bounds.summaryMaxBytes | Should -Be ([int]$limits.maxSummaryBytes)
        [int]$script:expectation.bounds.fullMaxBytes | Should -Be ([int]$limits.maxFullBytes)
        [int]$script:expectation.bounds.maxMergedFindings | Should -Be ([int]$limits.maxMergedFindings)
        $summaryBytes.Length | Should -BeLessOrEqual ([int]$script:expectation.bounds.summaryMaxBytes)
        $fullBytes.Length | Should -BeLessOrEqual ([int]$script:expectation.bounds.fullMaxBytes)
        @($script:golden.groups).Count | Should -BeLessOrEqual ([int]$script:expectation.bounds.maxMergedFindings)

        # D15 encoding, asserted on the rendered bytes rather than promised in the expectation.
        [string]$script:expectation.encoding.newline | Should -Be 'LF'
        [bool]$script:expectation.encoding.byteOrderMark | Should -BeFalse
        [string]$script:expectation.encoding.normalizationForm | Should -Be 'NFC'
        foreach ($text in @($summary, $full)) {
            $text | Should -Not -Match "`r"
            $text | Should -Not -Match "`u{feff}"
            $text.IsNormalized([System.Text.NormalizationForm]::FormC) | Should -BeTrue
            $text | Should -Match "`n$" -Because 'both views end with exactly one newline'
        }
        [string]$script:expectation.ownedByStep | Should -Be '1.1'
        [string]$script:expectation.status | Should -Be 'committed'
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization names every merged finding, attendance total, task and raw finding in the two views' {
        # Completeness is checked against the corpus, not against the golden: a golden that lost a
        # finding would still be self-consistent, and D5 forbids a view that silently drops one.
        $summary = New-ReviewSummaryView -Run $script:run
        $full = New-ReviewFullView -Run $script:run
        $projection = ConvertTo-ReviewProjection -Run $script:run

        @($projection.Findings).Count | Should -Be @($script:golden.groups).Count
        @($projection.Findings).Count | Should -Be 44
        [int]$projection.RawFindingCount | Should -Be @($script:run.findings).Count
        [int]$projection.RawFindingCount | Should -Be 60

        # Order and severity of every merged entry match the pre-change projection, so the new views
        # are the same review, re-laid-out.
        for ($i = 0; $i -lt @($script:golden.groups).Count; $i++) {
            [string]$projection.Findings[$i].Title | Should -Be ([string]$script:golden.groups[$i].title)
            [string]$projection.Findings[$i].Severity | Should -Be ([string]$script:golden.groups[$i].severity)
            @($projection.Findings[$i].Raw).Count | Should -Be ([int]$script:golden.groups[$i].rawFindings)
        }

        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $projection.Findings) {
            $encoded = ConvertTo-ReviewInlineText -Value $entry.Title
            if (-not $summary.Contains($encoded)) { $missing.Add("summary: $($entry.Title)") }
            if (-not $full.Contains($encoded)) { $missing.Add("full: $($entry.Title)") }
        }
        foreach ($task in $projection.Tasks) {
            if (-not $full.Contains('`' + $task.TaskId + '`')) { $missing.Add("full task: $($task.TaskId)") }
        }
        $missing -join '; ' | Should -BeNullOrEmpty -Because 'REQ-5: neither view may omit a merged finding or a task'

        # The summary names every merged severity/title exactly once as a numbered row, and carries
        # the attendance totals for every outcome the contract defines.
        @([regex]::Matches($summary, '(?m)^\| \d+ \| (Critical|High|Medium|Low)')).Count | Should -Be 44
        $attendance = $script:expectation.summary.requiredAttendance
        [int]$attendance.plannedTasks | Should -Be @($script:run.tasks).Count
        [int]$attendance.completed | Should -Be @($script:run.tasks | Where-Object { [string]$_.outcome -eq 'completed' }).Count
        [int]$attendance.invocationBudget | Should -Be ([int]$script:run.invocationBudget)
        [string]$attendance.runState | Should -Be 'clean' -Because 'D4: only an all-completed run is clean'
        foreach ($outcome in @('completed', 'failed', 'timed-out', 'omitted', 'cancelled', 'pending')) {
            $count = @($script:run.tasks | Where-Object { [string]$_.outcome -eq $outcome }).Count
            $summary | Should -Match "(?m)^\| ``$([regex]::Escape($outcome))`` \| $count \|$"
        }
        $summary | Should -Match "(?m)^\| \*\*planned\*\* \| $(@($script:run.tasks).Count) \|$"
        $summary | Should -Match '(?m)^## Merged findings \(44 of 60 raw\)$'

        # The full view carries one raw record row per raw finding — all 60, none merged away — and
        # keeps the distinct bodies rather than only the strongest.
        @([regex]::Matches($full, '(?m)^\| `[a-z0-9-]+` \| `(Critical|High|Medium|Low)` \|')).Count |
            Should -Be @($script:run.findings).Count
        @($script:expectation.full.requiredTaskIds) -join '|' |
            Should -Be (@($projection.Tasks | ForEach-Object { [string]$_.TaskId }) -join '|')
        [int]$script:expectation.full.requiredRawFindings | Should -Be @($script:run.findings).Count
        @($script:expectation.full.requiredRawRecords) -join ',' |
            Should -Be (@($projection.Findings | ForEach-Object { @($_.Raw).Count }) -join ',') -Because 'the expectation records how many raw records each merged entry stands for'
        (@($script:expectation.full.requiredRawRecords) | Measure-Object -Sum).Sum |
            Should -Be @($script:run.findings).Count -Because 'REQ-5: every raw finding belongs to exactly one merged entry'
        [bool]$script:expectation.full.retainsDistinctBodies | Should -BeTrue
        @([regex]::Matches($full, '(?m)^\*\*Also noted:\*\*$')).Count |
            Should -Be @($projection.Findings | ForEach-Object { [Math]::Max(0, @($_.Bodies).Count - 1) } | Measure-Object -Sum).Sum
        @([regex]::Matches($full, '(?m)^### \[\d+\] ')).Count | Should -Be 44
        @([regex]::Matches($full, '(?m)^\| \d+ \| `[a-z0-9-]+` \| `[a-z0-9-]+` \|')).Count | Should -Be 14
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization renders the new layout identically across culture and shuffled task, finding and property order' {
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $originalUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
        try {
            foreach ($culture in @('tr-TR', 'cs-CZ', 'de-DE', '')) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new($culture)

                # Compared against the committed bytes under each culture, not against a reference
                # rendered on this machine: a renderer that was wrong everywhere would pass that.
                [System.Text.Encoding]::UTF8.GetBytes((New-ReviewSummaryView -Run $script:run)).Length |
                    Should -Be $script:summaryGoldenBytes.Length -Because "the summary must not depend on the '$culture' culture"
                (Get-Sha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes((New-ReviewSummaryView -Run $script:run)))) |
                    Should -Be ([string]$script:expectation.summary.golden.sha256) -Because "the summary must not depend on the '$culture' culture"
                (Get-Sha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes((New-ReviewFullView -Run $script:run)))) |
                    Should -Be ([string]$script:expectation.full.golden.sha256) -Because "the full view must not depend on the '$culture' culture"
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
        }

        # Reviewers return in whatever order they finish in, and a JSON object has no order at all.
        # The envelope is re-serialized with its properties reversed and its task and finding arrays
        # reversed, then re-parsed, so the shuffle survives the round trip the reader performs.
        $shuffled = Get-ShuffledRun
        @($shuffled.tasks)[0].taskId | Should -Not -Be @($script:run.tasks)[0].taskId -Because 'the shuffle must actually shuffle'
        @($shuffled.findings)[0].title | Should -Not -Be @($script:run.findings)[0].title

        (Get-Sha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes((New-ReviewSummaryView -Run $shuffled)))) |
            Should -Be ([string]$script:expectation.summary.golden.sha256)
        (Get-Sha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes((New-ReviewFullView -Run $shuffled)))) |
            Should -Be ([string]$script:expectation.full.golden.sha256)
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization encodes and fences untrusted reviewer text in both views' {
        # Every rendered field except the schema-patterned ids is reviewer-authored. The corpus is
        # ordinary text, so the guarantee is proven twice: on the committed goldens, which must
        # contain no raw HTML or unescaped table separator, and on a hostile envelope built to break
        # out of exactly the two places it could.
        $full = [System.Text.Encoding]::UTF8.GetString($script:fullGoldenBytes)
        $summary = [System.Text.Encoding]::UTF8.GetString($script:summaryGoldenBytes)
        ($full -replace '<!-- skalary/review-full@1 -->', '') | Should -Not -Match '<'
        ($summary -replace '<!-- skalary/review-summary@1 -->', '') | Should -Not -Match '<'

        $hostile = @{
            findings = @(
                @{
                    body = "Closing fence follows.`n``````" + "`n## Injected heading`n<script>alert(1)</script>"
                    component = 'a | b'
                    rootCause = 'hostile'
                    severity = 'Critical'
                    taskId = 'hostile-m1'
                    title = 'Pipe | pipe and [link](javascript:alert(1)) and <b>bold</b>'
                }
            )
            invocationBudget = 4
            planDigest = 'sha256:' + ('0' * 64)
            reviewType = 'code'
            roster = @('Model A')
            runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            schema = 'skalary/review-run@1'
            scope = "hostile | scope`n## not a heading"
            tasks = @(@{ concern = 'security'; model = 'Model A'; outcome = 'completed'; taskId = 'hostile-m1' })
        }

        $hostileSummary = New-ReviewSummaryView -Run $hostile
        $hostileFull = New-ReviewFullView -Run $hostile

        foreach ($text in @($hostileSummary, $hostileFull)) {
            $text | Should -Not -Match '<script>'
            # Every table row still has exactly the cells its header declares: an unescaped pipe in
            # a title would silently add one and shift the row.
            foreach ($line in ($text -split "`n" | Where-Object { $_ -match '^\| \*\*(Scope|Severity)\*\* \|' })) {
                @($line -split '(?<!\\)\|').Count | Should -Be 4 -Because "'$line' must not gain a cell"
            }
        }
        $hostileSummary | Should -Match '&lt;b&gt;bold&lt;/b&gt;' -Because 'the title is HTML-encoded in the summary table'
        $hostileFull | Should -Match '&lt;script&gt;' -Because 'the body is HTML-encoded inside its fence'

        # The body opens a fence of its own; the renderer must open a longer one, so the injected
        # heading stays inside the untrusted block instead of becoming part of the document.
        $openings = @($hostileFull -split "`n" | Where-Object { $_ -match '^`{3,}text$' })
        $openings.Count | Should -Be 1 -Because 'one untrusted body, one fence'
        $openings[0] | Should -Match '^`{4,}text$' -Because 'the fence must be longer than the backtick run inside it'

        $outside = [System.Collections.Generic.List[string]]::new()
        $fence = $null
        foreach ($line in ($hostileFull -split "`n")) {
            if ($null -eq $fence) {
                if ($line -match '^(?<fence>`{3,})text$') { $fence = $Matches['fence']; continue }
                $outside.Add($line)
                continue
            }
            if ($line -eq $fence) { $fence = $null }
        }
        $fence | Should -BeNullOrEmpty -Because 'the fence the renderer opened is the fence that closes'
        @($outside | Where-Object { $_ -match '^#' -and $_ -notmatch '^#+ (Code Review|Tasks|Merged findings|Recommendations|\[\d+\])' }) -join '; ' |
            Should -BeNullOrEmpty -Because 'a body that closed its own fence would own the rest of the document'

        $canonical = @{
            findings = @(
                @{ component = 'Café'; rootCause = 'Café'; severity = 'Medium'; taskId = 'canonical'; title = 'Composed' }
                @{ component = "Cafe`u{0301}"; rootCause = "Cafe`u{0301}"; severity = 'Medium'; taskId = 'canonical'; title = 'Decomposed' }
            )
            invocationBudget = 1
            planDigest = 'sha256:' + ('0' * 64)
            reviewType = 'code'
            roster = @('Model')
            runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            schema = 'skalary/review-run@1'
            scope = 'canonical equivalence'
            tasks = @(@{ concern = 'security'; model = 'Model'; outcome = 'completed'; taskId = 'canonical' })
        }
        @(ConvertTo-ReviewProjection -Run $canonical).Findings.Count |
            Should -Be 1 -Because 'NFC-equivalent grouping fields are one canonical semantic input'

        $caseDistinctModels = @{
            findings = @(
                @{ component = 'component'; rootCause = 'cause'; severity = 'Medium'; taskId = 'upper'; title = 'One model reported' }
            )
            invocationBudget = 2
            planDigest = 'sha256:' + ('0' * 64)
            reviewType = 'code'
            roster = @('Model', 'model')
            runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            schema = 'skalary/review-run@1'
            scope = 'ordinal model identity'
            tasks = @(
                @{ concern = 'security'; model = 'Model'; outcome = 'completed'; taskId = 'upper' }
                @{ concern = 'security'; model = 'model'; outcome = 'completed'; taskId = 'lower' }
            )
        }
        $caseProjection = ConvertTo-ReviewProjection -Run $caseDistinctModels
        $caseProjection.Findings[0].Elevated | Should -BeFalse
        $caseProjection.Findings[0].Severity |
            Should -Be 'Medium' -Because 'declared model identity is an ordinal value, not a case-insensitive label'

        $caseDistinctModels.findings = @(
            @{ body = 'same'; component = 'component'; rootCause = 'cause'; severity = 'Medium'; taskId = 'upper'; title = 'Alpha' }
            @{ body = 'same'; component = 'component'; rootCause = 'cause'; severity = 'Medium'; taskId = 'upper'; title = 'alpha' }
        )
        $raw = @((ConvertTo-ReviewProjection -Run $caseDistinctModels).Findings[0].Raw)
        $raw.Count | Should -Be 2
        @($raw.Title | Sort-Object -CaseSensitive) |
            Should -Be @('Alpha', 'alpha') -Because 'ordinal raw-record sorting must not overwrite case-distinct legal findings'
    }

    It 'test:ReviewReport.GoldenSemanticParityAndCanonicalization hands step 1.2 a closed new-layout expectation it does not yet satisfy' {
        # The layout is committed; the production renderer is not. Step 1.1 adds no `Freeze`, no
        # `Publish` and no schema use to the shipped formatter, and the renderer that produces the
        # goldens is a test fixture rather than something a consumer can install.
        $formatterText = Get-Content -LiteralPath $script:formatter -Raw
        $formatterText | Should -Not -Match '(?i)\bFreeze\b'
        $formatterText | Should -Not -Match '(?i)\bPublish\b'
        $formatterText | Should -Not -Match '(?i)Test-Json'
        $formatterText | Should -Not -Match 'ReviewLayoutReference'

        $referenceModule = Join-Path $script:corpusRoot '..' 'ReviewLayoutReference.psm1'
        Test-Path -LiteralPath $referenceModule -PathType Leaf | Should -BeTrue
        (Resolve-Path $referenceModule).Path | Should -Match '[\\/]tests[\\/]' -Because 'the reference renderer is test-only'
        $moduleText = Get-Content -LiteralPath $referenceModule -Raw
        $moduleText | Should -Not -Match '(?m)^\s*(Set-Content|Out-File|\[System\.IO\.File\]::Write)' -Because 'the reference renderer performs no file I/O'
        [string]$script:expectation.renderer | Should -Be 'ReviewLayoutReference.psm1'

        foreach ($absent in @('Get-ReviewRun.ps1', 'Remove-ReviewRun.ps1', 'Publish-ReviewRun.ps1', 'ReviewRun.psm1')) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot "scripts/skalary/$absent") |
                Should -BeFalse -Because "$absent is step 1.2, and the committed layout is not evidence that it exists"
        }
    }
}
