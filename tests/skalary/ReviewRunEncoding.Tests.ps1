#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-11/D15/D17, step 1.2. Encoding, canonicalization, exits and diagnostics are exact:
# canonical JSON and Markdown are UTF-8 without BOM, LF, NFC and hashed after canonicalization; every
# terminal path prints exactly one bounded terminal-status object; task diagnostics, stdout and stderr
# have fixed byte ceilings; error precedence is parse/schema -> semantic -> admission -> publication;
# and the publication lock has a five-second contract.
Describe 'review report encoding, exit, diagnostic and lock contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking
        $script:cli = Join-Path $script:repoRoot 'scripts/skalary/Build-ReviewReport.ps1'
        # Child-process stdout is captured through a file in the gitignored scratch store, never a
        # system temp path.
        $script:cliScratch = Join-Path $script:repoRoot '.github/.skalary/test-scratch/cli.out'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $script:cliScratch) -Force)
        $script:limits = Get-ReviewLimits

        function Script:New-Frozen {
            param([object[]]$ResultTasks, [object[]]$Findings = @(), [string[]]$Roster = @('model-a'))

            $scratch = New-ReviewScratchRoot
            $runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$runId"
            $tasks = @($ResultTasks | ForEach-Object { @{ taskId = $_.taskId; concern = $_.concern; model = $_.model } })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $runId -Roster $Roster -Tasks $tasks)
            [void](Invoke-ReviewFreeze -RunId $runId -RepoRoot $scratch)
            $run = New-ReviewTestRun -RunId $runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster $Roster -Tasks $ResultTasks -Findings $Findings
            return [pscustomobject]@{ Scratch = $scratch; RunDir = $runDir; RunId = $runId; Run = $run }
        }

        function Script:Invoke-ReviewCli {
            <#
            .SYNOPSIS
                Runs the installed CLI shape as a child process, with a hard timeout so a run that
                cannot terminate fails the test instead of hanging the suite.
            #>
            param(
                [Parameter(Mandatory)][string[]]$Arguments,
                [int]$TimeoutSeconds = 0
            )

            if ($TimeoutSeconds -le 0) {
                $out = & pwsh -NoProfile -File $script:cli @Arguments 2>$null
                return [pscustomobject]@{ Stdout = ($out -join "`n"); ExitCode = $LASTEXITCODE; TimedOut = $false }
            }

            $stdoutPath = Join-Path ([System.IO.Path]::GetDirectoryName($script:cliScratch)) ([guid]::NewGuid().ToString('N') + '.out')
            $process = Start-Process -FilePath 'pwsh' -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath `
                -ArgumentList (@('-NoProfile', '-File', $script:cli) + $Arguments)
            $exited = $process.WaitForExit($TimeoutSeconds * 1000)
            if (-not $exited) {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
                return [pscustomobject]@{ Stdout = ''; ExitCode = $null; TimedOut = $true }
            }
            $stdout = $(if (Test-Path -LiteralPath $stdoutPath) { (Get-Content -LiteralPath $stdoutPath -Raw) } else { '' })
            Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Stdout = ([string]$stdout).TrimEnd("`r", "`n"); ExitCode = $process.ExitCode; TimedOut = $false }
        }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract writes canonical bytes as UTF-8 no BOM, LF, NFC and a digest taken after canonicalization, stable across shuffle' {
        $case = New-Frozen -ResultTasks @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
        ) -Findings @(
            # A decomposed accented title normalizes to NFC in the canonical bytes.
            @{ taskId = 'security-m1'; severity = 'High'; title = "Cafe`u{0301} finding"; body = 'b'; rootCause = 'r'; component = 'c' }
        )
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $case.RunId -RepoRoot $case.Scratch).ExitCode | Should -Be 0

            foreach ($role in @('canonical', 'summary', 'full', 'plan')) {
                $path = Get-ReviewRunArtifact -RunDir $case.RunDir -Role $role
                $path | Should -Not -BeNullOrEmpty -Because "the $role generation must exist"
                $name = Split-Path -Leaf $path
                $bytes = [System.IO.File]::ReadAllBytes($path)
                @($bytes[0], $bytes[1], $bytes[2]) -join ',' | Should -Not -Be '239,187,191' -Because "$name must carry no BOM"
                (@($bytes | Where-Object { $_ -eq 13 })).Count | Should -Be 0 -Because "$name must be LF-only"
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                $text.IsNormalized([System.Text.NormalizationForm]::FormC) | Should -BeTrue -Because "$name must be NFC"
                # The name is the content address of exactly these bytes.
                $name | Should -Be ("$(@{ canonical = 'review-run'; summary = 'review-summary'; full = 'review-full'; plan = 'review-plan' }[$role])." +
                    (Get-ReviewDigest -Bytes $bytes).Substring(7) + $(if ($role -in @('canonical', 'plan')) { '.json' } else { '.md' }))
            }

            # runDigest is the digest of the canonical bytes as written.
            $canonicalBytes = [System.IO.File]::ReadAllBytes((Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical))
            $manifest = Get-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') -Raw | ConvertFrom-Json -Depth 20
            [string]$manifest.runDigest | Should -Be (Get-ReviewDigest -Bytes $canonicalBytes)

            # The digest does not depend on raw property or array order.
            $shuffled = [ordered]@{}
            foreach ($k in @($case.Run.Keys | Sort-Object -Descending)) { $shuffled[$k] = $case.Run[$k] }
            $shuffledParsed = ($shuffled | ConvertTo-Json -Depth 40) | ConvertFrom-Json -AsHashtable -Depth 40
            $shuffledCanonical = ConvertTo-ReviewCanonicalJson -Node $shuffledParsed
            (Get-ReviewDigest -Bytes ([System.Text.Encoding]::UTF8.GetBytes($shuffledCanonical))) |
                Should -Be ([string]$manifest.runDigest)
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract prints exactly one bounded, schema-valid terminal-status object on every CLI exit' {
        $runId = [guid]::NewGuid().ToString().ToLowerInvariant()
        $runDir = Join-Path $script:repoRoot ".github/.skalary/review-runs/$runId"
        try {
            # Clean freeze then clean publish through the installed CLI shape.
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            $freeze = Invoke-ReviewCli -Arguments @('-Mode', 'Freeze', '-RunId', $runId)
            $freeze.ExitCode | Should -Be 0

            foreach ($stdout in @($freeze.Stdout)) {
                @($stdout -split "`n" | Where-Object { $_.Trim() }).Count | Should -Be 1 -Because 'exactly one terminal-status object'
                [System.Text.Encoding]::UTF8.GetByteCount($stdout) | Should -BeLessOrEqual ([int]$script:limits.maxTerminalStatusBytes)
                (Test-ReviewSchema -Json $stdout -SchemaName 'terminal-status.schema.json') | Should -BeTrue
                $obj = $stdout | ConvertFrom-Json
                $obj.mode | Should -Be 'freeze'; $obj.exitCode | Should -Be 0; $obj.state | Should -Be 'clean'; $obj.runId | Should -Be $runId
            }

            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            $run = New-ReviewTestRun -RunId $runId -PlanDigest $digest -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            $publish = Invoke-ReviewCli -Arguments @('-Mode', 'Publish', '-RunId', $runId)
            $publish.ExitCode | Should -Be 0
            (Test-ReviewSchema -Json $publish.Stdout -SchemaName 'terminal-status.schema.json') | Should -BeTrue
            ($publish.Stdout | ConvertFrom-Json).state | Should -Be 'clean'

            # An invalid input still emits one bounded status, exit 2.
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object @{ schema = 'skalary/review-run@1'; not = 'valid' }
            $invalid = Invoke-ReviewCli -Arguments @('-Mode', 'Publish', '-RunId', $runId)
            $invalid.ExitCode | Should -Be 2
            (Test-ReviewSchema -Json $invalid.Stdout -SchemaName 'terminal-status.schema.json') | Should -BeTrue
        }
        finally { Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract enforces the 2 KiB task diagnostic budget and drops status diagnostics to fit 8 KiB' {
        # A task diagnostic within the 2048 code-unit maxLength but over 2048 UTF-8 bytes (accented
        # characters are two bytes each) is a semantic rejection the schema cannot see.
        $case = New-Frozen -ResultTasks @(
            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'perf-m1'; concern = 'performance'; model = 'model-a'; outcome = 'failed'; diagnostic = ("`u{00e9}" * 2000) }
        )
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            $r = Invoke-ReviewPublish -RunId $case.RunId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            ($r.Diagnostics -join ' ') | Should -Match '2048 UTF-8 bytes'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }

        # The emitter keeps the object at most 8 KiB by dropping diagnostics from the end.
        $many = @(1..64 | ForEach-Object { 'diagnostic line number ' + $_ + ' ' + ('y' * 400) })
        $json = Get-ReviewTerminalStatusJson -Mode publish -ExitCode 2 -State invalid -Message 'many diagnostics' -RunId '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35' -Diagnostic $many
        [System.Text.Encoding]::UTF8.GetByteCount($json) + 1 | Should -BeLessOrEqual ([int]$script:limits.maxTerminalStatusBytes)
        (Test-ReviewSchema -Json $json -SchemaName 'terminal-status.schema.json') | Should -BeTrue
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract applies error precedence: parse/schema before semantic before admission' {
        # Schema failure plus a semantic problem: the schema error wins (exit 2), and nothing is rendered.
        $case = New-Frozen -ResultTasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
        try {
            $bad = Copy-ReviewMap -Map $case.Run
            $bad['findings'] = @(@{ taskId = 'nonexistent'; severity = 'NotASeverity'; title = 'x' })  # schema-invalid severity AND dangling task
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $bad
            $r = Invoke-ReviewPublish -RunId $case.RunId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            $r.Message | Should -Match 'schema' -Because 'schema failure precedes semantic'
            (Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical) | Should -BeNullOrEmpty
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract produces identical canonical bytes and digests under cs-CZ, tr-TR, de-DE and the invariant culture' {
        # Object key order decides the canonical bytes, so the comparer that orders keys must be
        # ordinal. A culture-sensitive sort gives a Turkish or Czech host a different key order — and
        # therefore a different digest — for the same document, which would silently split the
        # authority every view is bound to.
        $envelope = [ordered]@{
            schema = 'skalary/review-run@1'
            runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            reviewType = 'code'
            scope = 'İstanbul, chřtán, straße — 3 changed files'
            roster = @('model-I', 'model-i', 'model-ch', 'model-h', 'model-Z', 'model-a')
            invocationBudget = 6
            planDigest = 'sha256:' + ('0' * 64)
            tasks = @(
                @{ taskId = 'ia-m1'; concern = 'ia'; model = 'model-I'; outcome = 'completed' }
                @{ taskId = 'ib-m1'; concern = 'ib'; model = 'model-i'; outcome = 'completed' }
            )
            findings = @(
                @{ taskId = 'ia-m1'; severity = 'High'; title = 'Iı title'; body = 'İi body'; action = 'ACTION'; rootCause = 'ROOT'; component = 'CH'; references = @('Zebra', 'chalupa', 'Ibis', 'ibis') }
                @{ taskId = 'ib-m1'; severity = 'Low'; title = 'ı title'; body = 'ß body'; rootCause = 'root'; component = 'ch'; references = @('Åland', 'aland') }
            )
        }
        $parsed = ($envelope | ConvertTo-Json -Depth 40) | ConvertFrom-Json -AsHashtable -Depth 40

        $results = [ordered]@{}
        $original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            foreach ($culture in @('', 'cs-CZ', 'tr-TR', 'de-DE')) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
                $canonical = ConvertTo-ReviewCanonicalJson -Node $parsed
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
                $name = $(if ($culture) { $culture } else { 'invariant' })
                $results[$name] = [pscustomobject]@{
                    Digest = Get-ReviewDigest -Bytes $bytes
                    Bytes = $bytes
                    Summary = Get-ReviewRunSummaryView -Run ($canonical | ConvertFrom-Json -AsHashtable -Depth 40)
                }
            }
        }
        finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $original }

        $reference = $results['invariant']
        foreach ($name in @('cs-CZ', 'tr-TR', 'de-DE')) {
            $results[$name].Digest | Should -Be $reference.Digest -Because "canonical bytes must not depend on $name"
            (Compare-Object -ReferenceObject $results[$name].Bytes -DifferenceObject $reference.Bytes -SyncWindow 0) |
                Should -BeNullOrEmpty -Because "the canonical bytes must be identical under $name"
            $results[$name].Summary | Should -Be $reference.Summary -Because "the rendered summary must not depend on $name"
        }

        # And the key order really is ordinal, with no case-folding: uppercase keys sort before
        # lowercase ones, and a case-distinct member is never absorbed into its neighbour.
        $mixed = '{"b":1,"A":2,"a":3,"B":4}' | ConvertFrom-Json -AsHashtable
        (ConvertTo-ReviewCanonicalJson -Node $mixed) | Should -Be ("{`"A`":2,`"B`":4,`"a`":3,`"b`":1}`n")
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract gives semantically equivalent envelopes identical canonical bytes, one digest and an idempotent replay' {
        # Canonicalization is what makes "the same document" a decidable question. Three differences a
        # JSON encoder may introduce without changing the document at all — the line ending inside a
        # string, the Unicode composition of a grapheme, and the `1.0` spelling of an integer draft
        # 2020-12 accepts wherever it accepts `1` — used to survive into the canonical bytes and give
        # the same review two digests, two content addresses and two publications.
        $composed = [ordered]@{
            schema = 'skalary/review-run@1'
            runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            reviewType = 'code'
            scope = 'Café — 1 changed file'
            roster = @('model-a')
            invocationBudget = 4
            planDigest = 'sha256:' + ('0' * 64)
            tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            findings = @(@{ taskId = 'security-m1'; severity = 'High'; title = 'Café finding'; body = "first line`nsecond line"; rootCause = 'r'; component = 'c' })
        }
        $composedJson = ($composed | ConvertTo-Json -Depth 40 -Compress)
        # The same document as a CRLF-authored, NFD-composed, `1.0`-spelling editor would write it.
        $equivalentJson = $composedJson.Replace('"invocationBudget":4', '"invocationBudget":4.0')
        $equivalentJson = $equivalentJson.Replace('first line\nsecond line', 'first line\r\nsecond line')
        $equivalentJson = $equivalentJson.Replace("Caf\u00e9", "Cafe\u0301")
        $equivalentJson | Should -Not -Be $composedJson -Because 'the two inputs really are byte-different'

        $left = ConvertTo-ReviewCanonicalJson -Node ($composedJson | ConvertFrom-Json -AsHashtable -Depth 40)
        $right = ConvertTo-ReviewCanonicalJson -Node ($equivalentJson | ConvertFrom-Json -AsHashtable -Depth 40)
        $left | Should -Be $right -Because 'equivalent inputs canonicalize to the same text'
        (Compare-Object -ReferenceObject ([System.Text.Encoding]::UTF8.GetBytes($left)) -DifferenceObject ([System.Text.Encoding]::UTF8.GetBytes($right)) -SyncWindow 0) |
            Should -BeNullOrEmpty -Because 'equivalent inputs canonicalize to identical bytes'
        (Get-ReviewDigest -Bytes ([System.Text.Encoding]::UTF8.GetBytes($right))) |
            Should -Be (Get-ReviewDigest -Bytes ([System.Text.Encoding]::UTF8.GetBytes($left)))

        $left | Should -Match '"invocationBudget":4[,}]' -Because 'a schema-valid integral value is written as an integer'
        $left | Should -Not -Match '4\.0'
        $left | Should -Not -Match "`r"
        ([System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($left))).IsNormalized([System.Text.NormalizationForm]::FormC) |
            Should -BeTrue

        # Canonicalization is idempotent: re-canonicalizing the canonical form changes nothing.
        (ConvertTo-ReviewCanonicalJson -Node ($left | ConvertFrom-Json -AsHashtable -Depth 40)) | Should -Be $left

        # And the whole lifecycle agrees: freezing then publishing one spelling, then replaying the
        # other, is an idempotent replay rather than a second, conflicting generation.
        $scratch = New-ReviewScratchRoot
        try {
            $runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$runId"
            $planTasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $plan = New-ReviewTestPlan -RunId $runId -Roster @('model-a') -Tasks $planTasks -InvocationBudget 4 -Scope 'Café — 1 changed file'
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            (Invoke-ReviewFreeze -RunId $runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $planFile = Get-ReviewRunArtifact -RunDir $runDir -Role plan

            # The equivalent plan spelling is the same frozen plan, so the replay is idempotent and no
            # second generation appears.
            $planJson = ($plan | ConvertTo-Json -Depth 40 -Compress).Replace('"invocationBudget":4', '"invocationBudget":4.0')
            $planJson = $planJson.Replace("Caf\u00e9", "Cafe\u0301")
            $tmp = Join-Path $runDir '.review-plan.input.tmp'
            [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::UTF8.GetBytes($planJson))
            [System.IO.File]::Move($tmp, (Join-Path $runDir 'review-plan.input.json'), $true)
            $replay = Invoke-ReviewFreeze -RunId $runId -RepoRoot $scratch
            $replay.ExitCode | Should -Be 0 -Because 'an equivalent plan is the same plan'
            $replay.Message | Should -Match 'idempotent'
            @(Get-ReviewFrozenPlanFile -RunDir $runDir).Count | Should -Be 1
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -Be $planFile

            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            $run = New-ReviewTestRun -RunId $runId -PlanDigest $digest -Roster @('model-a') -InvocationBudget 4 -Scope 'Café — 1 changed file' `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(@{ taskId = 'security-m1'; severity = 'High'; title = 'Café finding'; body = "first line`nsecond line"; rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $canonicalFile = Get-ReviewRunArtifact -RunDir $runDir -Role canonical
            $manifestBefore = Get-Content -LiteralPath (Join-Path $runDir 'review-run.manifest.json') -Raw

            $runJson = ($run | ConvertTo-Json -Depth 40 -Compress).Replace('"invocationBudget":4', '"invocationBudget":4.0')
            $runJson = $runJson.Replace('first line\nsecond line', 'first line\r\nsecond line')
            $runJson = $runJson.Replace("Caf\u00e9", "Cafe\u0301")
            $tmp = Join-Path $runDir '.review-result.input.tmp'
            [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::UTF8.GetBytes($runJson))
            [System.IO.File]::Move($tmp, (Join-Path $runDir 'review-result.input.json'), $true)
            $replayPublish = Invoke-ReviewPublish -RunId $runId -RepoRoot $scratch
            $replayPublish.ExitCode | Should -Be 0 -Because 'an equivalent result is the same result, not a conflicting one'
            $replayPublish.Message | Should -Match 'idempotent'
            (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) | Should -Be $canonicalFile
            @(Get-ChildItem -LiteralPath $runDir -File -Force | Where-Object { $_.Name -cmatch '^review-run\.[0-9a-f]{64}\.json$' }).Count | Should -Be 1
            (Get-Content -LiteralPath (Join-Path $runDir 'review-run.manifest.json') -Raw) | Should -Be $manifestBefore
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # The committed corpus is still canonical under this rule: its plan bytes are exactly what
        # canonicalization produces, so the digest the corpus envelope is bound to still holds.
        $corpusRoot = Join-Path $PSScriptRoot 'fixtures/review-run/corpus'
        $corpusPlanBytes = [System.IO.File]::ReadAllBytes((Join-Path $corpusRoot 'gate-10.7-cr-branch.plan.json'))
        $corpusPlan = [System.Text.Encoding]::UTF8.GetString($corpusPlanBytes) | ConvertFrom-Json -AsHashtable -Depth 40
        $corpusCanonical = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-ReviewCanonicalJson -Node $corpusPlan))
        (Compare-Object -ReferenceObject $corpusCanonical -DifferenceObject $corpusPlanBytes -SyncWindow 0) |
            Should -BeNullOrEmpty -Because 'the committed corpus plan is already the canonical form'
        $corpusRun = Get-Content -LiteralPath (Join-Path $corpusRoot 'gate-10.7-cr-branch.run.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 40
        [string]$corpusRun['planDigest'] | Should -Be (Get-ReviewDigest -Bytes $corpusCanonical) -Because 'the committed corpus digest survives canonicalization unchanged'
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract bounds an oversized invalid run id to one schema-valid exit-2 status that never echoes it' {
        # A caller-supplied run id is unbounded text. Echoing a 9 KiB one both breaks the 8 KiB stdout
        # budget — nothing else in the object can shrink far enough to compensate, so the emitter used
        # to spin forever — and violates the status schema, whose runId is a UUID.
        $oversized = 'z' * 9500
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ReviewCli -Arguments @('-Mode', 'Freeze', '-RunId', $oversized) -TimeoutSeconds 60
        $sw.Stop()
        $result.TimedOut | Should -BeFalse -Because 'the terminal-status emitter must terminate, not shrink forever'
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 60
        $result.ExitCode | Should -Be 2

        @($result.Stdout -split "`n" | Where-Object { $_.Trim() }).Count | Should -Be 1
        [System.Text.Encoding]::UTF8.GetByteCount($result.Stdout) | Should -BeLessOrEqual ([int]$script:limits.maxTerminalStatusBytes)
        (Test-ReviewSchema -Json $result.Stdout -SchemaName 'terminal-status.schema.json') | Should -BeTrue
        $result.Stdout | Should -Not -Match 'zzzzzzzz' -Because 'a rejected id is never echoed back'
        $status = $result.Stdout | ConvertFrom-Json
        $status.runIdRejected | Should -BeTrue
        $status.state | Should -Be 'invalid'
        [bool]($status.PSObject.Properties.Name -contains 'runId') | Should -BeFalse

        # The in-process emitter is bounded the same way, with every diagnostic dropped if it must be.
        $json = Get-ReviewTerminalStatusJson -Mode publish -ExitCode 2 -State invalid -Message ('m' * 4000) `
            -RunId $oversized -Diagnostic @(1..16 | ForEach-Object { 'd' * 512 })
        [System.Text.Encoding]::UTF8.GetByteCount($json) + 1 | Should -BeLessOrEqual ([int]$script:limits.maxTerminalStatusBytes)
        (Test-ReviewSchema -Json $json -SchemaName 'terminal-status.schema.json') | Should -BeTrue

        # Both emitters are exported, so they are reachable from callers no CLI path controls. The
        # schema binds a rejected id to exactly one shape — exit 2, state invalid — so any other
        # exit/state offered with a rejected id is normalized to it rather than serialized into an
        # object that fails its own schema, and the exit code the writer returns is the one the object
        # states.
        foreach ($case in @(
                @{ Exit = 4; State = 'failed' },
                @{ Exit = 3; State = 'admission' },
                @{ Exit = 5; State = 'degraded' },
                @{ Exit = 0; State = 'clean' })) {
            foreach ($mode in @('freeze', 'publish')) {
                $rejected = Get-ReviewTerminalStatusJson -Mode $mode -ExitCode $case.Exit -State $case.State `
                    -Message 'rejected id' -RunId 'NOT-A-UUID' -Diagnostic @('one diagnostic')
                (Test-ReviewSchema -Json $rejected -SchemaName 'terminal-status.schema.json') |
                    Should -BeTrue -Because "$mode exit $($case.Exit) with a rejected id must still be schema-valid"
                $status = $rejected | ConvertFrom-Json
                $status.exitCode | Should -Be 2
                $status.state | Should -Be 'invalid'
                $status.runIdRejected | Should -BeTrue
                [bool]($status.PSObject.Properties.Name -contains 'runId') | Should -BeFalse
                $rejected | Should -Not -Match 'NOT-A-UUID'
            }
        }

        # A valid id is untouched: normalization is about the rejected shape, not about exit codes.
        $valid = Get-ReviewTerminalStatusJson -Mode publish -ExitCode 4 -State failed -Message 'lock' -RunId '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        (Test-ReviewSchema -Json $valid -SchemaName 'terminal-status.schema.json') | Should -BeTrue
        ($valid | ConvertFrom-Json).exitCode | Should -Be 4

        # The writer returns what it printed. Its stdout is captured so the suite's own output stays
        # one stream.
        $captured = Join-Path ([System.IO.Path]::GetDirectoryName($script:cliScratch)) ([guid]::NewGuid().ToString('N') + '.status')
        $writerScript = Join-Path ([System.IO.Path]::GetDirectoryName($script:cliScratch)) ([guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Set-Content -LiteralPath $writerScript -Value @'
param([string]$ModulePath)
Import-Module $ModulePath -Force -DisableNameChecking
$code = Write-ReviewTerminalStatus -Mode publish -ExitCode 4 -State failed -Message 'rejected id' -RunId 'NOT-A-UUID'
exit $code
'@ -NoNewline
            $process = Start-Process -FilePath 'pwsh' -PassThru -NoNewWindow -RedirectStandardOutput $captured `
                -ArgumentList @('-NoProfile', '-File', $writerScript, '-ModulePath', (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1'))
            [void]$process.WaitForExit(60000)
            $process.ExitCode | Should -Be 2 -Because 'stdout and the process exit can never disagree'
            $printed = (Get-Content -LiteralPath $captured -Raw).TrimEnd("`r", "`n")
            (Test-ReviewSchema -Json $printed -SchemaName 'terminal-status.schema.json') | Should -BeTrue
            ($printed | ConvertFrom-Json).exitCode | Should -Be 2
        }
        finally {
            Remove-Item -LiteralPath $captured -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $writerScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract turns an unexpected CLI failure into an explicit exit 4 status instead of an unhandled error' {
        # The module bounds every expected failure itself, so the CLI guard exists for what it cannot
        # bound: a broken install. It must still be one terminal-status object, and it must say the
        # mode failed rather than pretend anything about the run.
        $broken = Join-Path $script:repoRoot '.github/.skalary/test-scratch' ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $broken -Force)
        try {
            # A copy of the CLI with no engine beside it: importing the module is what fails.
            Copy-Item -LiteralPath $script:cli -Destination (Join-Path $broken 'Build-ReviewReport.ps1')
            $runId = [guid]::NewGuid().ToString().ToLowerInvariant()
            $out = & pwsh -NoProfile -File (Join-Path $broken 'Build-ReviewReport.ps1') -Mode Freeze -RunId $runId 2>$null
            $exit = $LASTEXITCODE
            $stdout = ($out -join "`n")

            $exit | Should -Be 4
            @($stdout -split "`n" | Where-Object { $_.Trim() }).Count | Should -Be 1
            (Test-ReviewSchema -Json $stdout -SchemaName 'terminal-status.schema.json') | Should -BeTrue
            $status = $stdout | ConvertFrom-Json
            $status.exitCode | Should -Be 4
            $status.state | Should -Be 'failed'
            $status.mode | Should -Be 'freeze'
            $status.runId | Should -Be $runId
            @($status.diagnostics).Count | Should -BeGreaterThan 0 -Because 'the failure is named, not swallowed'
        }
        finally { Remove-Item -LiteralPath $broken -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'test:ReviewReport.EncodingExitDiagnosticAndLockContract holds a five-second publication lock and fails with exit 4 when it cannot be acquired' {
        # The production timeout is the vocabulary's five seconds.
        [int]$script:limits.lockTimeoutSeconds | Should -Be 5
        (Get-ReviewLockTimeoutSeconds) | Should -Be 5

        $case = New-Frozen -ResultTasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            # Hold the lock, lower the timeout so the proof is fast, and confirm publish fails with 4.
            $held = Enter-ReviewLock -RunDir $case.RunDir
            try {
                Set-ReviewRunLockTimeoutOverride -Seconds 0.3
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $r = Invoke-ReviewPublish -RunId $case.RunId -RepoRoot $case.Scratch
                $sw.Stop()
                $r.ExitCode | Should -Be 4
                $r.State | Should -Be 'failed'
                $sw.Elapsed.TotalSeconds | Should -BeLessThan 5 -Because 'the lowered timeout fires well before the production ceiling'
                # Prior authority preserved: still frozen, no manifest.
                Get-ReviewRunState -RunDir $case.RunDir | Should -Be 'frozen'
            }
            finally {
                Set-ReviewRunLockTimeoutOverride -Seconds $null
                Exit-ReviewLock -Lock $held
            }

            # The lock file itself is stable: releasing it never unlinks it, so a second process
            # cannot open a *different* inode at the same path and believe it holds the lock.
            Test-Path -LiteralPath (Join-Path $case.RunDir '.review-run.lock') | Should -BeTrue
            # With the lock free again, the same input publishes (retry after 4 succeeds).
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $case.RunId -RepoRoot $case.Scratch).ExitCode | Should -Be 0
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }
}
