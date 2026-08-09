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
