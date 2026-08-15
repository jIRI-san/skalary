#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-6/D13/D19/D20/D21, step 1.2. The manifest is the sole publication commit point,
# replaced last; the bundled reader verifies it and every digest before emitting a summary; the state
# machine has closed transitions with a fixed exit for each; and a fault at any publication edge
# preserves prior authority and a retry succeeds. These tests pin all of that in-process through the
# module, which is where the deterministic fault seams live.
Describe 'review report manifest, reader and exit matrix' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking
        $script:runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'

        function Script:New-FrozenCase {
            param([string[]]$Outcomes = @('completed', 'failed'))

            $scratch = New-ReviewScratchRoot
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(); $resultTasks = @()
            for ($i = 0; $i -lt $Outcomes.Count; $i++) {
                $id = "c$($i)-m1"
                $tasks += @{ taskId = $id; concern = "concern$i"; model = 'model-a' }
                $t = @{ taskId = $id; concern = "concern$i"; model = 'model-a'; outcome = $Outcomes[$i] }
                if ($Outcomes[$i] -ne 'completed') { $t['diagnostic'] = "outcome $($Outcomes[$i])" }
                $resultTasks += $t
            }
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            [void](Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch)
            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks `
                -Findings @(@{ taskId = 'c0-m1'; severity = 'High'; title = 'One'; body = 'b'; rootCause = 'r'; component = 'c' })
            return [pscustomobject]@{ Scratch = $scratch; RunDir = $runDir; Run = $run }
        }
    }

    AfterEach { Clear-ReviewRunFaultSeam; Clear-ReviewPathItemProvider }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix commits the manifest last and reads it back verifying every digest' {
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5

            # The manifest names four confined files, each verified against its recorded digest/bytes.
            $verified = Read-ReviewManifest -RunDir $case.RunDir
            $verified.RunId | Should -Be $script:runId
            @($verified.Files.Keys | Sort-Object) | Should -Be @('canonical', 'full', 'plan', 'summary')

            # The reader emits either bounded view only after verifying the same complete manifest.
            $summary = Get-ReviewRunSummaryText -RunDir $case.RunDir
            $summary | Should -Match '(?m)^# Code Review — summary$'
            $full = Get-ReviewRunViewText -RunDir $case.RunDir -View Full
            $full | Should -Match '(?m)^# Code Review — full report$'
            $full | Should -Match '(?m)^## Tasks \(2\)$'
            $full | Should -Match '(?m)^### \[1\] One$'

            # Reader ignores files the manifest does not reference.
            Set-Content -LiteralPath (Join-Path $case.RunDir 'stray.md') -Value 'ignored'
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Not -Throw

            # A tampered generation file fails the digest check.
            $canonicalPath = Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical
            Add-Content -LiteralPath $canonicalPath -Value ' '
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Throw -ExpectedMessage '*mismatch*'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix is idempotent on identical replay and rejects changed reuse, publish-before-freeze and frozen mutation with exit 2' {
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            $first = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $first.ExitCode | Should -Be 5
            $manifestBytes = [System.IO.File]::ReadAllBytes((Join-Path $case.RunDir 'review-run.manifest.json'))

            # Identical replay: same run digest, idempotent, manifest byte-unchanged.
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            $replay = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $replay.ExitCode | Should -Be 5
            $replay.Message | Should -Match 'idempotent'
            [System.IO.File]::ReadAllBytes((Join-Path $case.RunDir 'review-run.manifest.json')) |
                Should -Be $manifestBytes

            # Changed input under a published run id: rejected, publication is immutable.
            $changed = Copy-ReviewMap -Map $case.Run
            $changed['findings'] = @(@{ taskId = 'c0-m1'; severity = 'Low'; title = 'Different'; body = 'x'; rootCause = 'r2'; component = 'c2' })
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $changed
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            [System.IO.File]::ReadAllBytes((Join-Path $case.RunDir 'review-run.manifest.json')) |
                Should -Be $manifestBytes -Because 'a rejected reuse must not disturb the published manifest'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }

        # Publish before Freeze.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest ('sha256:' + ('0' * 64)) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'c0-m1'; concern = 'concern0'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 2
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # Frozen mutation: the frozen plan file is edited after freeze, so it no longer matches the
        # digest in its own content-addressed name.
        $case2 = New-FrozenCase
        try {
            Add-Content -LiteralPath (Get-ReviewRunArtifact -RunDir $case2.RunDir -Role plan) -Value ' '
            Set-ReviewHandshake -RunDir $case2.RunDir -Kind result -Object $case2.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case2.Scratch).ExitCode | Should -Be 2
        }
        finally { Remove-ReviewScratchRoot -Path $case2.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix recovers from a fault at every publication edge, preserving prior authority and clean staging, and a retry succeeds' {
        foreach ($edge in @('during-lock', 'after-canonical', 'after-summary', 'after-full', 'before-manifest-swap')) {
            $case = New-FrozenCase
            try {
                Set-ReviewRunFaultSeam -Edge $edge
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                # A concurrent process's in-flight staging, which this attempt's cleanup must not touch.
                $foreign = Join-Path $case.RunDir '.review-run.other.json.tmp-ffffffffffffffffffffffffffffffff'
                Set-Content -LiteralPath $foreign -Value 'another process is writing this' -NoNewline

                $faulted = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
                $faulted.ExitCode | Should -Be 4 -Because "a fault at '$edge' is a publication failure"
                $faulted.State | Should -Be 'failed'

                # Prior authority preserved: the run is still frozen, no manifest, and no orphan
                # generation file leaks past the fault.
                Get-ReviewRunState -RunDir $case.RunDir | Should -Be 'frozen'
                Test-Path -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') | Should -BeFalse
                (Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical) | Should -BeNullOrEmpty
                # Cleanup is scoped to what this attempt wrote: its own temporary files are gone and
                # the other process's staging is untouched.
                @(Get-ChildItem -LiteralPath $case.RunDir -Filter '*.review-run.*.tmp-*' -Force).Count | Should -Be 1
                Test-Path -LiteralPath $foreign | Should -BeTrue -Because 'a sweep of every *.tmp-* would delete a concurrent writer''s staging'
                Remove-Item -LiteralPath $foreign -Force

                # Retry after correction (seam cleared) succeeds.
                Clear-ReviewRunFaultSeam
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                $retry = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
                $retry.ExitCode | Should -Be 5 -Because "a retry after the '$edge' fault must publish"
                Get-ReviewRunState -RunDir $case.RunDir | Should -Be 'published'
                @(Get-ChildItem -LiteralPath $case.RunDir -Filter '*.tmp-*' -Force).Count | Should -Be 0
            }
            finally {
                Clear-ReviewRunFaultSeam
                Remove-ReviewScratchRoot -Path $case.Scratch
            }
        }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix names every generation by its content digest and verifies name, digest, byte count and identity on read' {
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5

            $manifest = Get-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 20
            foreach ($role in @('plan', 'canonical', 'summary', 'full')) {
                $name = [string]$manifest['files'][$role]['name']
                $prefix = @{ plan = 'review-plan'; canonical = 'review-run'; summary = 'review-summary'; full = 'review-full' }[$role]
                $extension = $(if ($role -in @('plan', 'canonical')) { 'json' } else { 'md' })
                $name | Should -Match ('^' + [regex]::Escape($prefix) + '\.[0-9a-f]{64}\.' + $extension + '$')
                # The digest in the name is the digest of the bytes, so the name itself is evidence.
                $bytes = [System.IO.File]::ReadAllBytes((Join-Path $case.RunDir $name))
                $name | Should -Be ("$prefix." + (Get-ReviewDigest -Bytes $bytes).Substring(7) + ".$extension")
                [int]$manifest['files'][$role]['bytes'] | Should -Be $bytes.Length
            }
            # The fixed manifest name stays the only commit point.
            Test-Path -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') | Should -BeTrue

            $verified = Read-ReviewManifest -RunDir $case.RunDir

            # A manifest whose runId is not this directory's id is refused, even though every file it
            # names verifies: a manifest copied from another run must not read as this one.
            $foreign = Copy-ReviewMap -Map $verified.Manifest
            $foreign['runId'] = '00000000-0000-4000-8000-000000000000'
            Set-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') `
                -Value ((ConvertTo-Json -InputObject $foreign -Depth 10 -Compress) + "`n") -NoNewline
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Throw -ExpectedMessage '*runId is not this run directory*'

            # A name that is not a content address is refused before its bytes are trusted.
            $renamed = Copy-ReviewMap -Map $verified.Manifest
            $files = Copy-ReviewMap -Map $verified.Manifest['files']
            $summary = Copy-ReviewMap -Map $verified.Manifest['files']['summary']
            $legacyName = 'review-summary.md'
            Copy-Item -LiteralPath $verified.Files['summary'] -Destination (Join-Path $case.RunDir $legacyName)
            $summary['name'] = $legacyName
            $files['summary'] = $summary
            $renamed['files'] = $files
            Set-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') `
                -Value ((ConvertTo-Json -InputObject $renamed -Depth 10 -Compress) + "`n") -NoNewline
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Throw -ExpectedMessage '*not content-addressed*'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix bounds a tampered frozen plan and an unreadable published manifest to exit 2 with a terminal status' {
        # Neither is caller input, so neither used to be handled: a malformed frozen plan or manifest
        # escaped as an unhandled error, which is process exit 1 and no terminal-status object at all.
        $case = New-FrozenCase
        try {
            $planPath = Get-ReviewRunArtifact -RunDir $case.RunDir -Role plan
            [System.IO.File]::WriteAllText($planPath, 'not json at all')
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            $r.State | Should -Be 'invalid'
            $r.Message | Should -Match 'not trustworthy'

            # A second frozen plan file is equally untrustworthy: the frozen plan must be unique.
            [System.IO.File]::WriteAllText($planPath, 'still not json')
            Copy-Item -LiteralPath $planPath -Destination (Join-Path $case.RunDir ('review-plan.' + ('a' * 64) + '.json'))
            $second = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $second.ExitCode | Should -Be 2
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix refuses to overwrite an unreadable published manifest' {
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5

            # Corrupt the committed manifest, then publish a *different* result: the engine must not
            # decide it is unpublished and overwrite the authority it cannot read.
            Set-Content -LiteralPath (Join-Path $case.RunDir 'review-run.manifest.json') -Value '{ this is not json' -NoNewline
            $changed = Copy-ReviewMap -Map $case.Run
            $changed['findings'] = @(@{ taskId = 'c0-m1'; severity = 'Low'; title = 'Different'; body = 'x'; rootCause = 'r2'; component = 'c2' })
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $changed
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            $r.State | Should -Be 'invalid'
            $r.Message | Should -Match 'unreadable'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix keeps an admission decision terminal for its UUID and out of the incomplete list' {
        # D21: exit 3 never mutates the accepted set, and it outlives the process that decided it —
        # otherwise the caller could publish a quietly reduced set under the same id.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(1..2 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a' } })
            $resultTasks = @(1..2 | ForEach-Object { @{ taskId = ('t{0:d3}' -f $_); concern = ('concern-{0:d3}' -f $_); model = 'model-a'; outcome = 'completed' } })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0

            # An over-budget full view: 128 merged findings whose bodies expand four-fold when encoded.
            $body = '<' * 4096
            $over = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks $resultTasks -Findings @(1..128 | ForEach-Object {
                    @{ taskId = 't001'; severity = 'High'; title = ('finding {0}' -f $_); body = $body; rootCause = ('root-{0:d3}' -f $_); component = ('component-{0:d3}' -f $_) }
                })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $over
            $admission = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $admission.ExitCode | Should -Be 3
            Get-ReviewRunState -RunDir $runDir | Should -Be 'admission'

            # The marker is small and binds a preserved canonical source without embedding reviewer text.
            $marker = Get-Content -LiteralPath (Join-Path $runDir '.review-run.admission.json') -Raw
            $marker.Length | Should -BeLessThan 1024
            $markerObject = $marker | ConvertFrom-Json
            $markerObject.runId | Should -Be $script:runId
            $markerObject.state | Should -Be 'admission'
            $markerObject.restartable | Should -BeTrue
            $markerObject.maxRestarts | Should -Be 1
            $markerObject.maxPartitions | Should -Be 16
            $marker | Should -Not -Match '&lt;'
            $verifiedAdmission = Read-ReviewAdmissionMarker -RunDir $runDir -Boundary $scratch
            Test-Path -LiteralPath $verifiedAdmission.SourcePath -PathType Leaf | Should -BeTrue
            (Get-ReviewDigest -Bytes ([System.IO.File]::ReadAllBytes($verifiedAdmission.SourcePath))) |
                Should -Be ([string]$markerObject.parentRunDigest)

            # A narrower, perfectly publishable result under the same UUID is still exit 3, and nothing
            # is published: the caller must start a new run id.
            $reduced = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks $resultTasks -Findings @(@{ taskId = 't001'; severity = 'Low'; title = 'One small finding'; body = 'b'; rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $reduced
            $retry = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $retry.ExitCode | Should -Be 3 -Because 'admission is terminal for the UUID, not a prompt to publish less'
            $retry.State | Should -Be 'admission'
            Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
            (Get-ReviewRunArtifact -RunDir $runDir -Role canonical) | Should -BeNullOrEmpty

            # And a re-freeze of the same plan cannot reopen it either.
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 3

            # An admission-terminal run is finished, so it is not an interrupted run to finalize.
            @(Find-IncompleteReviewRun -RepoRoot $scratch) | Should -Not -Contain $script:runId
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix verifies bounded admission partitions preserve scope and every raw finding' {
        $scratch = New-ReviewScratchRoot
        try {
            $parentRunId = $script:runId
            $parentDir = Join-Path $scratch ".github/.skalary/review-runs/$parentRunId"
            $pathRecords = @(1..5 | ForEach-Object { [ordered]@{ path = "src/part$_.ps1"; status = 'modified' } })
            $parentScope = [ordered]@{ mode = 'paths'; paths = $pathRecords }
            $parentScope['digest'] = Get-ReviewScopeDigest -ScopeAuthority $parentScope
            $tasks = @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
                @{ taskId = 'correctness-m1'; concern = 'correctness'; model = 'model-a' }
            )
            $resultTasks = @($tasks | ForEach-Object { @{ taskId = $_.taskId; concern = $_.concern; model = $_.model; outcome = 'completed' } })
            $parentPlan = New-ReviewTestPlan -RunId $parentRunId -Roster @('model-a') -Tasks $tasks -ScopeAuthority $parentScope -Scope 'five canonical partitions'
            Set-ReviewHandshake -RunDir $parentDir -Kind plan -Object $parentPlan
            (Invoke-ReviewFreeze -RunId $parentRunId -RepoRoot $scratch).ExitCode | Should -Be 0

            $body = '<' * 4096
            $parentFindings = @(1..128 | ForEach-Object {
                    @{ taskId = 'security-m1'; severity = 'High'; title = ('finding {0:d3}' -f $_); body = $body; rootCause = ('root-{0:d3}' -f $_); component = ('component-{0:d3}' -f $_) }
                })
            $parentRun = New-ReviewTestRun -RunId $parentRunId -PlanDigest (Get-ReviewFrozenDigest -RunDir $parentDir) `
                -Roster @('model-a') -Tasks $resultTasks -Findings $parentFindings -ScopeAuthority $parentScope -Scope 'five canonical partitions'
            Set-ReviewHandshake -RunDir $parentDir -Kind result -Object $parentRun
            (Invoke-ReviewPublish -RunId $parentRunId -RepoRoot $scratch).ExitCode | Should -Be 3
            $admission = Read-ReviewAdmissionMarker -RunDir $parentDir -Boundary $scratch
            $parentRunDigest = [string]$admission.Marker['parentRunDigest']

            $childIds = @(
                '11111111-1111-4111-8111-111111111111',
                '22222222-2222-4222-8222-222222222222',
                '33333333-3333-4333-8333-333333333333',
                '44444444-4444-4444-8444-444444444444',
                '55555555-5555-4555-8555-555555555555'
            )
            for ($partition = 1; $partition -le 5; $partition++) {
                $childId = $childIds[$partition - 1]
                $childDir = Join-Path $scratch ".github/.skalary/review-runs/$childId"
                $childScope = [ordered]@{ mode = 'paths'; paths = @($pathRecords[$partition - 1]) }
                $childScope['digest'] = Get-ReviewScopeDigest -ScopeAuthority $childScope
                $restart = [ordered]@{
                    parentRunId = $parentRunId
                    parentRunDigest = $parentRunDigest
                    restartOrdinal = 1
                    partitionIndex = $partition
                    partitionCount = 5
                }
                $childPlan = New-ReviewTestPlan -RunId $childId -Roster @('model-a') -Tasks $tasks -ScopeAuthority $childScope `
                    -Scope "partition $partition of 5" -Restart $restart
                Set-ReviewHandshake -RunDir $childDir -Kind plan -Object $childPlan
                (Invoke-ReviewFreeze -RunId $childId -RepoRoot $scratch).ExitCode | Should -Be 0

                $first = [int][Math]::Floor((($partition - 1) * 128) / 5)
                $last = [int][Math]::Floor(($partition * 128) / 5) - 1
                $childFindings = @($parentFindings[$first..$last])
                $childRun = New-ReviewTestRun -RunId $childId -PlanDigest (Get-ReviewFrozenDigest -RunDir $childDir) `
                    -Roster @('model-a') -Tasks $resultTasks -Findings $childFindings -ScopeAuthority $childScope `
                    -Scope "partition $partition of 5" -Restart $restart
                Set-ReviewHandshake -RunDir $childDir -Kind result -Object $childRun
                $childPublish = Invoke-ReviewPublish -RunId $childId -RepoRoot $scratch
                $childPublish.ExitCode | Should -Be 0 -Because ($childPublish.Message + ' ' + ($childPublish.Diagnostics -join '; '))
            }

            $rollup = Get-ReviewAdmissionRollup -ParentRunId $parentRunId -RepoRoot $scratch
            $rollup.state | Should -Be 'verified'
            $rollup.parentRunDigest | Should -Be $parentRunDigest
            $rollup.scopeDigest | Should -Be ([string]$parentScope.digest)
            $rollup.findingCount | Should -Be 128
            @($rollup.partitions).Count | Should -Be 5
            @($rollup.partitions.index) | Should -Be @(1, 2, 3, 4, 5)
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix admits only from the mode''s legal prior state, never stamping admission onto published authority and never claiming a decision it could not persist' {
        # The marker is a state transition, so it is decided under the same lock every other
        # transition is: `Publish` may admit only a `frozen` run. Writing it unconditionally — the
        # earlier behavior — let an over-budget retry turn a verified publication into `admission`,
        # and reported exit 3 even when the marker never reached disk.
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5
            $manifestPath = Join-Path $case.RunDir 'review-run.manifest.json'
            $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)

            # An over-2 MiB *changed* result under the published run id. The byte gate refuses it
            # before anything parses it, and that refusal must not touch the run's committed state.
            $oversized = Copy-ReviewMap -Map $case.Run
            $oversized['findings'] = @(@{ taskId = 'c0-m1'; severity = 'Low'; title = 'Different'; body = ('b' * 2200000); rootCause = 'r2'; component = 'c2' })
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $oversized -Compress
            $inputPath = Join-Path $case.RunDir 'review-result.input.json'
            (Get-Item -LiteralPath $inputPath).Length |
                Should -BeGreaterThan ([int](Get-ReviewLimits).maxEnvelopeBytes) -Because 'the fixture must actually be over the input cap'

            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2 -Because 'an over-budget retry cannot stamp admission onto published authority'
            $r.State | Should -Be 'invalid'
            Test-Path -LiteralPath (Join-Path $case.RunDir '.review-run.admission.json') |
                Should -BeFalse -Because 'no marker is written from an illegal prior state'
            Get-ReviewRunState -RunDir $case.RunDir | Should -Be 'published'
            [System.IO.File]::ReadAllBytes($manifestPath) | Should -Be $manifestBytes
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Not -Throw
            Test-Path -LiteralPath $inputPath | Should -BeFalse -Because 'the rejected input is destroyed either way'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }

        # A marker it cannot persist is an explicit exit 4, not an exit 3 no later invocation could
        # ever see: the run stays exactly what it was.
        $case2 = New-FrozenCase
        $held = $null
        try {
            $held = Enter-ReviewLock -RunDir $case2.RunDir
            Set-ReviewRunLockTimeoutOverride -Seconds 0.3
            $oversized = Copy-ReviewMap -Map $case2.Run
            $oversized['findings'] = @(@{ taskId = 'c0-m1'; severity = 'Low'; title = 'Big'; body = ('b' * 2200000); rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $case2.RunDir -Kind result -Object $oversized -Compress

            $blocked = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case2.Scratch
            $blocked.ExitCode | Should -Be 4 -Because 'an admission that cannot be recorded is a failure, not a terminal decision'
            $blocked.State | Should -Be 'failed'
            ($blocked.Diagnostics -join ' ') | Should -Match 'could not be persisted'
            Test-Path -LiteralPath (Join-Path $case2.RunDir '.review-run.admission.json') | Should -BeFalse
            Get-ReviewRunState -RunDir $case2.RunDir | Should -Be 'frozen'
        }
        finally {
            Set-ReviewRunLockTimeoutOverride -Seconds $null
            if ($held) { Exit-ReviewLock -Lock $held }
            Remove-ReviewScratchRoot -Path $case2.Scratch
        }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix verifies the committed manifest in full before replaying it, so a tampered-but-parseable manifest is exit 2 rather than idempotent success' {
        # The replay branch used to parse the manifest itself and compare `runDigest` alone, so a
        # manifest that still parsed — and still carried the right `runDigest` — answered "already
        # published" for files nothing had verified. It now goes through the same reader a consumer
        # uses: schema, content-addressed names, bytes, every digest and the canonical plan binding.
        foreach ($tamper in @('summary-digest', 'plan-binding')) {
            $case = New-FrozenCase
            try {
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5
                $manifestPath = Join-Path $case.RunDir 'review-run.manifest.json'

                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
                $wrong = 'sha256:' + ('0' * 64)
                if ($tamper -eq 'summary-digest') { $manifest['files']['summary']['digest'] = $wrong }
                else { $manifest['planDigest'] = $wrong }
                $tamperedJson = (ConvertTo-Json -InputObject $manifest -Depth 10 -Compress) + "`n"
                # Parseable *and* schema-valid, with `runDigest` intact: only verification against the
                # files it names catches this one.
                (Test-ReviewSchema -Json $tamperedJson -SchemaName 'review-manifest.schema.json') | Should -BeTrue
                Set-Content -LiteralPath $manifestPath -Value $tamperedJson -NoNewline
                $tamperedBytes = [System.IO.File]::ReadAllBytes($manifestPath)

                # The identical result replays: previously exit 5 "idempotent", now a refusal.
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                $replay = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
                $replay.ExitCode | Should -Be 2 -Because "a '$tamper' manifest must not answer for this run"
                $replay.State | Should -Be 'invalid'
                $replay.Message | Should -Match 'unreadable'
                [System.IO.File]::ReadAllBytes($manifestPath) |
                    Should -Be $tamperedBytes -Because 'a refused replay never overwrites committed authority'
                (Get-ReviewRunArtifact -RunDir $case.RunDir -Role canonical) | Should -Not -BeNullOrEmpty
            }
            finally { Remove-ReviewScratchRoot -Path $case.Scratch }
        }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix refuses a verified read through a symlinked run directory or a symlinked leaf artifact' {
        # Confinement is not only a write-time property (RISK-6). A verified read opens concrete files,
        # so the run directory and every file the manifest names are re-checked for a reparse point
        # immediately before they are opened: otherwise a run directory or a single artifact swapped
        # for a link would make the reader read — and a consumer trust — bytes from outside the store.
        $case = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Not -Throw

            # 1. A leaf artifact replaced by a link to identical bytes elsewhere: every digest still
            # verifies, so only the reparse-point check can refuse it.
            $summaryPath = Get-ReviewRunArtifact -RunDir $case.RunDir -Role summary
            $summaryFull = [System.IO.Path]::GetFullPath($summaryPath)
            Set-ReviewPathItemProvider -Provider ({
                    param($Path)
                    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                    if ($item -and [string]::Equals([System.IO.Path]::GetFullPath($Path), $summaryFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return [pscustomobject]@{ Attributes = $item.Attributes -bor [System.IO.FileAttributes]::ReparsePoint }
                    }
                    return $item
                }.GetNewClosure())
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Throw -ExpectedMessage '*symlink or reparse point*'
            { Get-ReviewRunSummaryText -RunDir $case.RunDir } | Should -Throw -ExpectedMessage '*symlink or reparse point*'
            Clear-ReviewPathItemProvider
            { Read-ReviewManifest -RunDir $case.RunDir } | Should -Not -Throw -Because 'the run itself was never damaged'

            # 2. The run directory itself reached through a link inside the store.
            $store = Join-Path $case.Scratch '.github/.skalary/review-runs'
            $aliasId = '0e1d2c3b-4a59-4867-9a5b-1c2d3e4f5a6b'
            $alias = Join-Path $store $aliasId
            $linkType = $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' })
            [void](New-Item -ItemType $linkType -Path $alias -Target $case.RunDir -ErrorAction Stop)
            { Read-ReviewManifest -RunDir $alias } | Should -Throw -ExpectedMessage '*symlink or reparse point*'
            { Get-ReviewRunSummaryText -RunDir $alias -Boundary $case.Scratch } | Should -Throw -ExpectedMessage '*symlink or reparse point*'

            # 3. Enumeration is a read of the store too: a symlinked run directory is refused before
            # its state is decided, not reported as a run to finalize.
            { Find-IncompleteReviewRun -RepoRoot $case.Scratch } | Should -Throw -ExpectedMessage '*symlink or reparse point*'
            Remove-Item -LiteralPath $alias -Force
            { Find-IncompleteReviewRun -RepoRoot $case.Scratch } | Should -Not -Throw

            # The reader CLI turns both refusals into its bounded exit 2.
            $reader = Join-Path $script:repoRoot 'scripts/skalary/Get-ReviewRun.ps1'
            [void](New-Item -ItemType $linkType -Path $alias -Target $case.RunDir -ErrorAction Stop)
            & pwsh -NoProfile -File $reader -RunId $aliasId *> $null
            $LASTEXITCODE | Should -Be 2
            Remove-Item -LiteralPath $alias -Force
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix enforces each role''s own byte budget and artifact encoding, even when the manifest agrees with the bytes' {
        # The manifest's `byteCount` is bounded only by the generic 2 MiB envelope maximum, so a summary
        # of 900 KiB is a structurally valid, digest-consistent manifest entry. A reader that checked
        # nothing but "the file is as long as the manifest says" would hand a consumer a view far
        # outside the budget the publisher admits, and text in an encoding this engine never writes.
        # The reader therefore re-derives the role budget from the schema-owned vocabulary and checks
        # the artifact encoding itself.
        function Script:Set-ReviewArtifactBytes {
            <#
            .SYNOPSIS
                Replaces one role's artifact and repairs the manifest so the tamper stays fully
                digest-consistent: new content address, new digest, new byte count.
            #>
            param(
                [Parameter(Mandatory)][string]$RunDir,
                [Parameter(Mandatory)][ValidateSet('summary', 'full')][string]$Role,
                [Parameter(Mandatory)][byte[]]$Bytes
            )

            $manifestPath = Join-Path $RunDir 'review-run.manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
            $previous = Join-Path $RunDir ([string]$manifest['files'][$Role]['name'])
            $hex = (Get-ReviewDigest -Bytes $Bytes).Substring(7)
            $name = @{ summary = 'review-summary'; full = 'review-full' }[$Role] + '.' + $hex + '.md'
            [System.IO.File]::WriteAllBytes((Join-Path $RunDir $name), $Bytes)
            if ((Test-Path -LiteralPath $previous -PathType Leaf) -and ((Split-Path -Leaf $previous) -cne $name)) {
                Remove-Item -LiteralPath $previous -Force
            }
            $manifest['files'][$Role]['name'] = $name
            $manifest['files'][$Role]['digest'] = 'sha256:' + $hex
            $manifest['files'][$Role]['bytes'] = $Bytes.Length
            $json = (ConvertTo-Json -InputObject $manifest -Depth 10 -Compress) + "`n"
            Set-Content -LiteralPath $manifestPath -Value $json -NoNewline
            return $json
        }

        $limits = Get-ReviewLimits
        $cases = @(
            @{ Name = 'over the summary budget'; Role = 'summary'; Expect = '*over its 32768 budget*'
                Bytes = { [System.Text.Encoding]::UTF8.GetBytes(("# Code Review — summary`n`n" + ('x' * ([int]$limits.maxSummaryBytes + 64)) + "`n")) }
            }
            @{ Name = 'CRLF line endings'; Role = 'summary'; Expect = '*carriage return*'
                Bytes = { [System.Text.Encoding]::UTF8.GetBytes("# Code Review — summary`r`n`r`nverified`r`n") }
            }
            @{ Name = 'a byte-order mark'; Role = 'summary'; Expect = '*byte-order mark*'
                Bytes = { @(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("# Code Review — summary`n") }
            }
            @{ Name = 'decomposed (non-NFC) text'; Role = 'summary'; Expect = '*not NFC-normalized*'
                Bytes = { [System.Text.Encoding]::UTF8.GetBytes("# Cafe`u{0301} — summary`n") }
            }
            @{ Name = 'invalid UTF-8'; Role = 'summary'; Expect = '*not valid UTF-8*'
                Bytes = { [byte[]]@(0x23, 0x20, 0xC3, 0x28, 0x0A) }
            }
            @{ Name = 'over the full-view budget'; Role = 'full'; Expect = '*over its 1048576 budget*'
                Bytes = { [System.Text.Encoding]::UTF8.GetBytes(("# Code Review — full report`n`n" + ('y' * ([int]$limits.maxFullBytes + 64)) + "`n")) }
            }
        )

        foreach ($tamper in $cases) {
            $case = New-FrozenCase
            try {
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5
                { Read-ReviewManifest -RunDir $case.RunDir } | Should -Not -Throw

                $manifestJson = Set-ReviewArtifactBytes -RunDir $case.RunDir -Role $tamper.Role -Bytes ([byte[]](& $tamper.Bytes))
                # The tamper is fully consistent: schema-valid manifest, correct name, digest and count.
                (Test-ReviewSchema -Json $manifestJson -SchemaName 'review-manifest.schema.json') |
                    Should -BeTrue -Because "a manifest carrying $($tamper.Name) is still structurally valid"

                { Read-ReviewManifest -RunDir $case.RunDir } |
                    Should -Throw -ExpectedMessage $tamper.Expect -Because "the reader rejects $($tamper.Name) on its own authority"
                { Get-ReviewRunSummaryText -RunDir $case.RunDir } | Should -Throw
                # Cleanup verifies through the same reader, so it refuses to discard it silently.
                { Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $case.Scratch } | Should -Throw
                Test-Path -LiteralPath $case.RunDir -PathType Container | Should -BeTrue
            }
            finally { Remove-ReviewScratchRoot -Path $case.Scratch }
        }

        # And a run this engine actually published passes every one of those checks.
        $good = New-FrozenCase
        try {
            Set-ReviewHandshake -RunDir $good.RunDir -Kind result -Object $good.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $good.Scratch).ExitCode | Should -Be 5
            $verified = Read-ReviewManifest -RunDir $good.RunDir
            foreach ($role in @('plan', 'canonical', 'summary', 'full')) {
                $bytes = [System.IO.File]::ReadAllBytes($verified.Files[$role])
                $bytes.Length | Should -BeLessOrEqual (@{
                        plan = [int]$limits.maxEnvelopeBytes; canonical = [int]$limits.maxEnvelopeBytes
                        summary = [int]$limits.maxSummaryBytes; full = [int]$limits.maxFullBytes
                    }[$role])
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                $text | Should -Not -Match "`r"
                $text.IsNormalized([System.Text.NormalizationForm]::FormC) | Should -BeTrue
            }
        }
        finally { Remove-ReviewScratchRoot -Path $good.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix serializes concurrent publications so only one commits and the lock file is never unlinked' {
        $case = New-FrozenCase
        try {
            # A held lock blocks a concurrent Freeze of a *different* plan, so immutable state cannot be
            # decided by two processes at once.
            $held = Enter-ReviewLock -RunDir $case.RunDir
            try {
                Set-ReviewRunLockTimeoutOverride -Seconds 0.3
                $frozenBefore = Split-Path -Leaf (Get-ReviewRunArtifact -RunDir $case.RunDir -Role plan)
                Set-ReviewHandshake -RunDir $case.RunDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(
                        @{ taskId = 'other-m1'; concern = 'other'; model = 'model-a' }))
                $blocked = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $case.Scratch
                $blocked.ExitCode | Should -Be 4 -Because 'Freeze decides immutable state under the same lock a publication takes'
                Split-Path -Leaf (Get-ReviewRunArtifact -RunDir $case.RunDir -Role plan) | Should -Be $frozenBefore
            }
            finally {
                Set-ReviewRunLockTimeoutOverride -Seconds $null
                Exit-ReviewLock -Lock $held
                Remove-Item -LiteralPath (Join-Path $case.RunDir 'review-plan.input.json') -Force -ErrorAction SilentlyContinue
            }
            Test-Path -LiteralPath (Join-Path $case.RunDir '.review-run.lock') | Should -BeTrue -Because 'the stable lock file is never unlinked'

            # Two processes publishing different results race on the same run. Whatever the interleaving,
            # exactly one manifest exists, it verifies, and it is one of the two results — never a mix.
            $modulePath = Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1'
            $kitPath = Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1'
            $script:concurrentWorker = Join-Path $case.Scratch 'publish-worker.ps1'
            Set-Content -LiteralPath $script:concurrentWorker -Value @'
param([string]$ModulePath, [string]$KitPath, [string]$RepoRoot, [string]$RunDir, [string]$RunId, [string]$Title, [string]$OutPath)
Import-Module $ModulePath -Force -DisableNameChecking
Import-Module $KitPath -Force -DisableNameChecking
$digest = Get-ReviewFrozenDigest -RunDir $RunDir
$run = New-ReviewTestRun -RunId $RunId -PlanDigest $digest -Roster @('model-a') `
    -Tasks @(@{ taskId = 'c0-m1'; concern = 'concern0'; model = 'model-a'; outcome = 'completed' },
             @{ taskId = 'c1-m1'; concern = 'concern1'; model = 'model-a'; outcome = 'failed'; diagnostic = 'outcome failed' }) `
    -Findings @(@{ taskId = 'c0-m1'; severity = 'High'; title = $Title; body = 'b'; rootCause = 'r'; component = 'c' })
# Each caller stages its own temporary file and performs the D16 atomic rename onto the one fixed
# input name; the rename is what makes a complete document visible to the engine.
$tmp = Join-Path $RunDir (".review-result.input.tmp-" + [guid]::NewGuid().ToString('N'))
Set-Content -LiteralPath $tmp -Value (ConvertTo-Json -InputObject $run -Depth 40) -NoNewline
[System.IO.File]::Move($tmp, (Join-Path $RunDir 'review-result.input.json'), $true)
$result = Invoke-ReviewPublish -RunId $RunId -RepoRoot $RepoRoot
Set-Content -LiteralPath $OutPath -Value (ConvertTo-Json -InputObject @{ exit = $result.ExitCode; state = $result.State } -Compress) -NoNewline
'@ -NoNewline

            $outA = Join-Path $case.Scratch 'a.json'
            $outB = Join-Path $case.Scratch 'b.json'
            $procs = @(
                @{ Title = 'Alpha-result'; Out = $outA }
                @{ Title = 'Beta-result'; Out = $outB }
            ) | ForEach-Object {
                Start-Process -FilePath 'pwsh' -PassThru -NoNewWindow -ArgumentList @(
                    '-NoProfile', '-File', $script:concurrentWorker,
                    '-ModulePath', $modulePath, '-KitPath', $kitPath, '-RepoRoot', $case.Scratch,
                    '-RunDir', $case.RunDir, '-RunId', $script:runId, '-Title', $_.Title, '-OutPath', $_.Out)
            }
            foreach ($proc in $procs) { $proc.WaitForExit(120000) | Out-Null }

            foreach ($out in @($outA, $outB)) {
                Test-Path -LiteralPath $out | Should -BeTrue -Because 'each worker must reach a bounded terminal result'
                $record = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
                [int]$record.exit | Should -BeIn @(0, 2, 3, 4, 5) -Because 'every path is one of the contract exits'
            }

            # Exactly one committed authority, fully verifiable, and one of the two titles won outright.
            @(Get-ChildItem -LiteralPath $case.RunDir -File -Force -Filter 'review-run.manifest.json').Count | Should -Be 1
            $verified = Read-ReviewManifest -RunDir $case.RunDir
            $summary = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($verified.Files['summary']))
            @(@('Alpha-result', 'Beta-result') | Where-Object { $summary -match [regex]::Escape($_) }).Count |
                Should -Be 1 -Because 'a published run is exactly one result, never a mixture of two'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.ManifestReaderPublicationAndExitMatrix finds an incomplete frozen run and stops reporting it once published' {
        # A frozen-but-unpublished run is discoverable so the caller can finalize it at the next start.
        $case = New-FrozenCase
        try {
            @(Find-IncompleteReviewRun -RepoRoot $case.Scratch) | Should -Contain $script:runId
            (Get-ReviewRunState -RunDir $case.RunDir) | Should -Be 'frozen'

            # Publish it, then it is no longer incomplete.
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch).ExitCode | Should -Be 5
            @(Find-IncompleteReviewRun -RepoRoot $case.Scratch) | Should -Not -Contain $script:runId
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }
}
