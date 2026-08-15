#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-5/D5/D6/D18, step 1.2. Publish renders canonical JSON as the authority plus a
# bounded summary and full view, admits an envelope only when both complete views fit their byte
# budgets (never truncating), and blocks a plan-associated publication that carries a high-confidence
# credential shape before any lossless artifact is written. These tests pin canonical authority,
# completeness, render-time reduction, byte-budget admission and the secret guard.
Describe 'review report output admission, completeness and secret guard' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking
        $script:runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        $script:limits = Get-ReviewLimits

        function Script:New-PublishedRun {
            param([object[]]$Tasks, [object[]]$ResultTasks, [object[]]$Findings, [string[]]$Roster = @('model-a', 'model-b'))

            $scratch = New-ReviewScratchRoot
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $budget = [Math]::Max(6, @($Tasks).Count)
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster $Roster -Tasks $Tasks -InvocationBudget $budget
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            [void](Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch)
            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster $Roster -Tasks $ResultTasks -Findings $Findings -InvocationBudget $budget
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            $result = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            return [pscustomobject]@{ Scratch = $scratch; RunDir = $runDir; Result = $result; Run = $run }
        }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard writes canonical JSON as authority and names every merged finding, attendance and task in the views' {
        $tasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b' }
            @{ taskId = 'perf-m1'; concern = 'performance'; model = 'model-a' }
        )
        $resultTasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
            @{ taskId = 'perf-m1'; concern = 'performance'; model = 'model-a'; outcome = 'failed'; diagnostic = 'reviewer crashed' }
        )
        # Two findings on one root cause merge; one distinct finding stays separate.
        $findings = @(
            @{ taskId = 'security-m1'; severity = 'High'; title = 'Unconfined path'; body = 'Path is not confined before use.'; rootCause = 'path'; component = 'src/a.ps1' }
            @{ taskId = 'security-m2'; severity = 'Medium'; title = 'Unconfined path variant'; body = 'Same root cause, second reviewer.'; rootCause = 'path'; component = 'src/a.ps1' }
            @{ taskId = 'security-m1'; severity = 'Low'; title = 'Weak comparison'; body = 'Uses -eq on secrets.'; rootCause = 'comparison'; component = 'src/b.ps1' }
        )
        $case = New-PublishedRun -Tasks $tasks -ResultTasks $resultTasks -Findings $findings
        try {
            $case.Result.ExitCode | Should -Be 5 -Because 'one failed task makes the run degraded'

            # Canonical JSON is lossless authority: every accepted task and finding survives, and it
            # still validates against the schema.
            $canonicalBytes = [System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical))
            $canonicalText = [System.Text.Encoding]::UTF8.GetString($canonicalBytes)
            (Test-ReviewSchema -Json $canonicalText -SchemaName 'review-run.schema.json') | Should -BeTrue
            $canonical = $canonicalText | ConvertFrom-Json -AsHashtable -Depth 40
            @($canonical.tasks).Count | Should -Be 3
            @($canonical.findings).Count | Should -Be 3
            $canonicalText | Should -Not -Match "`r"

            # The manifest's runDigest is the digest of exactly these canonical bytes.
            $manifest = Get-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') -Raw | ConvertFrom-Json -Depth 20
            [string]$manifest.runDigest | Should -Be (Get-ReviewDigest -Bytes $canonicalBytes)

            $projection = ConvertTo-ReviewProjection -Run $canonical
            @($projection.Findings).Count | Should -Be 2 -Because 'two findings merge, one stays separate'

            $summary = Get-ReviewRunSummaryText -RunDir $case.RunDir
            $full = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role full)))
            foreach ($entry in $projection.Findings) {
                $summary | Should -Match ([regex]::Escape($entry.Title))
                $full | Should -Match ([regex]::Escape($entry.Title))
            }
            foreach ($task in $projection.Tasks) { $full | Should -Match ('`' + [regex]::Escape($task.TaskId) + '`') }
            # Attendance is derived, not supplied.
            $summary | Should -Match '(?m)^\| `completed` \| 2 \|$'
            $summary | Should -Match '(?m)^\| `failed` \| 1 \|$'
            $summary | Should -Match '(?m)^\| \*\*planned\*\* \| 3 \|$'
            # Reduction is render-time only: the full view keeps all three raw records.
            @([regex]::Matches($full, '(?m)^\| `[a-z0-9-]+` \| `(Critical|High|Medium|Low)` \|')).Count | Should -Be 3
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard keeps both views inside their byte budgets and rejects an over-budget render with exit 3 without touching the manifest' {
        # A structurally valid envelope whose full view exceeds 1 MiB once its bodies are HTML-encoded:
        # 128 merged findings, each body 4096 '<' characters, which expand four-fold to '&lt;'.
        $tasks = @(1..128 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a' } })
        $resultTasks = @(1..128 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a'; outcome = 'completed' } })
        $body = '<' * 4096
        $findings = @(1..128 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); severity = 'High'; title = ('finding {0}' -f $_); body = $body; rootCause = ('root-{0:d3}' -f $_); component = ('component-{0:d3}' -f $_) } })

        $case = New-PublishedRun -Tasks $tasks -ResultTasks $resultTasks -Findings $findings -Roster @('model-a')
        try {
            $case.Result.ExitCode | Should -Be 3 -Because 'the encoded full view is over the 1 MiB budget'
            $case.Result.State | Should -Be 'admission'
            ($case.Result.Diagnostics -join ' ') | Should -Match 'full view'
            # Terminal, never truncated: no manifest, no canonical authority written.
            Test-Path -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') | Should -BeFalse
            (Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical) | Should -BeNullOrEmpty
            Get-ReviewRunState -RunDir $case.RunDir | Should -Be 'admission' -Because 'admission is terminal for this run id'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard proves a clean publication fits both budgets' {
        $case = New-PublishedRun -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }) `
            -ResultTasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
            -Findings @(@{ taskId = 'security-m1'; severity = 'High'; title = 'One'; body = 'b'; rootCause = 'r'; component = 'c' }) `
            -Roster @('model-a')
        try {
            $case.Result.ExitCode | Should -Be 0
            $summaryBytes = [System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role summary))
            $fullBytes = [System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role full))
            $summaryBytes.Length | Should -BeLessOrEqual ([int]$script:limits.maxSummaryBytes)
            $fullBytes.Length | Should -BeLessOrEqual ([int]$script:limits.maxFullBytes)
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard preserves every raw finding when distinct records normalize to the same merge tuple' {
        # Two collision classes the renderer used to key a dictionary by, and therefore crash on:
        # titles that differ only in surrounding whitespace, and an explicit rootCause equal to another
        # finding's defaulted one. Both are structurally distinct findings the contract accepts, and
        # publication must keep all of them, in a deterministic order, without dropping or throwing.
        $tasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b' }
        )
        $resultTasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
        )
        $findings = @(
            # Whitespace-only title difference: distinct raw records, identical after trimming.
            @{ taskId = 'security-m1'; severity = 'High'; title = 'Unconfined path'; body = 'b1'; rootCause = 'path'; component = 'src/a.ps1' }
            @{ taskId = 'security-m1'; severity = 'High'; title = '  Unconfined path  '; body = 'b1'; rootCause = 'path'; component = 'src/a.ps1' }
            # Explicit rootCause equal to the defaulted rootCause of the record below it.
            @{ taskId = 'security-m2'; severity = 'Medium'; title = 'Weak comparison'; body = 'b2'; rootCause = 'Weak comparison'; component = 'src/b.ps1' }
            @{ taskId = 'security-m2'; severity = 'Medium'; title = 'Weak comparison'; body = 'b2'; component = 'src/b.ps1' }
        )

        $case = New-PublishedRun -Tasks $tasks -ResultTasks $resultTasks -Findings $findings
        try {
            $case.Result.ExitCode | Should -Be 0 -Because 'a colliding merge tuple is legal input, not a publication failure'

            $canonicalText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical)))
            $canonical = $canonicalText | ConvertFrom-Json -AsHashtable -Depth 40
            @($canonical.findings).Count | Should -Be 4 -Because 'canonical JSON is lossless authority'

            $projection = ConvertTo-ReviewProjection -Run $canonical
            (@($projection.Findings | ForEach-Object { $_.RawCount }) | Measure-Object -Sum).Sum |
                Should -Be 4 -Because 'every raw record survives into the projection'
            foreach ($entry in $projection.Findings) {
                @($entry.Raw).Count | Should -Be ([int]$entry.RawCount)
            }

            # The full view lists all four raw records, and the render is deterministic.
            $full = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role full)))
            @([regex]::Matches($full, '(?m)^\| `[a-z0-9-]+` \| `(Critical|High|Medium|Low)` \|')).Count | Should -Be 4
            (Get-ReviewRunFullView -Run $canonical) | Should -Be $full
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard rejects a schema-valid envelope over the 2 MiB input cap with a terminal exit 3, never a retryable 4' {
        # D3/D6: the input cap is a byte budget on the bytes that arrive, so it is enforced before the
        # document is parsed — an oversized envelope must never be materialized just to be refused —
        # and it is terminal admission, not a publication failure a caller may retry.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(1..128 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a' } })
                # Eight tasks carry maximum diagnostics (a completed task may not), the rest completed.
            $resultTasks = @(1..128 | ForEach-Object {
                    $task = @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a'; outcome = 'completed' }
                    if ($_ -le 8) { $task['outcome'] = 'failed'; $task['diagnostic'] = ('d' * 2048) }
                    $task
                })
                Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks -InvocationBudget 128)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0

            # 256 findings at the per-record maxima over the completed tasks. Every record is legal;
            # what puts the file over the cap is that the caller wrote it the way an editing tool
            # does — indented — which is exactly why the budget is measured on the bytes on disk
            # rather than on a re-serialized copy.
            $body = 'b' * 4096
            $action = 'a' * 1024
            $findings = @(1..256 | ForEach-Object {
                    $i = $_
                    # Merge keys are seeded per group, not per finding, so the 256 raw records collapse
                    # into the 128 merged groups the vocabulary admits while every string sits at its
                    # own structural maximum.
                    $group = (($i - 1) % 128) + 1
                    @{
                        taskId = ('t{0:d3}' -f ((($i - 1) % 120) + 9))
                        severity = 'High'
                        title = (('title-{0:d3}-' -f $i) + ('t' * 146))
                        body = $body
                        action = $action
                        rootCause = (('root-{0:d3}-' -f $group) + ('r' * 247))
                        component = (('component-{0:d3}-' -f $group) + ('c' * 242))
                        references = @(1..8 | ForEach-Object { ("ref-{0:d3}-{1}-" -f $i, $_) + ('f' * 246) })
                    }
                })
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks $resultTasks -Findings $findings -InvocationBudget 128
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run

            $inputPath = Join-Path $runDir 'review-result.input.json'
            (Get-Item -LiteralPath $inputPath).Length |
                Should -BeGreaterThan ([int]$script:limits.maxEnvelopeBytes) -Because 'the fixture must actually be over the cap'
            # Structurally valid: only the byte budget rejects it.
            (Test-ReviewSchema -Json ([System.IO.File]::ReadAllText($inputPath)) -SchemaName 'review-run.schema.json') | Should -BeTrue

            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 3 -Because 'an over-cap envelope is terminal admission, not a retryable failure'
            $r.State | Should -Be 'admission'
            ($r.Diagnostics -join ' ') | Should -Match 'over the 2097152 budget'

            Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
            (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) | Should -BeNullOrEmpty
            Get-ReviewRunState -RunDir $runDir | Should -Be 'admission'
            Test-Path -LiteralPath $inputPath | Should -BeFalse -Because 'a rejected input is destroyed, not left in a committed directory'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard rejects a structurally valid run that merges into more than the vocabulary''s 128 groups with exit 2 before it renders anything' {
        # `maxMergedFindings` is a property of the *merged* set, so no single-document keyword can
        # count it: 256 raw findings are structurally legal and may collapse into anything between one
        # group and 256. The semantic layer decides it with the renderer's own grouping key — including
        # its fallbacks — so 129 groups is exit 2 before canonicalization, rendering or any write, and
        # never an over-budget render or a silently reduced report.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            # Exactly at the cap: 128 distinct merge keys is admitted and publishes.
            $atCap = @(1..[int]$script:limits.maxMergedFindings | ForEach-Object {
                    @{ taskId = 'security-m1'; severity = 'Low'; title = ('finding {0}' -f $_); body = 'b'; rootCause = ('root-{0:d3}' -f $_); component = 'c' }
                })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object (New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $atCap)
            $ok = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $ok.ExitCode | Should -Be 0 -Because 'the declared maximum is admitted, not rejected'
            @((ConvertTo-ReviewProjection -Run (Get-Content -LiteralPath (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) -Raw | ConvertFrom-Json -AsHashtable -Depth 40)).Findings).Count |
                Should -Be ([int]$script:limits.maxMergedFindings)
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            # One group over the cap, and the last two use the contract's fallbacks rather than an
            # explicit rootCause/component, so the count is only right if the semantic layer applies
            # the same defaulting the renderer does.
            $overCap = @(1..([int]$script:limits.maxMergedFindings - 1) | ForEach-Object {
                    @{ taskId = 'security-m1'; severity = 'Low'; title = ('finding {0}' -f $_); body = 'b'; rootCause = ('root-{0:d3}' -f $_); component = 'c' }
                })
            $overCap += @{ taskId = 'security-m1'; severity = 'Low'; title = 'defaulted root cause'; body = 'b'; references = @('src/z.ps1') }
            $overCap += @{ taskId = 'security-m1'; severity = 'Low'; title = 'another defaulted root cause'; body = 'b'; references = @('src/y.ps1') }
            $over = New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $overCap
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $over

            # Structurally valid: 129 findings is well inside the 256 the schema admits.
            $inputPath = Join-Path $runDir 'review-result.input.json'
            (Test-ReviewSchema -Json ([System.IO.File]::ReadAllText($inputPath)) -SchemaName 'review-run.schema.json') |
                Should -BeTrue -Because 'only the semantic layer can decide the merged maximum'

            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2 -Because 'over the merged maximum is invalid input, not an admission and not a failure'
            $r.State | Should -Be 'invalid'
            ($r.Diagnostics -join ' ') | Should -Match 'merge into 129 groups, over the 128 merged-finding maximum'

            # Nothing was rendered or written: the run is still exactly frozen.
            Get-ReviewRunState -RunDir $runDir | Should -Be 'frozen'
            (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) | Should -BeNullOrEmpty
            (Get-ReviewRunArtifact -RunDir $runDir -Role summary) | Should -BeNullOrEmpty
            (Get-ReviewRunArtifact -RunDir $runDir -Role full) | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $runDir '.review-run.admission.json') | Should -BeFalse
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard counts the merged maximum on the canonical reference order the renderer publishes, not the raw order the caller wrote' {
        # The cap is only a cap if the two callers of the grouping key count the *same* groups.
        # Canonicalization sorts `references` ordinally, so the renderer never sees the caller's array
        # order — but semantic validation runs on the raw document, and taking the component fallback
        # from `references[0]` of each gave the two a different component for the same finding. A run
        # whose raw arrays all lead with one shared reference therefore counted 65 groups, passed the
        # 128 maximum, and then rendered 130. The key is order-invariant (canonical text, ordinal sort,
        # then the first non-blank reference), so validation counts exactly what publication renders.
        function Script:New-ReferencePair {
            # One pair sharing a rootCause: the same leading reference in raw order, different first
            # references once the array is canonically sorted.
            param([int]$Index)
            $root = ('root-{0:d3}' -f $Index)
            return @(
                @{ taskId = 'security-m1'; severity = 'Low'; title = ('finding {0}a' -f $Index); body = 'b'; rootCause = $root
                    references = @(('zzz-shared-{0:d3}' -f $Index), ('aaa-{0:d3}-1' -f $Index))
                }
                @{ taskId = 'security-m1'; severity = 'Low'; title = ('finding {0}b' -f $Index); body = 'b'; rootCause = $root
                    references = @(('zzz-shared-{0:d3}' -f $Index), ('aaa-{0:d3}-2' -f $Index))
                }
            )
        }

        # 130 findings in 65 pairs: 65 keys by raw order, 130 by canonical order. Rejected at exit 2.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            $overCap = @(1..65 | ForEach-Object { New-ReferencePair -Index $_ })
            @($overCap).Count | Should -Be 130
            # The reproduction shape: leading with one shared reference is what used to hide 65 groups.
            @(@($overCap | ForEach-Object { @($_.references)[0] }) | Sort-Object -Unique).Count | Should -Be 65
            # The key itself is now order-invariant, so the raw document already counts 130.
            @(@($overCap | ForEach-Object { Get-ReviewMergeKey -Finding $_ }) | Sort-Object -Unique).Count | Should -Be 130

            Set-ReviewHandshake -RunDir $runDir -Kind result -Object (New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $overCap)
            $inputPath = Join-Path $runDir 'review-result.input.json'
            (Test-ReviewSchema -Json ([System.IO.File]::ReadAllText($inputPath)) -SchemaName 'review-run.schema.json') |
                Should -BeTrue -Because 'only the semantic layer can decide the merged maximum'

            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2 -Because 'the renderer would publish 130 groups, so 130 is what the cap must count'
            $r.State | Should -Be 'invalid'
            ($r.Diagnostics -join ' ') | Should -Match 'merge into 130 groups, over the 128 merged-finding maximum'
            Get-ReviewRunState -RunDir $runDir | Should -Be 'frozen'
            (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) | Should -BeNullOrEmpty
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # The at-cap equivalent of the same shape: 64 pairs publish and render exactly 128 groups.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            $atCap = @(1..64 | ForEach-Object { New-ReferencePair -Index $_ })
            @($atCap).Count | Should -Be 128
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object (New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $atCap)

            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $canonical = Get-Content -LiteralPath (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) -Raw | ConvertFrom-Json -AsHashtable -Depth 40
            @((ConvertTo-ReviewProjection -Run $canonical).Findings).Count |
                Should -Be 128 -Because 'the admitted count is the count the renderer publishes'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # The inverse, which the same drift caused: raw order counted 129 where the renderer merges 128,
        # so a legal run was falsely rejected. It must publish, and render 128.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            $inverse = @(1..127 | ForEach-Object {
                    @{ taskId = 'security-m1'; severity = 'Low'; title = ('solo {0}' -f $_); body = 'b'; rootCause = ('solo-{0:d3}' -f $_); component = 'c' }
                })
            # One merged pair whose reference arrays differ only in order: one group, not two.
            $inverse += @{ taskId = 'security-m1'; severity = 'Low'; title = 'same group a'; body = 'b'; rootCause = 'shared'; references = @('b-ref', 'a-ref') }
            $inverse += @{ taskId = 'security-m1'; severity = 'Low'; title = 'same group b'; body = 'b'; rootCause = 'shared'; references = @('a-ref', 'b-ref') }
            @($inverse).Count | Should -Be 129

            Set-ReviewHandshake -RunDir $runDir -Kind result -Object (New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $inverse)
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 0 -Because '128 rendered groups is at the cap, not over it'
            $canonical = Get-Content -LiteralPath (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) -Raw | ConvertFrom-Json -AsHashtable -Depth 40
            @((ConvertTo-ReviewProjection -Run $canonical).Findings).Count | Should -Be 128
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard keeps full model attribution and correct unanimity when a schema-valid model name carries a control character' {
        # A model is `type: string` with a length bound and no character class, so `U+0001` inside one
        # is schema-valid untrusted input. Packing the model into a delimited sort key and reading it
        # back by the *last* delimiter truncated it to whatever followed the control character: the
        # Models cell named a model nobody dispatched, and the truncated name no longer matched the
        # roster, so unanimous agreement silently stopped elevating.
        $hostileModel = "model-a$([char]1)x"
        $tasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = $hostileModel }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b' }
        )
        $resultTasks = @(
            @{ taskId = 'security-m1'; concern = 'security'; model = $hostileModel; outcome = 'completed' }
            @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
        )
        $findings = @(
            @{ taskId = 'security-m1'; severity = 'Medium'; title = 'Both models saw it'; body = 'first'; rootCause = 'shared'; component = 'src/a.ps1' }
            @{ taskId = 'security-m2'; severity = 'Medium'; title = 'Both models saw it too'; body = 'second'; rootCause = 'shared'; component = 'src/a.ps1' }
        )

        $case = New-PublishedRun -Tasks $tasks -ResultTasks $resultTasks -Findings $findings -Roster @($hostileModel, 'model-b')
        try {
            $case.Result.ExitCode | Should -Be 0

            # Canonical JSON is lossless: the control character survives exactly as it arrived.
            $canonical = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical))) |
                ConvertFrom-Json -AsHashtable -Depth 40
            @($canonical.roster) | Should -Contain $hostileModel

            $entry = @((ConvertTo-ReviewProjection -Run $canonical).Findings)[0]
            @($entry.Models).Count | Should -Be 2
            $entry.Models | Should -Contain $hostileModel -Because 'attribution keeps the whole model name, never a substring of a packed key'
            $entry.Models | Should -Not -Contain 'x'
            $entry.Elevated | Should -BeTrue -Because 'every dispatched model reported it, control character or not'
            $entry.Severity | Should -Be 'High' -Because 'unanimous agreement elevates one rank from Medium'

            # The rendered views name the model in full and emit no raw C0 control byte.
            $summary = Get-ReviewRunSummaryText -RunDir $case.RunDir
            $full = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role full)))
            foreach ($text in @($summary, $full)) {
                @($text.ToCharArray() | Where-Object { [int]$_ -lt 0x20 -and $_ -ne "`n" }).Count |
                    Should -Be 0 -Because 'a rendered view never emits a raw C0 control character'
                $text | Should -Not -Match ([regex]::Escape($hostileModel))
            }
            # Replaced deterministically by the Unicode Control Picture for U+0001, so the whole name
            # is still readable and still distinguishable from any other model.
            $full | Should -Match ([regex]::Escape("model-a$([char]0x2401)x · model-b"))
            $full | Should -Match 'elevated — flagged under every declared model label'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard allows only exact synthetic shapes, not any token that merely contains a marker word' {
        # The allow list used to match a substring, so a live credential whose body happened to contain
        # `example` or `redacted` was waved through. Only the published AWS documentation key and a
        # provider prefix whose whole body is a mask or an exact marker repetition are allowed.
        $corpus = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/review-run/secrets/allow-block-corpus.json') -Raw | ConvertFrom-Json -Depth 20
        foreach ($case in $corpus.cases) {
            $token = Build-ReviewSecretToken -Segments $case.segments
            $blocked = @(Test-ReviewValueForSecret -Value "reviewer wrote $token here").Count -gt 0
            $blocked | Should -Be ($case.expected -eq 'block') -Because "corpus case '$($case.id)' must still be $($case.expected)ed"
        }

        # A real-looking token that merely embeds a marker word is a secret, not a placeholder.
        $prefix = 'gh' + 'p_'
        foreach ($token in @(
                ($prefix + 'EXAMPLE' + 'aZ9bY8cX7dW6eV5fU4gT3hS2iR1jQ0'),
                ($prefix + 'redacted' + '0123456789abcdefghijklmnopqr'),
                ('AK' + 'IA' + 'EXAMPLE123456789'))) {
            @(Test-ReviewValueForSecret -Value "reviewer wrote $token here").Count |
                Should -BeGreaterThan 0 -Because 'a marker word inside an otherwise live-looking body is not an allow rule'
        }

        # And the exact synthetic shapes stay allowed.
        foreach ($token in @(($prefix + ('X' * 36)), ($prefix + ('REDACTED' * 4) + 'REDA'), 'AKIAIOSFODNN7EXAMPLE')) {
            @(Test-ReviewValueForSecret -Value "reviewer wrote $token here").Count |
                Should -Be 0 -Because 'a fully masked or fully synthetic body is a known non-secret'
        }
    }

    It 'test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard blocks a credential shape before acceptance and reports only its redacted type and location' {
        # The token is reconstructed at runtime from the versioned corpus so no complete token is
        # committed; a GitHub PAT shape inside a reviewer body must fail closed.
        $corpus = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/review-run/secrets/allow-block-corpus.json') -Raw | ConvertFrom-Json -Depth 20
        $blockCase = @($corpus.cases | Where-Object { $_.id -eq 'github-pat-classic' })[0]
        $token = Build-ReviewSecretToken -Segments $blockCase.segments

        $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
        $resultTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
        $findings = @(@{ taskId = 'security-m1'; severity = 'Critical'; title = 'Hardcoded token'; body = "The reviewer quoted the token $token in the diff."; rootCause = 'secret'; component = 'src/a.ps1' })

        $case = New-PublishedRun -Tasks $tasks -ResultTasks $resultTasks -Findings $findings -Roster @('model-a')
        try {
            $case.Result.ExitCode | Should -Be 2
            $case.Result.State | Should -Be 'invalid'
            # Nothing lossless is written, and the run stays frozen.
            (Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical) | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') | Should -BeFalse
            # Only the redacted type and location are reported, never the value.
            $case.Result.Message | Should -Match 'credential'
            ($case.Result.Diagnostics -join ' ') | Should -Match 'github-pat-classic at finding:1/body'
            ($case.Result.Diagnostics -join ' ') | Should -Not -Match ([regex]::Escape($token))
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }
}
