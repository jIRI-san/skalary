#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Add-WorkflowNote' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'
        $script:planStatePath = Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1'

        function Script:New-PlanFixture {
            param([ValidateSet('legacy', 'assets')][string]$Layout = 'legacy')

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wfnote-" + [guid]::NewGuid().ToString('N'))
            $folder = if ($Layout -eq 'legacy') { '001-note-fixture' } else { '2026-08-09-a1b2c3-note-fixture' }
            $planDir = Join-Path $root "docs/implementation-plans/$folder"
            [void](New-Item -ItemType Directory -Path $planDir -Force)

            $planText = @(
                $(if ($Layout -eq 'legacy') { '# 001: Note fixture' } else { '# a1b2c3: Note fixture' })
                $(if ($Layout -eq 'assets') { '<!-- plan-id: a1b2c3 -->' } else { '' })
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | First | `test:first` | 1.1 |'
                '| REQ-2 | Second | `test:second` | 1.1 |'
                ''
                '## Risks'
                ''
                '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
                '|----|------|------------|--------|------------|-------|'
                '| RISK-1 | Risk | Low | Low | Test | 1.1 |'
                ''
                '## Phase 1: Fixture'
                '- [ ] 1.1 Exercise fixture (REQ-1, REQ-2, RISK-1) `S`'
            ) -join "`n"
            [System.IO.File]::WriteAllText(
                (Join-Path $planDir 'plan.md'),
                $planText + "`n",
                [System.Text.UTF8Encoding]::new($false)
            )

            if ($Layout -eq 'assets') {
                $assets = Join-Path $planDir 'assets'
                [void](New-Item -ItemType Directory -Path $assets -Force)
                [System.IO.File]::WriteAllText(
                    (Join-Path $assets 'requirements.md'),
                    @(
                        '# Requirements'
                        ''
                        '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                        '|----|-------------|---------------------|--------------|'
                        '| REQ-1 | First | `test:first` | 1.1 |'
                        '| REQ-2 | Second | `test:second` | 1.1 |'
                        ''
                    ) -join "`n",
                    [System.Text.UTF8Encoding]::new($false)
                )
            }

            return [pscustomobject]@{ Root = $root; PlanDir = $planDir; Layout = $Layout }
        }

        function Script:Remove-PlanFixture {
            param([Parameter(Mandatory)]$Fixture)

            Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }

        function Script:Add-Learning {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][int]$Number
            )

            & $script:scriptPath -Kind Learnings -PlanDir $Fixture.PlanDir -RepoRoot $Fixture.Root `
                -Phase 1 -Step "1.$Number" -Trigger reusable-pattern `
                -Concern maintainability-consistency -Requirement REQ-1 -ReviewType none `
                -Message "Learning number $Number"
        }

        function Script:Invoke-NoteProcess {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][string[]]$Arguments
            )

            $pwshArgs = @('-NoProfile', '-File', $script:scriptPath) + $Arguments +
                @('-PlanDir', $Fixture.PlanDir, '-RepoRoot', $Fixture.Root)
            $output = & pwsh @pwshArgs 2>&1
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }

        function Script:New-TestOverflowBatch {
            param([Parameter(Mandatory)][string[]]$Record)

            $recordBytes = ($Record -join "`n") + "`n"
            $framed = 'workflow-learning-overflow/v1' + [char]0 + '001' + [char]0 + $recordBytes
            $digest = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes($framed)
                )
            ).ToLowerInvariant()
            $content = @(
                '# Learning Overflow Batch'
                'Schema: workflow-learning-overflow/v1'
                'Plan: 001'
                "Digest: $digest"
                "Count: $($Record.Count)"
                ''
                $Record
            ) -join "`n"
            return [pscustomobject]@{ Digest = $digest; Content = $content + "`n" }
        }
    }

    It 'test:workflownote-init creates the section with a fail-loud placeholder' {
        $fixture = New-PlanFixture
        try {
            & $script:scriptPath -Kind CrLog -PlanDir $fixture.PlanDir -Phase 1 | Out-Null
            $file = Join-Path $fixture.PlanDir 'cr-log.md'
            Test-Path -LiteralPath $file | Should -BeTrue
            $text = Get-Content -LiteralPath $file -Raw
            $text | Should -Match '(?m)^## CR Capture$'
            $text | Should -Match '(?m)^Phase: 1$'
            $text | Should -Match '(?m)^No entries for this phase\.$'
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }

    It 'test:workflownote-init is idempotent and preserves prior phase sections' {
        $fixture = New-PlanFixture
        try {
            & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root -Phase 1 | Out-Null
            & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root -Phase 2 | Out-Null
            & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root -Phase 1 | Out-Null
            $text = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'learnings.md') -Raw
            ([regex]::Matches($text, '(?m)^## Learnings Capture$')).Count | Should -Be 2
            ([regex]::Matches($text, '(?m)^Phase: 1$')).Count | Should -Be 1
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }

    It 'test:workflownote-append replaces the placeholder with a typed-token entry' {
        $fixture = New-PlanFixture
        try {
            & $script:scriptPath -Kind CrLog -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root -Phase 1 | Out-Null
            & $script:scriptPath -Kind CrLog -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                -Phase 1 -Step 1.1 -Sev High -Concern correctness-reliability `
                -Requirement REQ-1 -ReviewType cr -Message 'Null check missing' | Out-Null
            $text = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'cr-log.md') -Raw
            $text | Should -Not -Match 'No entries for this phase'
            $text | Should -Match '(?m)^- \[1\.1\] \[src:code-review\] \[sev:High\].*Null check missing$'
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }

    It 'rejects kind-specific fields that are not represented in the record grammar' {
        $fixture = New-PlanFixture
        try {
            $learning = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                '-Kind', 'Learnings', '-Phase', '1', '-Step', '1.1',
                '-Trigger', 'reusable-pattern', '-Src', 'note',
                '-Concern', 'maintainability-consistency', '-Requirement', 'REQ-1',
                '-ReviewType', 'none', '-Message', 'Hidden source'
            )
            $learning.ExitCode | Should -Not -Be 0
            $learning.Output | Should -Match 'do not accept -Src or -Sev'

            $capture = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                '-Kind', 'Capture', '-Phase', '1', '-Step', '1.1',
                '-Trigger', 'reusable-pattern',
                '-Concern', 'maintainability-consistency', '-Requirement', 'REQ-1',
                '-ReviewType', 'none', '-Message', 'Hidden trigger'
            )
            $capture.ExitCode | Should -Not -Be 0
            $capture.Output | Should -Match 'do not accept -Trigger'

            $crossPhase = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                '-Kind', 'Capture', '-Phase', '1', '-Step', '2.1',
                '-Concern', 'maintainability-consistency', '-Requirement', 'REQ-1',
                '-ReviewType', 'none', '-Message', 'Wrong phase'
            )
            $crossPhase.ExitCode | Should -Not -Be 0
            $crossPhase.Output | Should -Match 'does not belong to\s+phase\s+1'

            $stepLessLearning = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                '-Kind', 'Learnings', '-Phase', '1',
                '-Trigger', 'reusable-pattern',
                '-Concern', 'maintainability-consistency', '-Requirement', 'REQ-1',
                '-ReviewType', 'none', '-Message', 'Missing step'
            )
            $stepLessLearning.ExitCode | Should -Not -Be 0
            $stepLessLearning.Output | Should -Match 'require -Step'
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }

    It 'test:workflownote-append appends additional entries after the first' {
        $fixture = New-PlanFixture
        try {
            Add-Learning -Fixture $fixture -Number 1 | Out-Null
            Add-Learning -Fixture $fixture -Number 2 | Out-Null
            $lines = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'learnings.md')
            ($lines | Where-Object { $_ -match '^- \[' }).Count | Should -Be 2
            $lines[-1] | Should -Match '^- \[1\.2\] \[trigger:reusable-pattern\].*Learning number 2$'
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }

    Context 'test:WorkflowNote.TypedProvenanceRoundTrip' {
        It 'test:WorkflowNote.TypedProvenanceRoundTrip sorts requirements and domain-separates source records' {
            $fixture = New-PlanFixture
            try {
                $cr = & $script:scriptPath -Kind CrLog -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Sev Med -Concern testing-evidence `
                    -Requirement REQ-2, REQ-1, REQ-2 -ReviewType cr -Message 'Typed finding'
                $capture = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern testing-evidence `
                    -Requirement REQ-2, REQ-1 -ReviewType cr -Message 'Typed finding'

                $cr.SourceRecordId | Should -Match '^[0-9a-f]{64}$'
                $capture.SourceRecordId | Should -Match '^[0-9a-f]{64}$'
                $capture.SourceRecordId | Should -Not -Be $cr.SourceRecordId

                $base = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-1 `
                    -ReviewType none -Message 'Binding probe'
                $changedConcern = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern performance -Requirement REQ-1 `
                    -ReviewType none -Message 'Binding probe'
                $changedRequirement = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-2 `
                    -ReviewType none -Message 'Binding probe'
                $changedReview = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-1 `
                    -ReviewType cr -Message 'Binding probe'
                $ordered = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-1, REQ-2 `
                    -ReviewType dr -Message 'Ordering probe'
                $permuted = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-2, REQ-1 `
                    -ReviewType dr -Message 'Ordering probe'

                $changedConcern.SourceRecordId | Should -Not -Be $base.SourceRecordId
                $changedRequirement.SourceRecordId | Should -Not -Be $base.SourceRecordId
                $changedReview.SourceRecordId | Should -Not -Be $base.SourceRecordId
                $permuted.SourceRecordId | Should -Be $ordered.SourceRecordId
                $permuted.Appended | Should -BeFalse
                $line = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'cr-log.md') |
                    Where-Object { $_ -match 'Typed finding' }
                $line | Should -Match '\[concern:testing-evidence\]'
                $line | Should -Match '\[req:REQ-1,REQ-2\]'
                $line | Should -Match '\[review:cr\]'
                $line | Should -Match "\[source-record:$($cr.SourceRecordId)\]"
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:WorkflowNote.TypedProvenanceRoundTrip refuses unknown plan requirements and enum values' {
            $fixture = New-PlanFixture
            try {
                {
                    & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                        -Phase 1 -Concern security -Requirement REQ-99 -Message 'Unknown requirement'
                } | Should -Throw '*does not belong*'
                {
                    & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                        -Phase 1 -Concern invented-concern -Message 'Unknown concern'
                } | Should -Throw
                {
                    & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                        -Phase 1 -Concern security -ReviewType invented-review -Message 'Unknown review'
                } | Should -Throw
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }
    }

    Context 'test:WorkflowNote.LosslessOverflowCrashRecovery' {
        It 'test:WorkflowNote.LosslessOverflowCrashRecovery writes overflow before retaining the newest active set' {
            $fixture = New-PlanFixture
            try {
                foreach ($number in 1..11) {
                    Add-Learning -Fixture $fixture -Number $number | Out-Null
                }

                $active = @(Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'learnings.md') |
                        Where-Object { $_ -match '^- \[' })
                $active.Count | Should -Be 10
                ($active -join "`n") | Should -Not -Match 'Learning number 1\b'
                ($active -join "`n") | Should -Match 'Learning number 11\b'
                ($active -join "`n") | Should -Not -Match 'overflow-summary'

                $overflow = @(Get-ChildItem -LiteralPath (Join-Path $fixture.PlanDir 'learning-overflow') -File)
                $overflow.Count | Should -Be 1
                $overflowText = [System.IO.File]::ReadAllText($overflow[0].FullName)
                $overflowText | Should -Match 'Learning number 1\b'
                $overflowText | Should -Match '(?m)^Schema: workflow-learning-overflow/v1$'
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:WorkflowNote.LosslessOverflowCrashRecovery replays an overflow-first crash state without loss or duplicate batches' {
            $fixture = New-PlanFixture
            try {
                foreach ($number in 1..10) {
                    Add-Learning -Fixture $fixture -Number $number | Out-Null
                }
                $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                $beforeOverflow = [System.IO.File]::ReadAllText($activePath)

                Add-Learning -Fixture $fixture -Number 11 | Out-Null
                $overflowRoot = Join-Path $fixture.PlanDir 'learning-overflow'
                @(Get-ChildItem -LiteralPath $overflowRoot -File).Count | Should -Be 1

                $postCommitReplay = Add-Learning -Fixture $fixture -Number 11
                $postCommitReplay.Appended | Should -BeFalse
                @(Get-Content -LiteralPath $activePath | Where-Object { $_ -match 'Learning number 11\b' }).Count |
                    Should -Be 1

                # This is the persisted state after overflow-first succeeds and the active replace
                # crashes: the append-only batch exists while the active file still has its old bytes.
                [System.IO.File]::WriteAllText(
                    $activePath,
                    $beforeOverflow,
                    [System.Text.UTF8Encoding]::new($false)
                )
                Add-Learning -Fixture $fixture -Number 11 | Out-Null

                @(Get-ChildItem -LiteralPath $overflowRoot -File).Count | Should -Be 1
                $active = @(Get-Content -LiteralPath $activePath | Where-Object { $_ -match '^- \[' })
                $active.Count | Should -Be 10
                ($active -join "`n") | Should -Not -Match 'Learning number 1\b'
                ($active -join "`n") | Should -Match 'Learning number 11\b'
                $all = ([System.IO.File]::ReadAllText((Get-ChildItem -LiteralPath $overflowRoot -File).FullName) +
                    [System.IO.File]::ReadAllText($activePath))
                ([regex]::Matches($all, 'Learning number 1\b')).Count | Should -Be 1
                ([regex]::Matches($all, 'Learning number 11\b')).Count | Should -Be 1

                $overflowReplay = Add-Learning -Fixture $fixture -Number 1
                $overflowReplay.Appended | Should -BeFalse
                @(Get-ChildItem -LiteralPath $overflowRoot -File).Count | Should -Be 1
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:WorkflowNote.LosslessOverflowCrashRecovery surfaces old overflow summaries as legacy loss' {
            $fixture = New-PlanFixture
            try {
                $legacy = @(
                    '## Learnings Capture'
                    'Phase: 1'
                    ''
                    '- [1.1] [trigger:overflow-summary] Folded 4 additional learnings into this summary.'
                    ''
                ) -join "`n"
                [System.IO.File]::WriteAllText(
                    (Join-Path $fixture.PlanDir 'learnings.md'),
                    $legacy,
                    [System.Text.UTF8Encoding]::new($false)
                )

                $result = & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1
                $result.Status | Should -Be 'legacy-loss'
                $result.LegacyLossCount | Should -Be 1
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }
    }

    Context 'test:Capture.AtomicBoundaryMigrationMatrix' {
        It 'test:Capture.AtomicBoundaryMigrationMatrix repairs duplicate ids, orphan batches, summaries, and stale temps' {
            $fixture = New-PlanFixture
            try {
                $first = Add-Learning -Fixture $fixture -Number 1
                $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                $entry = Get-Content -LiteralPath $activePath | Where-Object { $_ -match 'Learning number 1\b' }
                Add-Content -LiteralPath $activePath -Value $entry -Encoding utf8NoBOM
                $temp = Join-Path $fixture.PlanDir '.atomic-stale.tmp'
                [System.IO.File]::WriteAllText($temp, 'abandoned')
                (Get-Item -LiteralPath $temp -Force).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)

                & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1 | Out-Null
                @(Get-Content -LiteralPath $activePath |
                        Where-Object { $_ -match [regex]::Escape($first.SourceRecordId) }).Count | Should -Be 1
                Test-Path -LiteralPath $temp | Should -BeFalse

                foreach ($number in 2..11) { Add-Learning -Fixture $fixture -Number $number | Out-Null }
                $overflowRoot = Join-Path $fixture.PlanDir 'learning-overflow'
                $before = [System.IO.File]::ReadAllText($activePath)
                $overflowEntry = [System.IO.File]::ReadAllText((Get-ChildItem -LiteralPath $overflowRoot -File |
                        Select-Object -First 1).FullName)
                [System.IO.File]::WriteAllText($activePath, $before + $entry + "`n")
                & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1 | Out-Null
                ([System.IO.File]::ReadAllText($activePath) + $overflowEntry) |
                    Should -Match ([regex]::Escape($first.SourceRecordId))
                ([regex]::Matches([System.IO.File]::ReadAllText($activePath), [regex]::Escape($first.SourceRecordId))).Count |
                    Should -Be 0
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix returns capacity-blocked before record or batch plus-one mutation' {
            $fixture = New-PlanFixture
            try {
                $probe = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-1 `
                    -ReviewType none -Message 'x'
                $capturePath = Join-Path $fixture.PlanDir 'capture.md'
                $probeLine = Get-Content -LiteralPath $capturePath | Where-Object {
                    $_ -match [regex]::Escape($probe.SourceRecordId)
                }
                $overhead = [System.Text.Encoding]::UTF8.GetByteCount($probeLine) - 1
                $maxBody = 'x' * (16KB - $overhead)
                $exact = & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.2 -Concern security -Requirement REQ-1 `
                    -ReviewType none -Message $maxBody
                $exactLine = Get-Content -LiteralPath $capturePath | Where-Object {
                    $_ -match [regex]::Escape($exact.SourceRecordId)
                }
                [System.Text.Encoding]::UTF8.GetByteCount($exactLine) | Should -Be 16KB
                $before = [System.IO.File]::ReadAllText($capturePath)
                $recordResult = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                    '-Kind', 'Capture', '-Phase', '1', '-Step', '1.3',
                    '-Concern', 'security', '-Requirement', 'REQ-1',
                    '-ReviewType', 'none', '-Message', ('x' * (16KB - $overhead + 1))
                )
                $recordResult.ExitCode | Should -Be 4
                $recordResult.Output | Should -Match 'capacity-blocked'
                [System.IO.File]::ReadAllText($capturePath) | Should -BeExactly $before

                foreach ($number in 1..10) { Add-Learning -Fixture $fixture -Number $number | Out-Null }
                $overflowRoot = Join-Path $fixture.PlanDir 'learning-overflow'
                [void](New-Item -ItemType Directory -Path $overflowRoot -Force)
                foreach ($number in 1..64) {
                    $seed = New-TestOverflowBatch -Record "- [seed-$number] retained batch $number"
                    [System.IO.File]::WriteAllText(
                        (Join-Path $overflowRoot "$($seed.Digest).md"),
                        $seed.Content
                    )
                }
                $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                $before = [System.IO.File]::ReadAllText($activePath)
                $batchResult = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                    '-Kind', 'Learnings', '-Phase', '1', '-Step', '1.11',
                    '-Trigger', 'reusable-pattern', '-Concern', 'maintainability-consistency',
                    '-Requirement', 'REQ-1', '-ReviewType', 'none', '-Message', 'Learning number 11'
                )
                $batchResult.ExitCode | Should -Be 4
                $batchResult.Output | Should -Match 'capacity-blocked'
                [System.IO.File]::ReadAllText($activePath) | Should -BeExactly $before
                @(Get-ChildItem -LiteralPath $overflowRoot -File -Filter '*.md').Count | Should -Be 64
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix exposes shared lock-timeout and three-conflict exhaustion statuses' {
            $fixture = New-PlanFixture
            try {
                Import-Module (Join-Path $script:repoRoot 'scripts/skalary/AtomicStore.psm1') -Force
                $status = Get-AtomicStoreStatus
                $status.CapacityBlocked | Should -Be 'capacity-blocked'

                $conflictPath = Join-Path $fixture.Root 'conflict.txt'
                [System.IO.File]::WriteAllText($conflictPath, 'seed')
                $conflict = Invoke-AtomicStoreUpdate -Path $conflictPath -MaxAttempts 3 -Transform {
                    param($current, $generation, $attempt)
                    [System.IO.File]::WriteAllText($conflictPath, "conflict-$attempt")
                    "desired-$attempt"
                }
                $conflict.Status | Should -Be 'cas-exhausted'
                $conflict.Attempts | Should -Be 3

                $holder = Join-Path $fixture.Root 'hold-lock.ps1'
                $marker = Join-Path $fixture.Root 'lock-ready'
                @'
param($Module, $Scope, $Marker)
Import-Module $Module -Force
Invoke-WithAtomicStoreLock -Scope $Scope -Action {
    [System.IO.File]::WriteAllText($Marker, 'ready')
    Start-Sleep -Seconds 30
}
'@ | Set-Content -LiteralPath $holder -Encoding utf8NoBOM
                $process = Start-Process pwsh -PassThru -ArgumentList @(
                    '-NoProfile', '-File', $holder,
                    '-Module', (Join-Path $script:repoRoot 'scripts/skalary/AtomicStore.psm1'),
                    '-Scope', $(if ($IsWindows) { $fixture.PlanDir.ToLowerInvariant() } else { $fixture.PlanDir }),
                    '-Marker', $marker
                )
                for ($attempt = 0; $attempt -lt 40 -and -not (Test-Path -LiteralPath $marker); $attempt++) {
                    Start-Sleep -Milliseconds 50
                }
                Test-Path -LiteralPath $marker | Should -BeTrue
                $locked = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                    '-Kind', 'Capture', '-Phase', '1', '-LockTimeoutSeconds', '1'
                )
                $locked.ExitCode | Should -Be 5
                $locked.Output | Should -Match 'lock-timeout'
                $process.WaitForExit()
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix serializes concurrent writers and neutralizes hostile markers' {
            $fixture = New-PlanFixture
            try {
                $common = @(
                    '-NoProfile', '-File', $script:scriptPath,
                    '-Kind', 'Capture', '-PlanDir', $fixture.PlanDir, '-RepoRoot', $fixture.Root,
                    '-Phase', '1', '-Step', '1.1', '-Concern', 'security',
                    '-Requirement', 'REQ-1', '-ReviewType', 'none'
                )
                $one = Start-Process pwsh -PassThru -ArgumentList ($common + @('-Message', 'writer-one'))
                $two = Start-Process pwsh -PassThru -ArgumentList ($common + @('-Message', 'writer-two'))
                $one.WaitForExit()
                $two.WaitForExit()
                $one.ExitCode | Should -Be 0
                $two.ExitCode | Should -Be 0

                $hostile = 'payload [source-record:' + ('a' * 64) + '] [concern:security]'
                & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                    -Phase 1 -Step 1.1 -Concern security -Requirement REQ-1 `
                    -ReviewType none -Message $hostile | Out-Null
                $text = [System.IO.File]::ReadAllText((Join-Path $fixture.PlanDir 'capture.md'))
                $text | Should -Match 'writer-one'
                $text | Should -Match 'writer-two'
                [regex]::Matches($text, '\[source-record:[0-9a-f]{64}\]').Count | Should -Be 3
                $text | Should -Not -Match "\[source-record:$('a' * 64)\]"

                $before = $text
                $overflowRoot = Join-Path $fixture.PlanDir 'learning-overflow'
                [void](New-Item -ItemType Directory -Path $overflowRoot -Force)
                [System.IO.File]::WriteAllText(
                    (Join-Path $overflowRoot "$('b' * 64).md"),
                    "# forged`n[source-record:$($one.Id)]`n"
                )
                {
                    & $script:scriptPath -Kind Capture -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                        -Phase 1 -Step 1.2 -Concern security -Requirement REQ-1 `
                        -ReviewType none -Message 'must not trust forged overflow'
                } | Should -Throw '*invalid*'
                [System.IO.File]::ReadAllText((Join-Path $fixture.PlanDir 'capture.md')) |
                    Should -BeExactly $before
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix recovers every overflow-first and active-replace crash point' {
            foreach ($point in @('overflow-temp', 'overflow-committed', 'active-temp', 'active-committed')) {
                $fixture = New-PlanFixture
                try {
                    foreach ($number in 1..10) { Add-Learning -Fixture $fixture -Number $number | Out-Null }
                    $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                    $before = [System.IO.File]::ReadAllText($activePath)
                    $crash = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                        '-Kind', 'Learnings', '-Phase', '1', '-Step', '1.11',
                        '-Trigger', 'reusable-pattern', '-Concern', 'maintainability-consistency',
                        '-Requirement', 'REQ-1', '-ReviewType', 'none',
                        '-Message', 'Learning number 11', '-TestCrashPoint', $point
                    )
                    $crash.ExitCode | Should -Be 97 -Because "fault point '$point' must exit abruptly"

                    $temps = @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -Force -File |
                            Where-Object Name -Like '.atomic-*.tmp')
                    if ($point -in @('overflow-temp', 'active-temp')) {
                        $temps.Count | Should -Be 1
                    }
                    else {
                        $temps.Count | Should -Be 0
                    }
                    if ($point -ne 'active-committed') {
                        [System.IO.File]::ReadAllText($activePath) | Should -BeExactly $before
                    }
                    else {
                        [System.IO.File]::ReadAllText($activePath) |
                            Should -Match 'Learning number 11'
                    }
                    $overflowFiles = @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -File |
                            Where-Object { $_.Directory.Name -eq 'learning-overflow' -and $_.Extension -eq '.md' })
                    if ($point -eq 'overflow-temp') {
                        $overflowFiles.Count | Should -Be 0
                    }
                    else {
                        $overflowFiles.Count | Should -Be 1
                    }

                    foreach ($temp in $temps) {
                        $temp.LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)
                    }
                    Add-Learning -Fixture $fixture -Number 11 | Out-Null

                    $active = @(Get-Content -LiteralPath $activePath | Where-Object { $_ -match '^- \[' })
                    $active.Count | Should -Be 10
                    $all = @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -File -Filter '*.md' |
                            ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
                    foreach ($number in 1..11) {
                        ([regex]::Matches($all, "Learning number $number(?!\d)")).Count |
                            Should -Be 1 -Because "fault point '$point' must preserve learning $number exactly once"
                    }
                    @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -Force -File |
                            Where-Object Name -Like '.atomic-*.tmp').Count | Should -Be 0
                }
                finally {
                    Remove-PlanFixture $fixture
                }
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix does not double-count legacy loss after overflow-first crash' {
            $fixture = New-PlanFixture
            try {
                $legacy = @(
                    '## Learnings Capture'
                    'Phase: 1'
                    ''
                    '- [1.1] [trigger:overflow-summary] Folded 4 additional learnings into this summary.'
                    ''
                ) -join "`n"
                $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                [System.IO.File]::WriteAllText(
                    $activePath,
                    $legacy,
                    [System.Text.UTF8Encoding]::new($false)
                )

                $crash = Invoke-NoteProcess -Fixture $fixture -Arguments @(
                    '-Kind', 'Learnings', '-Phase', '1',
                    '-TestCrashPoint', 'overflow-committed'
                )
                $crash.ExitCode | Should -Be 97
                [System.IO.File]::ReadAllText($activePath) | Should -Match 'overflow-summary'

                $replay = & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1
                $replay.Status | Should -Be 'legacy-loss'
                $replay.LegacyLossCount | Should -Be 1
                $all = @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -File -Filter '*.md' |
                        ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
                ([regex]::Matches($all, '\[trigger:overflow-summary\]')).Count | Should -Be 1
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix preserves identical legacy-loss occurrences' {
            $fixture = New-PlanFixture
            try {
                $summary = '- [1.1] [trigger:overflow-summary] Folded 4 additional learnings into this summary.'
                $activePath = Join-Path $fixture.PlanDir 'learnings.md'
                [System.IO.File]::WriteAllText(
                    $activePath,
                    (@('## Learnings Capture', 'Phase: 1', '', $summary, '') -join "`n"),
                    [System.Text.UTF8Encoding]::new($false)
                )
                & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1 | Out-Null

                [System.IO.File]::WriteAllText(
                    $activePath,
                    (@('## Learnings Capture', 'Phase: 1', '', $summary, '') -join "`n"),
                    [System.Text.UTF8Encoding]::new($false)
                )
                $result = & $script:scriptPath -Kind Learnings -PlanDir $fixture.PlanDir `
                    -RepoRoot $fixture.Root -Phase 1

                $result.Status | Should -Be 'legacy-loss'
                $result.LegacyLossCount | Should -Be 2
                $all = @(Get-ChildItem -LiteralPath $fixture.PlanDir -Recurse -File -Filter '*.md' |
                        ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
                ([regex]::Matches($all, '\[trigger:overflow-summary\]')).Count | Should -Be 2
                ([regex]::Matches($all, '\[legacy-observation:[0-9a-f]{64}\]')).Count |
                    Should -Be 2
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix accepts exact byte and count ceilings then rejects plus-one' {
            $records = [System.Collections.Generic.List[string]]::new()
            foreach ($number in 1..64) {
                $records.Add("- [seed-$number] " + ('x' * 8080))
            }
            $batch = New-TestOverflowBatch -Record $records.ToArray()
            $batchBytes = [System.Text.Encoding]::UTF8.GetByteCount($batch.Content)
            $records[63] += 'x' * (512KB - $batchBytes)
            $batch = New-TestOverflowBatch -Record $records.ToArray()
            [System.Text.Encoding]::UTF8.GetByteCount($batch.Content) | Should -Be 512KB

            $exactBatchFixture = New-PlanFixture
            try {
                $activePath = Join-Path $exactBatchFixture.PlanDir 'learnings.md'
                $active = @('## Learnings Capture', 'Phase: 1', '') + $records.ToArray()
                [System.IO.File]::WriteAllText(
                    $activePath,
                    ($active -join "`n") + "`n",
                    [System.Text.UTF8Encoding]::new($false)
                )
                $result = & $script:scriptPath -Kind Learnings -PlanDir $exactBatchFixture.PlanDir `
                    -RepoRoot $exactBatchFixture.Root -Phase 1 -Step 1.65 -MaxLearnings 1 `
                    -Trigger reusable-pattern -Concern maintainability-consistency `
                    -Requirement REQ-1 -ReviewType none -Message 'exact batch append'
                $result.Status | Should -Be 'complete'
                $result.OverflowCount | Should -Be 64
                (Get-Item -LiteralPath $result.OverflowFile).Length | Should -Be 512KB
            }
            finally {
                Remove-PlanFixture $exactBatchFixture
            }

            $plusBatchFixture = New-PlanFixture
            try {
                $plusRecords = [string[]]$records.ToArray().Clone()
                $plusRecords[63] += 'x'
                $activePath = Join-Path $plusBatchFixture.PlanDir 'learnings.md'
                $active = @('## Learnings Capture', 'Phase: 1', '') + $plusRecords
                $before = ($active -join "`n") + "`n"
                [System.IO.File]::WriteAllText(
                    $activePath,
                    $before,
                    [System.Text.UTF8Encoding]::new($false)
                )
                $blocked = Invoke-NoteProcess -Fixture $plusBatchFixture -Arguments @(
                    '-Kind', 'Learnings', '-Phase', '1', '-Step', '1.65', '-MaxLearnings', '1',
                    '-Trigger', 'reusable-pattern', '-Concern', 'maintainability-consistency',
                    '-Requirement', 'REQ-1', '-ReviewType', 'none', '-Message', 'plus one batch append'
                )
                $blocked.ExitCode | Should -Be 4
                [System.IO.File]::ReadAllText($activePath) | Should -BeExactly $before
                Test-Path -LiteralPath (Join-Path $plusBatchFixture.PlanDir 'learning-overflow') |
                    Should -BeFalse
            }
            finally {
                Remove-PlanFixture $plusBatchFixture
            }

            $plusRecordFixture = New-PlanFixture
            try {
                $activePath = Join-Path $plusRecordFixture.PlanDir 'learnings.md'
                $countRecords = @(1..65 | ForEach-Object { "- [count-$_] retained record $_" })
                $active = @('## Learnings Capture', 'Phase: 1', '') + $countRecords
                $before = ($active -join "`n") + "`n"
                [System.IO.File]::WriteAllText(
                    $activePath,
                    $before,
                    [System.Text.UTF8Encoding]::new($false)
                )
                $blocked = Invoke-NoteProcess -Fixture $plusRecordFixture -Arguments @(
                    '-Kind', 'Learnings', '-Phase', '1', '-Step', '1.66', '-MaxLearnings', '1',
                    '-Trigger', 'reusable-pattern', '-Concern', 'maintainability-consistency',
                    '-Requirement', 'REQ-1', '-ReviewType', 'none', '-Message', 'record count plus one'
                )
                $blocked.ExitCode | Should -Be 4
                [System.IO.File]::ReadAllText($activePath) | Should -BeExactly $before
                Test-Path -LiteralPath (Join-Path $plusRecordFixture.PlanDir 'learning-overflow') |
                    Should -BeFalse
            }
            finally {
                Remove-PlanFixture $plusRecordFixture
            }

            $probeFixture = New-PlanFixture
            try {
                $probe = & $script:scriptPath -Kind Capture -PlanDir $probeFixture.PlanDir `
                    -RepoRoot $probeFixture.Root -Phase 1 -Step 1.1 -Concern security `
                    -Requirement REQ-1 -ReviewType none -Message 'exact active log'
                $probeLine = Get-Content -LiteralPath (Join-Path $probeFixture.PlanDir 'capture.md') |
                    Where-Object { $_ -match [regex]::Escape($probe.SourceRecordId) }
                $plusProbe = & $script:scriptPath -Kind Capture -PlanDir $probeFixture.PlanDir `
                    -RepoRoot $probeFixture.Root -Phase 1 -Step 1.2 -Concern security `
                    -Requirement REQ-1 -ReviewType none -Message 'plus one active log'
                $plusProbeLine = Get-Content -LiteralPath (Join-Path $probeFixture.PlanDir 'capture.md') |
                    Where-Object { $_ -match [regex]::Escape($plusProbe.SourceRecordId) }
            }
            finally {
                Remove-PlanFixture $probeFixture
            }

            $activeFixture = New-PlanFixture
            try {
                $capturePath = Join-Path $activeFixture.PlanDir 'capture.md'
                $fixed = "## Capture`nPhase: 1`n`n$probeLine`n"
                $paddingLength = 4MB - [System.Text.Encoding]::UTF8.GetByteCount($fixed) - 1
                $seed = "## Capture`nPhase: 1`n`nNo entries for this phase.`n" +
                    ('p' * $paddingLength) + "`n"
                [System.IO.File]::WriteAllText(
                    $capturePath,
                    $seed,
                    [System.Text.UTF8Encoding]::new($false)
                )
                & $script:scriptPath -Kind Capture -PlanDir $activeFixture.PlanDir `
                    -RepoRoot $activeFixture.Root -Phase 1 -Step 1.1 -Concern security `
                    -Requirement REQ-1 -ReviewType none -Message 'exact active log' | Out-Null
                (Get-Item -LiteralPath $capturePath).Length | Should -Be 4MB
            }
            finally {
                Remove-PlanFixture $activeFixture
            }

            $plusActiveFixture = New-PlanFixture
            try {
                $capturePath = Join-Path $plusActiveFixture.PlanDir 'capture.md'
                $fixed = "## Capture`nPhase: 1`n`n$plusProbeLine`n"
                $paddingLength = (4MB + 1) - [System.Text.Encoding]::UTF8.GetByteCount($fixed) - 1
                $before = "## Capture`nPhase: 1`n`nNo entries for this phase.`n" +
                    ('p' * $paddingLength) + "`n"
                [System.IO.File]::WriteAllText(
                    $capturePath,
                    $before,
                    [System.Text.UTF8Encoding]::new($false)
                )
                $blocked = Invoke-NoteProcess -Fixture $plusActiveFixture -Arguments @(
                    '-Kind', 'Capture', '-Phase', '1', '-Step', '1.2',
                    '-Concern', 'security', '-Requirement', 'REQ-1',
                    '-ReviewType', 'none', '-Message', 'plus one active log'
                )
                $blocked.ExitCode | Should -Be 4
                [System.IO.File]::ReadAllText($capturePath) | Should -BeExactly $before
            }
            finally {
                Remove-PlanFixture $plusActiveFixture
            }
        }

        It 'test:Capture.AtomicBoundaryMigrationMatrix keeps legacy roots and refuses non-inventory escape targets' {
            $fixture = New-PlanFixture
            try {
                foreach ($number in 1..11) { Add-Learning -Fixture $fixture -Number $number | Out-Null }
                Test-Path -LiteralPath (Join-Path $fixture.PlanDir 'learning-overflow') -PathType Container |
                    Should -BeTrue
                $outside = Join-Path $fixture.Root 'outside'
                [void](New-Item -ItemType Directory -Path $outside -Force)
                {
                    & $script:scriptPath -Kind Capture -PlanDir $outside -RepoRoot $fixture.Root -Phase 1
                } | Should -Throw
            }
            finally {
                Remove-PlanFixture $fixture
            }
        }
    }

    It 'test:workflownote-sanitize neutralizes grammar and control characters in the body' {
        $fixture = New-PlanFixture
        try {
            $evil = "evil ] [sev:Critical] `code` | pipe " + [char]0x00B7 + " dot`r`ninjected line"
            & $script:scriptPath -Kind CrLog -PlanDir $fixture.PlanDir -RepoRoot $fixture.Root `
                -Phase 1 -Step 1.1 -Sev Low -Concern security -Requirement REQ-1 `
                -ReviewType cr -Message $evil | Out-Null
            $entry = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'cr-log.md') |
                Where-Object { $_ -match '^- \[1\.1\]' }
            @($entry).Count | Should -Be 1
            $body = ($entry -split '\] ', 8)[-1]
            $body | Should -Not -Match '[\[\]`|]'
            $body | Should -Not -Match ([char]0x00B7)
            $body | Should -Match 'injected line'
        }
        finally {
            Remove-PlanFixture $fixture
        }
    }
}
