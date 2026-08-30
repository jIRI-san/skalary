#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Legacy phase receipt migration' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:harvest = Join-Path $script:repoRoot 'scripts/skalary/Invoke-PhaseHarvest.ps1'
        $script:phaseState = Join-Path $script:repoRoot 'scripts/skalary/Get-PhaseExecutionState.ps1'
        $script:addNote = Join-Path $script:repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        function Get-FixtureDigest {
            param(
                [Parameter(Mandatory)][string]$Domain,
                [Parameter(Mandatory)][string[]]$Field
            )

            return [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes(
                        $Domain + [char]0 + ($Field -join [char]0)
                    )
                )
            ).ToLowerInvariant()
        }

        function Save-FixtureJson {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)]$Value
            )

            [System.IO.File]::WriteAllText(
                $Path,
                (($Value | ConvertTo-Json -Depth 20 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        function Set-LegacyReceiptId {
            param([Parameter(Mandatory)]$Receipt)

            $payloadJson = $Receipt.payload | ConvertTo-Json -Depth 20 -Compress
            $Receipt.receiptId = Get-FixtureDigest -Domain 'phase-harvest-receipt/v1' `
                -Field @($payloadJson)
        }

        function Invoke-FixtureGit {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$Argument
            )

            & git -C $Root @Argument | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Fixture git command failed: git $($Argument -join ' ')"
            }
        }

        function ConvertTo-AssertionText {
            param([AllowEmptyCollection()][object[]]$InputObject)

            return (($InputObject | Out-String) -replace '\r?\n\s*', '').Trim()
        }

        function New-MigrationFixture {
            $tempBase = if ($IsWindows) {
                [void](New-Item -ItemType Directory -Path 'C:\tmp' -Force)
                'C:\tmp'
            }
            else {
                [System.IO.Path]::GetTempPath()
            }
            $root = Join-Path $tempBase ('phase-migrate-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-30-a1b2c3-receipt-migration'
            $logs = Join-Path $planDir 'assets/logs'
            [void](New-Item -ItemType Directory -Path $logs -Force)
            $script:tempRoots.Add($root)

            @'
# a1b2c3: Receipt migration fixture
<!-- plan-id: a1b2c3 -->

## Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|---|---|---|---|
| REQ-1 | Preserve evidence | `test:PhaseReceiptMigration.Success` | 1.1 |

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|---|---|---|---|---|---|
| RISK-1 | False proof | Low | High | Re-derive immutable evidence | 1.1 |

## Phase 1: Migration

- [x] 1.1 Preserve historical evidence (REQ-1, RISK-1) `S`
'@ | Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM
            @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|---|---|---|---|
| REQ-1 | Preserve evidence | `test:PhaseReceiptMigration.Success` | 1.1 |
'@ | Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') -Encoding utf8NoBOM
            "## Capture`nPhase: 1`n`nNo entries for this phase.`n" |
                Set-Content -LiteralPath (Join-Path $logs 'capture.md') -Encoding utf8NoBOM -NoNewline
            "## CR Capture`nPhase: 1`n`nNo entries for this phase.`n" |
                Set-Content -LiteralPath (Join-Path $logs 'cr-log.md') -Encoding utf8NoBOM -NoNewline
            "## Learnings Capture`nPhase: 1`n`nNo entries for this phase.`n" |
                Set-Content -LiteralPath (Join-Path $logs 'learnings.md') -Encoding utf8NoBOM -NoNewline

            Invoke-FixtureGit -Root $root -Argument @('init', '--quiet')
            Invoke-FixtureGit -Root $root -Argument @('config', 'user.name', 'fixture')
            Invoke-FixtureGit -Root $root -Argument @('config', 'user.email', 'fixture@example.invalid')
            Invoke-FixtureGit -Root $root -Argument @(
                'remote', 'add', 'origin', 'https://github.com/example/receipt-migration.git'
            )
            & $script:addNote -Kind Capture -PlanDir $planDir -RepoRoot $root -Phase 1 `
                -Step 1.1 -Concern testing-evidence -Requirement REQ-1 -ReviewType none `
                -Message 'Preserve the committed source record during migration.' | Out-Null
            Invoke-FixtureGit -Root $root -Argument @('add', '--all')
            Invoke-FixtureGit -Root $root -Argument @('commit', '--quiet', '-m', 'source evidence')

            $created = & pwsh -NoProfile -File $script:harvest -PlanDir $planDir -Phase 1 `
                -Src autopilot -RepoRoot $root 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to create fixture receipt: $($created -join "`n")"
            }
            $receiptPath = Join-Path $planDir 'assets/harvest-receipts/phase-001.json'
            $v2Text = [System.IO.File]::ReadAllText($receiptPath)
            $v2 = $v2Text | ConvertFrom-Json -Depth 20
            $legacyCandidates = @($v2.payload.candidates | ForEach-Object {
                    [pscustomobject][ordered]@{
                        SourceId = [string]$_.SourceId
                        WorkflowSourceRecordId = [string]$_.WorkflowSourceRecordId
                        SourceKind = [string]$_.SourceKind
                        SourcePath = [string]$_.SourcePath
                        SourceBytesSha256 = [string]$_.SourceBytesSha256
                        ReviewType = [string]$_.ReviewType
                        Concern = [string]$_.Concern
                        Requirements = [string[]]@($_.Requirements)
                        Category = [string]$_.Category
                        Severity = [string]$_.Severity
                        Entry = [string]$_.Entry
                        Tags = [string[]]@($_.Tags)
                    }
                })
            $legacy = [pscustomobject][ordered]@{
                schema = 'phase-harvest-receipt/v1'
                receiptId = ''
                payload = [pscustomobject][ordered]@{
                    repo = [string]$v2.payload.repo
                    plan = [string]$v2.payload.plan
                    phase = [int]$v2.payload.phase
                    status = [string]$v2.payload.status
                    ledgerSource = [string]$v2.payload.ledgerSource
                    sources = @($v2.payload.sources)
                    candidates = $legacyCandidates
                }
            }
            Set-LegacyReceiptId -Receipt $legacy
            Save-FixtureJson -Path $receiptPath -Value $legacy
            Invoke-FixtureGit -Root $root -Argument @('add', '--all')
            Invoke-FixtureGit -Root $root -Argument @('commit', '--quiet', '-m', 'legacy receipt')

            return [pscustomobject]@{
                Root = $root
                PlanDir = $planDir
                PlanPath = Join-Path $planDir 'plan.md'
                ReceiptPath = $receiptPath
                LegacyText = [System.IO.File]::ReadAllText($receiptPath)
                NativeV2Text = $v2Text
                LegacyCommit = (& git -C $root rev-parse HEAD).Trim()
            }
        }

        function Invoke-Migration {
            param(
                [Parameter(Mandatory)]$Fixture,
                [string]$SourceRef = 'HEAD'
            )

            $output = & pwsh -NoProfile -File $script:harvest -PlanDir $Fixture.PlanDir `
                -Phase 1 -MigrateLegacyReceipt -SourceRef $SourceRef -RepoRoot $Fixture.Root 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ConvertTo-AssertionText -InputObject $output
            }
        }
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'test:PhaseReceiptMigration.Success migrates committed v1 evidence without replay and preserves provenance' {
        $fixture = New-MigrationFixture
        $ledgerBefore = Get-ChildItem -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger') -File |
            ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)" }

        $preState = & pwsh -NoProfile -File $script:phaseState -PlanPath $fixture.PlanPath `
            -Phase 1 -RepoRoot $fixture.Root -HarvestValidator $script:harvest 2>&1
        $LASTEXITCODE | Should -Be 2
        ($preState -join "`n") | Should -Match 'Malformed harvest receipt'

        $migrated = Invoke-Migration -Fixture $fixture
        $migrated.ExitCode | Should -Be 0 -Because $migrated.Output
        $migrated.Output | Should -Match 'without phase replay'
        $receipt = Get-Content -LiteralPath $fixture.ReceiptPath -Raw | ConvertFrom-Json -Depth 20
        $receipt.schema | Should -BeExactly 'phase-harvest-receipt/v2'
        $receipt.payload.candidateFormat | Should -BeExactly 'typed-source-record/v1'
        $receipt.payload.candidates[0].SourceRecord | Should -Match '\[source-record:[0-9a-f]{64}\]'
        $receipt.migration.schema | Should -BeExactly 'phase-harvest-receipt-migration/v1'
        $receipt.migration.source.schema | Should -BeExactly 'phase-harvest-receipt/v1'
        $receipt.migration.source.commit | Should -BeExactly $fixture.LegacyCommit
        $receipt.migration.source.tree | Should -Match '^[0-9a-f]{40}$'
        $receipt.migration.source.blob | Should -Match '^[0-9a-f]{40}$'
        $receipt.migration.source.sha256 | Should -Match '^[0-9a-f]{64}$'
        $receipt.migration.source.payloadSha256 | Should -Match '^[0-9a-f]{64}$'

        $pendingValidation = & pwsh -NoProfile -File $script:harvest `
            -PlanDir $fixture.PlanDir -Phase 1 -ValidateReceipt -RepoRoot $fixture.Root 2>&1
        $LASTEXITCODE | Should -Be 3
        (ConvertTo-AssertionText -InputObject $pendingValidation) |
            Should -Match 'does not match repository HEAD'
        $pendingState = & pwsh -NoProfile -File $script:phaseState -PlanPath $fixture.PlanPath `
            -Phase 1 -RepoRoot $fixture.Root -HarvestValidator $script:harvest 2>&1
        $LASTEXITCODE | Should -Be 0
        ($pendingState -join "`n").Trim() | Should -BeExactly 'close-pending'

        $ledgerAfter = Get-ChildItem -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger') -File |
            ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)" }
        $ledgerAfter | Should -Be $ledgerBefore

        $before = (Get-FileHash -LiteralPath $fixture.ReceiptPath -Algorithm SHA256).Hash
        $again = Invoke-Migration -Fixture $fixture
        $again.ExitCode | Should -Be 0 -Because $again.Output
        $again.Output | Should -Match 'content unchanged'
        (Get-FileHash -LiteralPath $fixture.ReceiptPath -Algorithm SHA256).Hash |
            Should -BeExactly $before

        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @('commit', '--quiet', '-m', 'migrate receipt')
        $state = & pwsh -NoProfile -File $script:phaseState -PlanPath $fixture.PlanPath `
            -Phase 1 -RepoRoot $fixture.Root -HarvestValidator $script:harvest 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($state -join "`n")
        ($state -join "`n").Trim() | Should -BeExactly 'closed'

        $final = & pwsh -NoProfile -File $script:harvest -PlanDir $fixture.PlanDir `
            -FinalSweep -RepoRoot $fixture.Root 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($final -join "`n")

        $archiveRoot = Join-Path $fixture.Root 'docs/implementation-plans/archived'
        [void](New-Item -ItemType Directory -Path $archiveRoot -Force)
        Move-Item -LiteralPath $fixture.PlanDir -Destination $archiveRoot
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--all')
        Invoke-FixtureGit -Root $fixture.Root -Argument @('commit', '--quiet', '-m', 'archive')
        $archivedPlan = Join-Path $archiveRoot (Split-Path $fixture.PlanDir -Leaf)
        $archivedState = & pwsh -NoProfile -File $script:phaseState `
            -PlanPath (Join-Path $archivedPlan 'plan.md') -Phase 1 -RepoRoot $fixture.Root `
            -HarvestValidator $script:harvest 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($archivedState -join "`n")
        ($archivedState -join "`n").Trim() | Should -BeExactly 'closed'
    }

    It 'fails closed for a committed malformed v1 receipt' {
        $fixture = New-MigrationFixture
        [System.IO.File]::WriteAllText(
            $fixture.ReceiptPath,
            '{',
            [System.Text.UTF8Encoding]::new($false)
        )
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @('commit', '--quiet', '-m', 'malformed receipt')

        $result = Invoke-Migration -Fixture $fixture
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'Malformed legacy harvest receipt'
    }

    It 'fails closed after committed identity, outcome, path, and evidence tampering' -ForEach @(
        @{
            Name = 'plan mismatch'
            Mutate = {
                param($receipt)
                $receipt.payload.plan = 'fedcba'
            }
            Match = 'identity or unsupported outcome'
        }
        @{
            Name = 'phase mismatch'
            Mutate = {
                param($receipt)
                $receipt.payload.phase = 2
            }
            Match = 'requested phase 1'
        }
        @{
            Name = 'unsupported outcome'
            Mutate = {
                param($receipt)
                $receipt.payload.status = 'degraded'
            }
            Match = 'identity or unsupported outcome'
        }
        @{
            Name = 'repository path escape'
            Mutate = {
                param($receipt)
                $receipt.payload.sources[0].Path = '../escape.md'
            }
            Match = 'not a confined repository-relative path'
        }
        @{
            Name = 'tampered candidate'
            Mutate = {
                param($receipt)
                $receipt.payload.candidates[0].Entry = 'forged'
            }
            Match = 'complete immutable source re-derivation'
        }
        @{
            Name = 'unprovable source record'
            Mutate = {
                param($receipt)
                $receipt.payload.candidates[0].SourceBytesSha256 = 'f' * 64
            }
            Match = 'complete immutable source re-derivation'
        }
    ) {
        param($Name, $Mutate, $Match)
        $fixture = New-MigrationFixture
        $receipt = $fixture.LegacyText | ConvertFrom-Json -Depth 20
        & $Mutate $receipt
        Set-LegacyReceiptId -Receipt $receipt
        Save-FixtureJson -Path $fixture.ReceiptPath -Value $receipt
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @('commit', '--quiet', '-m', "tamper $Name")

        $result = Invoke-Migration -Fixture $fixture
        $result.ExitCode | Should -Be 3 -Because "$Name must fail closed"
        $result.Output | Should -Match $Match
    }

    It 'fails closed when a content-addressed v1 receipt omits an immutable candidate' {
        $fixture = New-MigrationFixture
        $receipt = $fixture.LegacyText | ConvertFrom-Json -Depth 20
        $receipt.payload.status = 'empty'
        $receipt.payload.candidates = @()
        Set-LegacyReceiptId -Receipt $receipt
        Save-FixtureJson -Path $fixture.ReceiptPath -Value $receipt
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @(
            'commit', '--quiet', '-m', 'omit legacy candidate'
        )

        $result = Invoke-Migration -Fixture $fixture
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'complete immutable source re-derivation'
    }

    It 'fails closed for uncommitted source, missing refs, ambiguous identity, and conflicting v2' {
        $dirty = New-MigrationFixture
        Add-Content -LiteralPath (Join-Path $dirty.PlanDir 'assets/logs/capture.md') -Value 'dirty'
        $dirtyResult = Invoke-Migration -Fixture $dirty
        $dirtyResult.ExitCode | Should -Be 3
        $dirtyResult.Output | Should -Match 'has uncommitted changes'

        $missing = New-MigrationFixture
        $missingResult = Invoke-Migration -Fixture $missing -SourceRef ('f' * 40)
        $missingResult.ExitCode | Should -Be 3
        $missingResult.Output | Should -Match 'does not resolve to a commit'

        $ambiguous = New-MigrationFixture
        Remove-Item -LiteralPath $ambiguous.ReceiptPath
        Invoke-FixtureGit -Root $ambiguous.Root -Argument @('add', '--all')
        Invoke-FixtureGit -Root $ambiguous.Root -Argument @('commit', '--quiet', '-m', 'remove receipt')
        [System.IO.File]::WriteAllText(
            $ambiguous.ReceiptPath,
            $ambiguous.LegacyText,
            [System.Text.UTF8Encoding]::new($false)
        )
        Invoke-FixtureGit -Root $ambiguous.Root -Argument @('add', '--all')
        Invoke-FixtureGit -Root $ambiguous.Root -Argument @('commit', '--quiet', '-m', 'readd receipt')
        $ambiguousResult = Invoke-Migration -Fixture $ambiguous
        $ambiguousResult.ExitCode | Should -Be 3
        $ambiguousResult.Output | Should -Match 'ambiguous introduction history'

        $conflict = New-MigrationFixture
        [System.IO.File]::WriteAllText(
            $conflict.ReceiptPath,
            $conflict.NativeV2Text,
            [System.Text.UTF8Encoding]::new($false)
        )
        Invoke-FixtureGit -Root $conflict.Root -Argument @('add', '--all')
        Invoke-FixtureGit -Root $conflict.Root -Argument @('commit', '--quiet', '-m', 'native v2')
        $conflictResult = Invoke-Migration -Fixture $conflict
        $conflictResult.ExitCode | Should -Be 3
        $conflictResult.Output | Should -Match 'Refusing to replace an existing native v2 receipt'
    }

    It 'rejects a migrated envelope that did not immediately replace its declared v1 blob' {
        $fixture = New-MigrationFixture
        $migration = Invoke-Migration -Fixture $fixture
        $migration.ExitCode | Should -Be 0 -Because $migration.Output
        $migratedText = [System.IO.File]::ReadAllText($fixture.ReceiptPath)

        $superseding = $fixture.LegacyText | ConvertFrom-Json -Depth 20
        $superseding.payload.ledgerSource = 'ci'
        Set-LegacyReceiptId -Receipt $superseding
        Save-FixtureJson -Path $fixture.ReceiptPath -Value $superseding
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @(
            'commit', '--quiet', '-m', 'supersede legacy receipt'
        )

        [System.IO.File]::WriteAllText(
            $fixture.ReceiptPath,
            $migratedText,
            [System.Text.UTF8Encoding]::new($false)
        )
        Invoke-FixtureGit -Root $fixture.Root -Argument @('add', '--', $fixture.ReceiptPath)
        Invoke-FixtureGit -Root $fixture.Root -Argument @(
            'commit', '--quiet', '-m', 'install stale migration'
        )

        $validation = & pwsh -NoProfile -File $script:harvest -PlanDir $fixture.PlanDir `
            -Phase 1 -ValidateReceipt -RepoRoot $fixture.Root 2>&1
        $LASTEXITCODE | Should -Be 3
        (ConvertTo-AssertionText -InputObject $validation) |
            Should -Match 'intervening conflicting receipt'
    }

    It 'fails closed when migrated provenance is tampered or its source commit is unavailable' {
        $fixture = New-MigrationFixture
        (Invoke-Migration -Fixture $fixture).ExitCode | Should -Be 0
        $receipt = Get-Content -LiteralPath $fixture.ReceiptPath -Raw | ConvertFrom-Json -Depth 20
        $receipt.migration.source.commit = 'f' * 40
        $body = [pscustomobject][ordered]@{
            schema = [string]$receipt.migration.schema
            migratedAt = ([datetime]$receipt.migration.migratedAt).ToUniversalTime().ToString('o')
            tool = [string]$receipt.migration.tool
            source = $receipt.migration.source
            validation = $receipt.migration.validation
        }
        $receipt.migration.migrationId = Get-FixtureDigest `
            -Domain 'phase-harvest-receipt-migration/v1' `
            -Field @(($body | ConvertTo-Json -Depth 20 -Compress))
        Save-FixtureJson -Path $fixture.ReceiptPath -Value $receipt

        $validation = & pwsh -NoProfile -File $script:harvest -PlanDir $fixture.PlanDir `
            -Phase 1 -ValidateReceipt -RepoRoot $fixture.Root 2>&1
        $LASTEXITCODE | Should -Be 3
        (ConvertTo-AssertionText -InputObject $validation) | Should -Match 'does not exist'
    }

    It 'keeps canonical, bundled, dogfood, and SI migration consumers byte-identical' {
        $comparisons = @(
            @('scripts/skalary/Invoke-PhaseHarvest.ps1', 'plugins/continue-implementation/skills/ci/scripts/Invoke-PhaseHarvest.ps1'),
            @('scripts/skalary/Invoke-PhaseHarvest.ps1', 'plugins/autopilot/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1'),
            @('plugins/continue-implementation/skills/ci/scripts/Invoke-PhaseHarvest.ps1', '.github/skills/ci/scripts/Invoke-PhaseHarvest.ps1'),
            @('plugins/autopilot/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1', '.github/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1'),
            @('plugins/self-improvement/scripts/Get-SiHarvest.ps1', '.github/skills/si/scripts/Get-SiHarvest.ps1')
        )
        foreach ($pair in $comparisons) {
            (Get-FileHash -LiteralPath (Join-Path $script:repoRoot $pair[1]) -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath (
                        Join-Path $script:repoRoot $pair[0]
                    ) -Algorithm SHA256).Hash
        }
    }
}
