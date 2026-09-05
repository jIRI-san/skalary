#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Durable self-improvement state' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:siScripts = Join-Path $script:repoRoot '.github/skills/si/scripts'
        $script:siSchemas = Join-Path $script:repoRoot '.github/skills/si/schemas'
        $script:atomicModule = Join-Path $script:repoRoot 'scripts/skalary/AtomicStore.psm1'
        $script:enqueue = Join-Path $script:siScripts 'Enqueue-SiDue.ps1'
        $script:update = Join-Path $script:siScripts 'Update-SiState.ps1'
        $script:getState = Join-Path $script:siScripts 'Get-SiState.ps1'
        $script:archive = Join-Path $script:siScripts 'Archive-SiState.ps1'
        Import-Module (Join-Path $script:siScripts 'SiStateStore.psm1') -Force
        Import-Module $script:atomicModule -Force

        function Script:New-StateRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('si-state-' + [Guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            return $root
        }

        function Script:Write-JsonInput {
            param([string]$Root, $Value)
            $path = Join-Path $Root ('input-' + [Guid]::NewGuid().ToString('N') + '.json')
            [System.IO.File]::WriteAllText($path, (($Value | ConvertTo-Json -Depth 100) + "`n"))
            return $path
        }

        function Script:New-ResumableRun {
            param([string]$RunId, [string]$DueId)
            return [pscustomobject][ordered]@{
                schemaVersion = 2; runId = $RunId; dueId = $DueId; status = 'resumable'
                createdAtUtc = '2026-08-09T00:00:00Z'; updatedAtUtc = '2026-08-09T00:00:00Z'; completedAtUtc = $null
                provenance = [pscustomobject][ordered]@{
                    repoId = 'owner/repo'; planId = '1936cb'; sourceCommit = ('a' * 40)
                    pinnedBaseOid = ('b' * 40); resolverReceiptId = $null
                }
                rankedSet  = [pscustomobject][ordered]@{ count = 0; digest = ('0' * 64); candidates = @() }
                choices = @(); proposalPr = $null
            }
        }

        function Script:New-DeclinedRun {
            param([string]$RunId, [string]$DueId)
            $run = New-ResumableRun -RunId $RunId -DueId $DueId
            $run.status = 'declined-before-ranking'
            $run.updatedAtUtc = '2026-08-09T01:00:00Z'
            $run.completedAtUtc = '2026-08-09T01:00:00Z'
            return $run
        }
    }

    BeforeEach {
        $script:stateRoot = New-StateRoot
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:stateRoot) {
            Remove-Item -LiteralPath $script:stateRoot -Recurse -Force
        }
    }

    It 'test:SiState.ArtifactDigestNormalizesLineEndingsWithoutParsingCorruptJson' {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $lf = $utf8.GetBytes("{`n`"broken`" : [`n")
        $crlf = $utf8.GetBytes("{`r`n`"broken`" : [`r`n")
        $changed = $utf8.GetBytes("{`n`"different`" : [`n")

        (Get-SiArtifactDigest -Bytes $crlf) | Should -Be (Get-SiArtifactDigest -Bytes $lf)
        (Get-SiArtifactDigest -Bytes $changed) | Should -Not -Be (Get-SiArtifactDigest -Bytes $lf)
    }

    It 'test:SiState.SchemaManifestAndRuns validates every persisted manifest and run against the owned schemas' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('a' * 40)
        $enqueued.Status | Should -Be 'complete'

        $manifestPath = Join-Path $script:stateRoot 'docs/self-improvement/state.json'
        (Get-Content -LiteralPath $manifestPath -Raw |
            Test-Json -SchemaFile (Join-Path $script:siSchemas 'manifest.schema.json')) | Should -BeTrue

        $requestPath = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId         = $enqueued.DueId
                runId         = ('1' * 64)
                pinnedBaseOid = ('b' * 40)
                createdAtUtc  = '2026-08-09T00:00:00.0000000Z'
            })
        $updated = & $script:update -RepoRoot $script:stateRoot -Operation Begin `
            -InputPath $requestPath
        $updated.Status | Should -Be 'complete'

        $runPath = Join-Path $script:stateRoot "docs/self-improvement/runs/2026/08/$('1' * 64).json"
        Test-Path -LiteralPath $runPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $runPath -Raw |
            Test-Json -SchemaFile (Join-Path $script:siSchemas 'run.schema.json')) | Should -BeTrue
    }

    It 'test:SiState.RankedSetCompleteness rejects count, rank, choice, and duplicate-id gaps' {
        $candidate = {
            param($id, $rank)
            [pscustomobject]@{
                candidateId = $id
                rank        = $rank
                title       = 'Candidate'
                rationale   = 'Because'
                sources     = @('docs/review-ledger/testing.md')
                targets     = @('plugins/self-improvement/skills/si/SKILL.md')
            }
        }
        $run = [pscustomobject]@{
            rankedSet = [pscustomobject]@{
                count      = 2
                candidates = @((& $candidate ('1' * 64) 1))
            }
            choices   = @()
        }
        { Assert-SiRunIntegrity -Run $run } | Should -Throw '*count*'

        $run.rankedSet.candidates = @(
            (& $candidate ('1' * 64) 1),
            (& $candidate ('1' * 64) 2)
        )
        { Assert-SiRunIntegrity -Run $run } | Should -Throw '*unique*'

        $run.rankedSet.candidates[1].candidateId = ('2' * 64)
        $run.choices = @([pscustomobject]@{ candidateId = ('3' * 64) })
        { Assert-SiRunIntegrity -Run $run } | Should -Throw '*outside the ranked set*'
    }

    It 'test:SiState.InspectionRepairStateMatrix classifies absent, valid, orphan, corrupt, forward, and incomplete stores' {
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'absent'
        & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40) | Out-Null
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'valid'

        $manifestPath = Join-Path $script:stateRoot 'docs/self-improvement/state.json'
        [System.IO.File]::WriteAllText($manifestPath, '{broken')
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'repairable-corrupt'

        [System.IO.File]::WriteAllText($manifestPath, '{"schemaVersion":99}')
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'forward-readonly'

        Remove-Item -LiteralPath $manifestPath -Force
        $runDir = Join-Path $script:stateRoot 'docs/self-improvement/runs/2026/08'
        [void](New-Item -ItemType Directory -Path $runDir -Force)
        $orphanDueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $resumable = [ordered]@{
            schemaVersion = 2; runId = ('4' * 64); dueId = $orphanDueId; status = 'resumable'
            createdAtUtc = '2026-08-09T00:00:00Z'; updatedAtUtc = '2026-08-09T00:00:00Z'; completedAtUtc = $null
            provenance = [ordered]@{
                repoId = 'owner/repo'; planId = '1936cb'; sourceCommit = ('a' * 40)
                pinnedBaseOid = ('b' * 40); resolverReceiptId = $null
            }
            rankedSet  = [ordered]@{ count = 0; digest = ('0' * 64); candidates = @() }
            choices = @(); proposalPr = $null
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $runDir "$('4' * 64).json"),
            (($resumable | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'repairable-orphans'

        $observationId = '6' * 64
        $backup = Join-Path $script:stateRoot "docs/self-improvement/backups/$observationId"
        [void](New-Item -ItemType Directory -Path $backup -Force)
        $journalPath = Join-Path $backup 'apply-journal.json'
        [System.IO.File]::WriteAllText(
            $journalPath,
            (([ordered]@{
                        schemaVersion = 1
                        observationId = $observationId
                        beforeDigest = 'absent'
                        stage = 'backup-complete'
                    } | ConvertTo-Json -Compress) + "`n")
        )
        $inspection = Get-SiStoreInspection -RepoRoot $script:stateRoot
        $inspection.Status | Should -Be 'apply-incomplete'
        $inspection.IncompleteApplies.Count | Should -Be 1
        $inspection.IncompleteApplies[0].observationId | Should -Be $observationId
        $inspection.IncompleteApplies[0].stage | Should -Be 'backup-complete'
        $inspection.IncompleteApplies[0].journalPath | Should -Be (
            "docs/self-improvement/backups/$observationId/apply-journal.json"
        )
        $metadata = & $script:getState -RepoRoot $script:stateRoot
        $metadata.IncompleteApplies[0].observationId | Should -Be $observationId

        [System.IO.File]::WriteAllText($journalPath, "{}`n")
        $invalidJournal = Get-SiStoreInspection -RepoRoot $script:stateRoot
        $invalidJournal.IncompleteApplies[0].observationId | Should -Be $observationId
        $invalidJournal.IncompleteApplies[0].stage | Should -Be 'invalid'

        [System.IO.File]::WriteAllText(
            $journalPath,
            (([ordered]@{
                        schemaVersion = 1
                        observationId = '9' * 64
                        beforeDigest = 'absent'
                        stage = 'mutation-started'
                    } | ConvertTo-Json -Compress) + "`n")
        )
        $mismatchedJournal = Get-SiStoreInspection -RepoRoot $script:stateRoot
        $mismatchedJournal.IncompleteApplies[0].observationId | Should -Be $observationId
        $mismatchedJournal.IncompleteApplies[0].stage | Should -Be 'invalid'

        $nestedId = 'a' * 64
        $nestedBackup = Join-Path (
            Split-Path -Parent $backup
        ) "nested/$nestedId"
        [void](New-Item -ItemType Directory -Path $nestedBackup -Force)
        [System.IO.File]::WriteAllText(
            (Join-Path $nestedBackup 'apply-journal.json'),
            (([ordered]@{
                        schemaVersion = 1
                        observationId = $nestedId
                        beforeDigest = 'absent'
                        stage = 'backup-complete'
                    } | ConvertTo-Json -Compress) + "`n")
        )
        $nestedJournal = (Get-SiStoreInspection -RepoRoot $script:stateRoot).IncompleteApplies |
            Where-Object observationId -EQ $nestedId
        $nestedJournal.stage | Should -Be 'invalid'
    }

    It 'test:SiState.VersionMigrationRepairRollback snapshots exact observations and restores the pre-repair version' {
        $stateDir = Join-Path $script:stateRoot 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        $manifestPath = Join-Path $stateDir 'state.json'
        $legacy = '{"schemaVersion":1,"generation":7,"pending":[],"inFlight":[],"recentRuns":[]}' + "`n"
        [System.IO.File]::WriteAllText($manifestPath, $legacy)
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'migration-required'

        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot -PinnedBaseOid ('a' * 40)
        $snapshot.ObservationId | Should -Match '^[0-9a-f]{64}$'
        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply -Observation $snapshot.ObservationId
        $applied.Status | Should -Be 'valid'
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'valid'

        $rolledBack = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback -Receipt $applied.ReceiptId
        $rolledBack.Status | Should -Be 'migration-required'
        [System.IO.File]::ReadAllText($manifestPath) | Should -Be $legacy
    }

    It 'test:SiState.VersionMigrationRepairRollback rejects a mutated repair receipt before rollback' {
        $stateDir = Join-Path $script:stateRoot 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        [System.IO.File]::WriteAllText(
            (Join-Path $stateDir 'state.json'),
            '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}'
        )
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot -PinnedBaseOid ('a' * 40)
        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply -Observation $snapshot.ObservationId
        $receiptPath = Join-Path $stateDir "repair-receipts/$($applied.ReceiptId).json"
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 20
        $receipt.createdAtUtc = '2026-01-01T00:00:00Z'
        [System.IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 20 -Compress) + "`n"))

        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback -Receipt $applied.ReceiptId
        } | Should -Throw '*content-address check*'
    }

    It 'test:SiState.InspectionRepairStateMatrix refuses Apply for valid and forward stores' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('f' * 40)
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        $validBytes = [System.IO.File]::ReadAllBytes($manifestPath)
        $validSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)

        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $validSnapshot.ObservationId
        } | Should -Throw "*refuses observed status 'valid'*"
        [System.IO.File]::ReadAllBytes($manifestPath) | Should -Be $validBytes
        $enqueued.DueId | Should -Match '^[0-9a-f]{64}$'

        [System.IO.File]::WriteAllText($manifestPath, '{"schemaVersion":99}')
        $forwardBytes = [System.IO.File]::ReadAllBytes($manifestPath)
        $forwardSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $forwardSnapshot.ObservationId
        } | Should -Throw "*refuses observed status 'forward-readonly'*"
        [System.IO.File]::ReadAllBytes($manifestPath) | Should -Be $forwardBytes
    }

    It 'test:SiState.InspectionRepairStateMatrix rebuilds a parseable manifest without schemaVersion' {
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force)
        [System.IO.File]::WriteAllText($manifestPath, '{}')
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $snapshot.Status | Should -Be 'repairable-corrupt'

        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId).Status | Should -Be 'valid'
        (Read-SiManifest -RepoRoot $script:stateRoot).schemaVersion | Should -Be 2
    }

    It 'test:SiState.InspectionRepairStateMatrix blocks Apply while another observation journal exists' {
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force)
        [System.IO.File]::WriteAllText($manifestPath, '{broken')
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $otherId = '0' * 64
        $otherJournal = Join-Path $script:stateRoot (
            "docs/self-improvement/backups/$otherId/apply-journal.json"
        )
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $otherJournal) -Force)
        [System.IO.File]::WriteAllText(
            $otherJournal,
            (([ordered]@{
                        schemaVersion = 1; observationId = $otherId
                        beforeDigest = '0' * 64; stage = 'backup-pending'
                    } | ConvertTo-Json -Compress) + "`n")
        )

        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId
        } | Should -Throw '*another SI repair*'
        [System.IO.File]::ReadAllText($manifestPath) | Should -Be '{broken'
    }

    It 'test:SiState.VersionMigrationRepairRollback preserves current manifest state while repairing runs' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('c' * 40)
        $runId = 'a' * 64
        $runPath = Get-SiRunPath -RepoRoot $script:stateRoot -RunId $runId `
            -Timestamp ([datetime]'2026-08-09T00:00:00Z')
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runPath) -Force)
        [System.IO.File]::WriteAllText($runPath, '{broken')
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $snapshot.Status | Should -Be 'repairable-corrupt'

        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
            -Observation $snapshot.ObservationId

        $applied.Status | Should -Be 'valid'
        $manifest = Read-SiManifest -RepoRoot $script:stateRoot
        @($manifest.pending | Where-Object dueId -EQ $enqueued.DueId).Count |
            Should -Be 1
        Test-Path -LiteralPath $runPath | Should -BeFalse

        $legacyRunId = 'b' * 64
        $legacyDueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $legacyPath = Write-SiRun -RepoRoot $script:stateRoot -Run (
            New-ResumableRun -RunId $legacyRunId -DueId $legacyDueId
        )
        $legacy = Get-Content -LiteralPath $legacyPath -Raw | ConvertFrom-Json -Depth 100
        $legacy.schemaVersion = 1
        [System.IO.File]::WriteAllText(
            $legacyPath,
            (($legacy | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        $migration = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $migration.Status | Should -Be 'migration-required'

        $migrationApplied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
            -Observation $migration.ObservationId
        $migrationApplied.Status | Should -Be 'valid'
        [int](Get-Content -LiteralPath $legacyPath -Raw |
                ConvertFrom-Json -Depth 100).schemaVersion | Should -Be 2
        @((Read-SiManifest -RepoRoot $script:stateRoot).pending |
                Where-Object dueId -EQ $enqueued.DueId).Count | Should -Be 1

        $stateRoot = Join-Path $script:stateRoot 'docs/self-improvement'
        $relativeRun = [System.IO.Path]::GetRelativePath(
            $script:stateRoot, $legacyPath
        )
        $legacyBackup = Join-Path $stateRoot (
            "backups/$($migration.ObservationId)/files/$relativeRun"
        )
        [System.IO.File]::WriteAllBytes(
            $legacyPath,
            [System.IO.File]::ReadAllBytes($legacyBackup)
        )
        $migrationRollback = Invoke-SiRepair -RepoRoot $script:stateRoot `
            -Mode Rollback -Receipt $migrationApplied.ReceiptId
        $migrationRollback.Status | Should -Be 'migration-required'
        [int](Get-Content -LiteralPath $legacyPath -Raw |
                ConvertFrom-Json -Depth 100).schemaVersion | Should -Be 1
    }

    It 'test:SiState.VersionMigrationRepairRollback binds observations to exact artifact bytes' {
        $stateDir = Join-Path $script:stateRoot 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        $manifestPath = Join-Path $stateDir 'state.json'
        $legacyCrLf = '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}' +
            "`r`n"
        [System.IO.File]::WriteAllText($manifestPath, $legacyCrLf)
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)

        [System.IO.File]::WriteAllText(
            $manifestPath,
            $legacyCrLf.Replace('"generation":0', '"generation":1')
        )

        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId
        } | Should -Throw '*stale*'
        Test-Path -LiteralPath (
            Join-Path $stateDir "backups/$($snapshot.ObservationId)/apply-journal.json"
        ) | Should -BeFalse
    }

    It 'test:SiState.VersionMigrationRepairRollback inspects empty artifacts and restores corrupt bytes exactly' {
        $stateDir = Join-Path $script:stateRoot 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        $manifestPath = Join-Path $stateDir 'state.json'
        [System.IO.File]::WriteAllBytes($manifestPath, [byte[]]@())
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-corrupt'

        Remove-Item -LiteralPath $manifestPath -Force
        $runId = 'c' * 64
        $runPath = Join-Path $stateDir "runs/2026/08/$runId.json"
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runPath) -Force)
        $corruptBytes = [byte[]]@(0xff, 0xfe, 0x00, 0x7b)
        [System.IO.File]::WriteAllBytes($runPath, $corruptBytes)
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('b' * 40)
        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
            -Observation $snapshot.ObservationId
        $newerRunBytes = [byte[]]@(0x7b, 0x7d)
        [System.IO.File]::WriteAllBytes($runPath, $newerRunBytes)
        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
                -Receipt $applied.ReceiptId
        } | Should -Throw '*recreated after apply*'
        [System.IO.File]::ReadAllBytes($runPath) | Should -Be $newerRunBytes
        Remove-Item -LiteralPath $runPath -Force
        $rolledBack = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
            -Receipt $applied.ReceiptId

        $rolledBack.Status | Should -Be 'repairable-corrupt'
        [System.IO.File]::ReadAllBytes($runPath) | Should -Be $corruptBytes
    }

    It 'test:SiState.VersionMigrationRepairRollback authenticates the exact rollback backup set' {
        $stateDir = Join-Path $script:stateRoot 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        $manifestPath = Join-Path $stateDir 'state.json'
        $legacy = '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}' +
            "`n"
        [System.IO.File]::WriteAllText($manifestPath, $legacy)
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('d' * 40)
        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
            -Observation $snapshot.ObservationId
        $backupFiles = Join-Path $stateDir "backups/$($snapshot.ObservationId)/files"
        $manifestBackup = Join-Path $backupFiles 'docs/self-improvement/state.json'

        [System.IO.File]::WriteAllText($manifestBackup, 'tampered')
        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
                -Receipt $applied.ReceiptId
        } | Should -Throw '*observation digest*'
        [System.IO.File]::WriteAllText($manifestBackup, $legacy)

        $injected = Join-Path $backupFiles 'docs/self-improvement/runs/injected.json'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $injected) -Force)
        [System.IO.File]::WriteAllText($injected, '{}')
        {
            Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
                -Receipt $applied.ReceiptId
        } | Should -Throw '*does not exactly match*'
        Remove-Item -LiteralPath $injected -Force

        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
                -Receipt $applied.ReceiptId).Status | Should -Be 'migration-required'
        [System.IO.File]::ReadAllText($manifestPath) | Should -Be $legacy
    }

    It 'test:SiState.VersionMigrationRepairRollback reconstructs a corrupt manifest while migrating legacy runs' {
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force)
        [System.IO.File]::WriteAllText($manifestPath, '{broken')
        $runId = 'e' * 64
        $runDueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $runPath = Write-SiRun -RepoRoot $script:stateRoot -Run (
            New-ResumableRun -RunId $runId -DueId $runDueId
        )
        $legacyRun = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json -Depth 100
        $legacyRun.schemaVersion = 1
        [System.IO.File]::WriteAllText(
            $runPath,
            (($legacyRun | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $snapshot.Status | Should -Be 'repairable-corrupt'

        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId).Status | Should -Be 'valid'
        [int](Get-Content -LiteralPath $runPath -Raw |
                ConvertFrom-Json -Depth 100).schemaVersion | Should -Be 2
        @((Read-SiManifest -RepoRoot $script:stateRoot).inFlight |
                Where-Object runId -EQ $runId).Count | Should -Be 1
    }

    It 'test:SiState.InspectionRepairStateMatrix rejects repair backup sources that escape through a descendant link' -Skip:$IsWindows {
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) (
            'si-state-outside-' + [Guid]::NewGuid().ToString('N') + '.json'
        )
        try {
            $run = New-ResumableRun -RunId ('7' * 64) -DueId ('8' * 64)
            [System.IO.File]::WriteAllText(
                $outside,
                (($run | ConvertTo-Json -Depth 20 -Compress) + "`n")
            )
            $runDir = Join-Path $script:stateRoot 'docs/self-improvement/runs/2026/08'
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            [void](New-Item -ItemType SymbolicLink `
                    -Path (Join-Path $runDir "$('7' * 64).json") -Target $outside)

            $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
                -PinnedBaseOid ('a' * 40)
            $snapshot.Status | Should -Be 'invalid'
            {
                Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                    -Observation $snapshot.ObservationId
            } | Should -Throw "*refuses observed status 'invalid'*"

            Test-Path -LiteralPath (
                Join-Path $script:stateRoot (
                    "docs/self-improvement/backups/$($snapshot.ObservationId)/apply-journal.json"
                )
            ) | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $outside) {
                Remove-Item -LiteralPath $outside -Force
            }
        }
    }

    It 'test:SiState.InspectionRepairStateMatrix rejects a linked backup descendant' -Skip:$IsWindows {
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) (
            'si-backup-outside-' + [Guid]::NewGuid().ToString('N')
        )
        try {
            [void](New-Item -ItemType Directory -Path $outside -Force)
            $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
            [void](New-Item -ItemType Directory -Path (
                    Split-Path -Parent $manifestPath
                ) -Force)
            [System.IO.File]::WriteAllText(
                $manifestPath,
                '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}'
            )
            $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
                -PinnedBaseOid ('a' * 40)
            $backupRoot = Join-Path $script:stateRoot (
                "docs/self-improvement/backups/$($snapshot.ObservationId)"
            )
            [void](New-Item -ItemType Directory -Path $backupRoot -Force)
            [void](New-Item -ItemType SymbolicLink `
                    -Path (Join-Path $backupRoot 'files') -Target $outside)

            {
                Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                    -Observation $snapshot.ObservationId
            } | Should -Throw '*refuses reparse point*'
            @(Get-ChildItem -LiteralPath $outside -File -Recurse).Count | Should -Be 0
        }
        finally {
            if (Test-Path -LiteralPath $outside) {
                Remove-Item -LiteralPath $outside -Recurse -Force
            }
        }
    }

    It 'test:SiState.ConcurrentCrashCasExhaustion returns the closed status after three generation conflicts' {
        $path = Join-Path $script:stateRoot 'state.txt'
        [System.IO.File]::WriteAllText($path, 'seed')
        $result = Invoke-AtomicStoreUpdate -Path $path -MaxAttempts 3 -Transform {
            param($current, $generation, $attempt)
            [System.IO.File]::WriteAllText($path, "conflict-$attempt")
            return "desired-$attempt"
        }
        $result.Status | Should -Be 'cas-exhausted'
        $result.Attempts | Should -Be 3
        [System.IO.File]::ReadAllText($path) | Should -Be 'conflict-3'
        @(Get-ChildItem -LiteralPath $script:stateRoot -Filter '.atomic-*.tmp').Count | Should -Be 0
    }

    It 'test:SiState.ConcurrentCrashCasExhaustion reuses prepared side effects after a manifest conflict' {
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force)
        $sideEffects = [pscustomobject]@{ Count = 0 }
        $result = Invoke-SiManifestUpdate -RepoRoot $script:stateRoot -Transform {
            param($manifest, $attempt, $prepared)
            if ($null -eq $prepared) {
                $sideEffects.Count++
                $prepared = [pscustomobject]@{ Token = 'run-written' }
                $conflict = New-SiManifest
                [System.IO.File]::WriteAllText(
                    $manifestPath,
                    (($conflict | ConvertTo-Json -Depth 20 -Compress) + "`n")
                )
            }
            $manifest.pending = @()
            return $prepared
        }

        $result.Status | Should -Be 'complete'
        $result.Attempts | Should -Be 2
        $result.Value.Token | Should -Be 'run-written'
        $sideEffects.Count | Should -Be 1
    }

    It 'keeps state limits, statuses, topology, and prepared retries module-owned' {
        $contract = Get-SiStateContract
        $contract.Limits.RecentRunReferences | Should -Be 64
        [string[]]$contract.RunStatuses.Terminal |
            Should -Be @('declined-before-ranking', 'no-candidates', 'completed')
        (Get-SiStateRelativePath -Kind Manifest) |
            Should -Be 'docs/self-improvement/state.json'

        $consumerPaths = Get-ChildItem -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/scripts'
        ) -Include '*.ps1', '*.psm1' -Recurse | Where-Object Name -NE 'SiStateStore.psm1'
        $consumerText = @($consumerPaths | ForEach-Object {
                [System.IO.File]::ReadAllText($_.FullName)
            }) -join "`n"
        $consumerText | Should -Not -Match [regex]::Escape(
            "@('declined-before-ranking', 'no-candidates', 'completed')"
        )
        $consumerText | Should -Not -Match 'Select-Object\s+-First\s+63'
        $consumerText | Should -Not -Match "'docs/self-improvement(?:/[^']*)?'"

        $updateText = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/self-improvement/scripts/Update-SiState.ps1')
        )
        $updateText | Should -Match 'param\(\$manifest,\s*\$attempt,\s*\$prepared\)'
        $updateText | Should -Match 'if\s*\(\$null\s+-ne\s+\$prepared\)'
    }

    It 'test:SiState.ConcurrentCrashCasExhaustion blocks the seventeenth active run before mutation' {
        for ($index = 0; $index -lt 16; $index++) {
            $runId = $index.ToString('x').PadLeft(64, '0')
            $dueId = ($index + 32).ToString('x').PadLeft(64, '0')
            Write-SiRun -RepoRoot $script:stateRoot -Run (
                New-ResumableRun -RunId $runId -DueId $dueId
            ) | Out-Null
        }
        $plusOneId = ('f' * 64)
        {
            Write-SiRun -RepoRoot $script:stateRoot -Run (
                New-ResumableRun -RunId $plusOneId -DueId ('e' * 64)
            )
        } | Should -Throw '*capacity-blocked*'
        @(Get-ChildItem -LiteralPath (Join-Path $script:stateRoot 'docs/self-improvement/runs') `
                -Filter '*.json' -Recurse -File).Count | Should -Be 16
    }

    It 'allows a matching partial Begin retry when all in-flight slots are occupied' {
        $targetDue = '1' * 64
        $targetRun = '2' * 64
        Write-SiRun -RepoRoot $script:stateRoot -Run (
            New-ResumableRun -RunId $targetRun -DueId $targetDue
        ) | Out-Null
        $inFlight = for ($index = 0; $index -lt 16; $index++) {
            [pscustomobject][ordered]@{
                dueId = if ($index -eq 0) { $targetDue } else {
                    ($index + 32).ToString('x').PadLeft(64, '0')
                }
                repoId = 'owner/repo'
                planId = '1936cb'
                sourceCommit = 'a' * 40
                createdAtUtc = '2026-08-09T00:00:00Z'
                status = 'in-flight'
                runId = if ($index -eq 0) { $targetRun } else {
                    ($index + 64).ToString('x').PadLeft(64, '0')
                }
            }
        }
        $manifestPath = Join-Path $script:stateRoot 'docs/self-improvement/state.json'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (([ordered]@{
                        schemaVersion = 2
                        generation = 16
                        pending = @()
                        inFlight = @($inFlight)
                        recentRuns = @()
                    } | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        $requestPath = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId = $targetDue
                runId = $targetRun
                pinnedBaseOid = 'b' * 40
            })

        $retried = & $script:update -RepoRoot $script:stateRoot `
            -Operation Begin -InputPath $requestPath

        $retried.Status | Should -Be 'complete'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -Depth 100
        @($manifest.inFlight).Count | Should -Be 16
        @($manifest.inFlight | Where-Object dueId -EQ $targetDue).Count | Should -Be 1
    }

    It 'rejects lifecycle replay when the active due is bound to another run' {
        $dueId = '7' * 64
        $boundRunId = '8' * 64
        $requestedRunId = '9' * 64
        $manifest = New-SiManifest
        $manifest.inFlight = @([pscustomobject][ordered]@{
                dueId = $dueId
                repoId = 'owner/repo'
                planId = '1936cb'
                sourceCommit = 'a' * 40
                createdAtUtc = '2026-08-09T00:00:00Z'
                deferUntilUtc = $null
                status = 'in-flight'
                runId = $boundRunId
            })
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force)
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        $requestPath = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId = $dueId
                runId = $requestedRunId
                pinnedBaseOid = 'b' * 40
            })

        {
            & $script:update -RepoRoot $script:stateRoot -Operation Begin `
                -InputPath $requestPath
        } | Should -Throw "*already bound to run '$boundRunId'*"
        Test-Path -LiteralPath (
            Get-SiRunPath -RepoRoot $script:stateRoot -RunId $requestedRunId
        ) | Should -BeFalse
    }

    It 'rejects non-Begin transitions while the due is still pending' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('d' * 40)
        $runId = 'd' * 64
        Write-SiRun -RepoRoot $script:stateRoot -Run (
            New-ResumableRun -RunId $runId -DueId $enqueued.DueId
        ) | Out-Null
        $requestPath = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId = $enqueued.DueId
                runId = $runId
                resolverReceiptId = 'e' * 64
                rankedSet = [ordered]@{
                    count = 0
                    digest = '0' * 64
                    candidates = @()
                }
            })

        {
            & $script:update -RepoRoot $script:stateRoot -Operation RecordRanking `
                -InputPath $requestPath
        } | Should -Throw '*requires due*bound in-flight*'
        (Get-Content -LiteralPath (
                Get-SiRunPath -RepoRoot $script:stateRoot -RunId $runId `
                    -Timestamp ([datetime]'2026-08-09T00:00:00Z')
            ) -Raw | ConvertFrom-Json).status | Should -Be 'resumable'
    }

    It 'repairs run-first graph divergence and requeues a due whose run is corrupt' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('e' * 40)
        $runId = '6' * 64
        $run = New-ResumableRun -RunId $runId -DueId $enqueued.DueId
        $run.provenance.sourceCommit = 'e' * 40
        $runPath = Write-SiRun -RepoRoot $script:stateRoot -Run $run
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-orphans'
        $orphanSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $orphanSnapshot.ObservationId).Status | Should -Be 'valid'
        $manifest = Read-SiManifest -RepoRoot $script:stateRoot
        @($manifest.pending | Where-Object dueId -EQ $enqueued.DueId).Count |
            Should -Be 0
        @($manifest.inFlight | Where-Object runId -EQ $runId).Count | Should -Be 1

        [System.IO.File]::WriteAllText($runPath, '{broken')
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-corrupt'
        $corruptSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $corruptSnapshot.ObservationId).Status | Should -Be 'valid'
        $repaired = Read-SiManifest -RepoRoot $script:stateRoot
        @($repaired.inFlight | Where-Object runId -EQ $runId).Count | Should -Be 0
        $pending = @($repaired.pending | Where-Object dueId -EQ $enqueued.DueId)
        $pending.Count | Should -Be 1
        $pending[0].status | Should -Be 'pending'
        $pending[0].runId | Should -BeNullOrEmpty
    }

    It 'classifies a schema-valid run at a noncanonical path as repairable' {
        $runId = '4' * 64
        $dueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $run = New-ResumableRun -RunId $runId -DueId $dueId
        $wrongPath = Join-Path $script:stateRoot (
            "docs/self-improvement/runs/2026/08/$('3' * 64).json"
        )
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $wrongPath) -Force)
        [System.IO.File]::WriteAllText(
            $wrongPath,
            (($run | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        $manifest = New-SiManifest
        $manifest.inFlight = @([pscustomobject][ordered]@{
                dueId = $dueId; repoId = 'owner/repo'; planId = '1936cb'
                sourceCommit = 'a' * 40; createdAtUtc = '2026-08-09T00:00:00Z'
                deferUntilUtc = $null; status = 'in-flight'; runId = $runId
            })
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )

        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-corrupt'
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $applied = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
            -Observation $snapshot.ObservationId
        $applied.Status | Should -Be 'valid'
        Test-Path -LiteralPath $wrongPath | Should -BeFalse
        $repaired = Read-SiManifest -RepoRoot $script:stateRoot
        @($repaired.inFlight).Count | Should -Be 0
        @($repaired.pending | Where-Object dueId -EQ $dueId).Count | Should -Be 1
        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Rollback `
                -Receipt $applied.ReceiptId).Status | Should -Be 'repairable-corrupt'
        Test-Path -LiteralPath $wrongPath | Should -BeTrue
    }

    It 'quarantines duplicate run ownership and leaves one pending due' {
        $dueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $first = New-ResumableRun -RunId ('1' * 64) -DueId $dueId
        $second = New-ResumableRun -RunId ('2' * 64) -DueId $dueId
        $third = New-ResumableRun -RunId ('3' * 64) -DueId $dueId
        $firstPath = Write-SiRun -RepoRoot $script:stateRoot -Run $first
        $secondPath = Write-SiRun -RepoRoot $script:stateRoot -Run $second
        $thirdPath = Write-SiRun -RepoRoot $script:stateRoot -Run $third
        $manifest = New-SiManifest
        $manifest.pending = @([pscustomobject][ordered]@{
                dueId = $dueId; repoId = 'owner/repo'; planId = '1936cb'
                sourceCommit = 'a' * 40; createdAtUtc = '2026-08-09T00:00:00Z'
                deferUntilUtc = $null; status = 'pending'; runId = $null
            })
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-orphans'
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)

        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId).Status | Should -Be 'valid'
        Test-Path -LiteralPath $firstPath | Should -BeFalse
        Test-Path -LiteralPath $secondPath | Should -BeFalse
        Test-Path -LiteralPath $thirdPath | Should -BeFalse
        $repaired = Read-SiManifest -RepoRoot $script:stateRoot
        @($repaired.pending | Where-Object dueId -EQ $dueId).Count | Should -Be 1
        @($repaired.inFlight).Count | Should -Be 0
    }

    It 'quarantines parseable schema-invalid runs without projecting their fields' {
        $runPath = Join-Path $script:stateRoot (
            "docs/self-improvement/runs/2026/08/$('7' * 64).json"
        )
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runPath) -Force)
        [System.IO.File]::WriteAllText($runPath, '{}')
        $snapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $snapshot.Status | Should -Be 'repairable-corrupt'

        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $snapshot.ObservationId).Status | Should -Be 'valid'
        Test-Path -LiteralPath $runPath | Should -BeFalse
        @((Read-SiManifest -RepoRoot $script:stateRoot).pending).Count | Should -Be 0
    }

    It 'canonicalizes duplicate pending dues and rebuilds in-flight provenance' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('1' * 40)
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        $manifest = Read-SiManifest -RepoRoot $script:stateRoot
        $manifest.pending = @($manifest.pending) + $manifest.pending[0]
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-orphans'
        $duplicateSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $duplicateSnapshot.ObservationId).Status | Should -Be 'valid'
        @((Read-SiManifest -RepoRoot $script:stateRoot).pending |
                Where-Object dueId -EQ $enqueued.DueId).Count | Should -Be 1

        $runId = '8' * 64
        $requestPath = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId = $enqueued.DueId
                runId = $runId
                pinnedBaseOid = 'b' * 40
                createdAtUtc = '2026-08-09T00:00:00Z'
            })
        (& $script:update -RepoRoot $script:stateRoot -Operation Begin `
                -InputPath $requestPath).Status | Should -Be 'complete'
        $manifest = Read-SiManifest -RepoRoot $script:stateRoot
        $manifest.inFlight[0].repoId = 'forged/repo'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n")
        )
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'repairable-orphans'
        $provenanceSnapshot = Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        (Invoke-SiRepair -RepoRoot $script:stateRoot -Mode Apply `
                -Observation $provenanceSnapshot.ObservationId).Status | Should -Be 'valid'
        (Read-SiManifest -RepoRoot $script:stateRoot).inFlight[0].repoId |
            Should -Be 'owner/repo'
    }

    It 'test:SiState.BoundedManifestPagingAndRepair preserves manifest-referenced runs during archive' {
        $protectedRunId = '3' * 64
        $protectedDueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('a' * 40)
        $archiveRunId = '5' * 64
        $archiveDueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('b' * 40)
        $protectedPath = Write-SiRun -RepoRoot $script:stateRoot -Run (
            New-ResumableRun -RunId $protectedRunId -DueId $protectedDueId
        )
        $archiveRun = New-DeclinedRun -RunId $archiveRunId -DueId $archiveDueId
        $archiveRun.provenance.sourceCommit = 'b' * 40
        $archivePath = Write-SiRun -RepoRoot $script:stateRoot -Run $archiveRun
        $manifest = New-SiManifest
        $manifest.inFlight = @([pscustomobject][ordered]@{
                dueId = $protectedDueId
                repoId = 'owner/repo'
                planId = '1936cb'
                sourceCommit = 'a' * 40
                createdAtUtc = '2026-08-09T00:00:00Z'
                deferUntilUtc = $null
                status = 'in-flight'
                runId = $protectedRunId
            })
        $manifest.recentRuns = @([pscustomobject][ordered]@{
                runId = $archiveRunId
                dueId = $archiveDueId
                status = 'declined-before-ranking'
                path = "docs/self-improvement/runs/2026/08/$archiveRunId.json"
                completedAtUtc = '2026-08-09T01:00:00Z'
            })
        $manifestPath = Join-Path $script:stateRoot 'docs/self-improvement/state.json'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            (($manifest | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )

        $result = & $script:archive -RepoRoot $script:stateRoot `
            -BeforeUtc ([datetime]::UtcNow.AddDays(1))

        $result.Status | Should -Be 'complete'
        $result.Archived | Should -Be 1
        Test-Path -LiteralPath $protectedPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $archivePath -PathType Leaf | Should -BeFalse
        $after = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -Depth 20
        @($after.inFlight | Where-Object runId -EQ $protectedRunId).Count | Should -Be 1
        @($after.recentRuns | Where-Object runId -EQ $archiveRunId).Count | Should -Be 0
    }

    It 'test:SiState.BoundedManifestPagingAndRepair recovers an interrupted archive before continuing' {
        $runId = '6' * 64
        $dueId = Get-SiDueId -RepoId 'owner/repo' -PlanId '1936cb' `
            -SourceCommit ('c' * 40)
        $run = New-DeclinedRun -RunId $runId -DueId $dueId
        $run.provenance.sourceCommit = 'c' * 40
        $source = Write-SiRun -RepoRoot $script:stateRoot -Run $run
        $manifest = New-SiManifest
        $manifest.recentRuns = @([pscustomobject][ordered]@{
                runId = $runId
                dueId = $dueId
                status = 'declined-before-ranking'
                path = "docs/self-improvement/runs/2026/08/$runId.json"
                completedAtUtc = '2026-08-09T01:00:00Z'
            })
        $manifestPath = Get-SiManifestPath -RepoRoot $script:stateRoot
        $manifestJson = ($manifest | ConvertTo-Json -Depth 20 -Compress) + "`n"
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson)
        $beforeDigest = Get-SiArtifactDigest -Path $manifestPath
        $afterManifest = New-SiManifest
        $afterManifest.generation = 1
        $afterJson = ($afterManifest | ConvertTo-Json -Depth 20 -Compress) + "`n"
        $afterDigest = Get-SiArtifactDigest -Bytes (
            [System.Text.UTF8Encoding]::new($false).GetBytes($afterJson)
        )
        $target = Join-Path $script:stateRoot (
            "docs/self-improvement/archive/2026/08/$runId.json"
        )
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        $entry = [ordered]@{
            runId = $runId
            source = "docs/self-improvement/runs/2026/08/$runId.json"
            target = "docs/self-improvement/archive/2026/08/$runId.json"
            sha256 = Get-SiArtifactDigest -Path $source
        }
        $payload = [ordered]@{
            protocol = 'si-archive-journal-v1'
            beforeManifestDigest = $beforeDigest
            afterManifestDigest = $afterDigest
            entries = @($entry)
        }
        $transactionId = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes(
                    'si-archive-journal-v1' +
                    ($payload | ConvertTo-Json -Depth 20 -Compress)
                )
            )
        ).ToLowerInvariant()
        $journal = [ordered]@{
            protocol = 'si-archive-journal-v1'
            transactionId = $transactionId
            beforeManifestDigest = $beforeDigest
            afterManifestDigest = $afterDigest
            entries = @($entry)
        }
        $journalPath = Join-Path $script:stateRoot (
            'docs/self-improvement/archive-journal.json'
        )
        [System.IO.File]::WriteAllText(
            $journalPath,
            (($journal | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        [System.IO.File]::Move($source, $target, $false)

        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status |
            Should -Be 'archive-incomplete'
        $result = & $script:archive -RepoRoot $script:stateRoot `
            -BeforeUtc ([datetime]::UtcNow.AddDays(1))

        $result.Status | Should -Be 'complete'
        $result.Recovery | Should -Be 'rollback'
        Test-Path -LiteralPath $journalPath | Should -BeFalse
        Test-Path -LiteralPath $source | Should -BeFalse
        Test-Path -LiteralPath $target -PathType Leaf | Should -BeTrue
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'valid'
    }

    It 'test:SiState.BoundedManifestPagingAndRepair rejects the active run plus-one during discovery' {
        $runsRoot = Join-Path $script:stateRoot 'docs/self-improvement/runs/2026/08'
        [void](New-Item -ItemType Directory -Path $runsRoot -Force)
        foreach ($index in 0..48) {
            $name = $index.ToString('x64') + '.json'
            [System.IO.File]::WriteAllText((Join-Path $runsRoot $name), '{}')
        }

        $inspection = Get-SiStoreInspection -RepoRoot $script:stateRoot

        $inspection.Status | Should -Be 'capacity-blocked'
        @($inspection.RunFiles).Count | Should -Be 49
    }
}

Describe 'Shared atomic writer closure' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:writers = @(
            'scripts/skalary/Update-FeedbackQueue.ps1',
            'scripts/skalary/Add-WorkflowNote.ps1',
            'scripts/skalary/LedgerStore.psm1',
            'scripts/skalary/Invoke-PhaseHarvest.ps1',
            'plugins/self-improvement/scripts/SiStateStore.psm1',
            'plugins/self-improvement/scripts/Get-SiHarvest.ps1'
        )
        function Script:Get-NonAtomicWriters {
            param([string]$Root, [string[]]$Paths)
            return @($Paths | Where-Object {
                    $text = [System.IO.File]::ReadAllText((Join-Path $Root $_))
                    $text -notmatch "Import-Module.+AtomicStore\.psm1" -or
                    $text -notmatch '(Invoke-AtomicStoreUpdate|Invoke-WithAtomicStoreLock|Set-AtomicStore(?:Content|Bytes))' -or
                    $text -match '(?:\[System\.IO\.File\]::WriteAll(?:Text|Bytes)|(?m)^\s*Set-Content\b)'
                })
        }
    }

    It 'test:AtomicStore.AllWritersUseSharedPrimitive covers every canonical writer and fails its direct-writer negative fixture' {
        @(Get-NonAtomicWriters -Root $script:repoRoot -Paths $script:writers).Count | Should -Be 0

        $fixture = Join-Path $TestDrive 'repo'
        foreach ($writer in $script:writers) {
            $target = Join-Path $fixture $writer
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
            Copy-Item -LiteralPath (Join-Path $script:repoRoot $writer) -Destination $target
        }
        $direct = Join-Path $fixture 'scripts/skalary/Add-WorkflowNote.ps1'
        $text = [System.IO.File]::ReadAllText($direct)
        $text += "`n[System.IO.File]::WriteAllText(`$path, `$content)`n"
        [System.IO.File]::WriteAllText($direct, $text)

        Get-NonAtomicWriters -Root $fixture -Paths $script:writers |
            Should -Contain 'scripts/skalary/Add-WorkflowNote.ps1'
    }
}

Describe 'Installed SI state paging and repair' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/self-improvement'

        function Script:New-InstalledSiRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('si-installed-' + [Guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 100
            foreach ($file in @($manifest.files)) {
                $source = Join-Path $script:pluginRoot ([string]$file.src)
                $target = Join-Path $root ('.github/' + [string]$file.dest)
                $parent = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $parent -Force)
                }
                Copy-Item -LiteralPath $source -Destination $target
            }
            return $root
        }
    }

    BeforeEach {
        $script:consumer = New-InstalledSiRoot
        $script:installedScripts = Join-Path $script:consumer '.github/skills/si/scripts'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:consumer) {
            Remove-Item -LiteralPath $script:consumer -Recurse -Force
        }
    }

    It 'test:SiState.BoundedManifestPagingAndRepair pages metadata and rebuilds an orphan manifest from the self-improvement payload alone' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 100
        $declared = @($manifest.scaffolds | ForEach-Object { [string]$_.path })
        foreach ($required in @(
                'docs/self-improvement/state.json',
                'docs/self-improvement/runs/<yyyy>/<mm>/<run>.json',
                'docs/self-improvement/archive/<yyyy>/<mm>/<run>.json',
                'docs/self-improvement/archive-journal.json',
                'docs/self-improvement/backups/<observation>/**',
                'docs/self-improvement/quarantine/index.json',
                'docs/self-improvement/quarantine/<observation>/**',
                'docs/self-improvement/repair-observations/<observation>.json',
                'docs/self-improvement/repair-receipts/<receipt>.json',
                'docs/self-improvement/resolver-receipts/<receipt>.json'
            )) {
            $declared | Should -Contain $required
        }

        $enqueue = Join-Path $script:installedScripts 'Enqueue-SiDue.ps1'
        $getState = Join-Path $script:installedScripts 'Get-SiState.ps1'
        $update = Join-Path $script:installedScripts 'Update-SiState.ps1'
        $repair = Join-Path $script:installedScripts 'Repair-SiState.ps1'
        $stateDir = Join-Path $script:consumer 'docs/self-improvement'
        $dues = @()
        foreach ($suffix in @('a', 'b', 'c')) {
            $dues += & $enqueue -RepoRoot $script:consumer -RepoId 'consumer/repo' `
                -PlanId '1936cb' -SourceCommit ($suffix * 40)
        }
        $page1 = & $getState -RepoRoot $script:consumer -PageSize 2
        $page1.Items.Count | Should -Be 2
        $page1.NextCursor | Should -Be '2'
        @($page1.Items[0].PSObject.Properties.Name) | Should -Be @('dueId', 'runId', 'status')
        $page2 = & $getState -RepoRoot $script:consumer -PageSize 2 -Cursor $page1.NextCursor
        $page2.Items.Count | Should -Be 1
        $page2.NextCursor | Should -BeNullOrEmpty

        $inputPath = Join-Path $script:consumer 'begin.json'
        [System.IO.File]::WriteAllText($inputPath, (([ordered]@{
                        dueId         = $dues[0].DueId
                        runId         = ('1' * 64)
                        pinnedBaseOid = ('d' * 40)
                        createdAtUtc  = '2026-08-09T00:00:00Z'
                    } | ConvertTo-Json -Compress) + "`n"))
        (& $update -RepoRoot $script:consumer -Operation Begin -InputPath $inputPath).Status |
            Should -Be 'complete'
        Remove-Item -LiteralPath (Join-Path $script:consumer 'docs/self-improvement/state.json') -Force

        (& $repair -RepoRoot $script:consumer -Mode Inspect -PinnedBaseOid ('d' * 40)).Status |
            Should -Be 'repairable-orphans'
        $snapshot = & $repair -RepoRoot $script:consumer -Mode Snapshot -PinnedBaseOid ('d' * 40)
        $applied = & $repair -RepoRoot $script:consumer -Mode Apply -Observation $snapshot.ObservationId
        $applied.Status | Should -Be 'valid'
        $repaired = & $getState -RepoRoot $script:consumer -PageSize 2
        $repaired.InFlightCount | Should -Be 1
        $repaired.Items[0].dueId | Should -Be $dues[0].DueId

        $rolledBack = & $repair -RepoRoot $script:consumer -Mode Rollback -Receipt $applied.ReceiptId
        $rolledBack.Status | Should -Be 'repairable-orphans'
        $rolledBack.ReceiptId | Should -Match '^[0-9a-f]{64}$'
        Test-Path -LiteralPath (
            Join-Path $stateDir "backups/$($snapshot.ObservationId)/apply-journal.json"
        ) | Should -BeFalse
    }

    It 'test:SiState.RepairReceiptGatesApplyRollback rejects stale observations and requires the exact apply receipt' {
        $repair = Join-Path $script:installedScripts 'Repair-SiState.ps1'
        $getState = Join-Path $script:installedScripts 'Get-SiState.ps1'
        $stateDir = Join-Path $script:consumer 'docs/self-improvement'
        [void](New-Item -ItemType Directory -Path $stateDir -Force)
        $manifestPath = Join-Path $stateDir 'state.json'
        [System.IO.File]::WriteAllText($manifestPath, '{broken')
        $corruptMetadata = & $getState -RepoRoot $script:consumer
        $corruptMetadata.Status | Should -Be 'repairable-corrupt'
        $corruptMetadata.Items.Count | Should -Be 0

        $legacy = '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}'
        [System.IO.File]::WriteAllText($manifestPath, $legacy)
        $snapshot = & $repair -RepoRoot $script:consumer -Mode Snapshot -PinnedBaseOid ('e' * 40)

        [System.IO.File]::WriteAllText($manifestPath, $legacy + ' ')
        { & $repair -RepoRoot $script:consumer -Mode Apply -Observation $snapshot.ObservationId } |
            Should -Throw '*stale*'
        [System.IO.File]::WriteAllText($manifestPath, $legacy)

        $applied = & $repair -RepoRoot $script:consumer -Mode Apply -Observation $snapshot.ObservationId
        { & $repair -RepoRoot $script:consumer -Mode Apply -Observation $snapshot.ObservationId } |
            Should -Throw '*stale*'
        { & $repair -RepoRoot $script:consumer -Mode Rollback -Observation $snapshot.ObservationId } |
            Should -Throw '*requires its apply receipt*'
        { & $repair -RepoRoot $script:consumer -Mode Rollback -Receipt ('f' * 64) } |
            Should -Throw '*not found*'

        $rolledBack = & $repair -RepoRoot $script:consumer -Mode Rollback -Receipt $applied.ReceiptId
        $rolledBack.Status | Should -Be 'migration-required'
        $rollbackReceipt = Get-Content -LiteralPath (
            Join-Path $stateDir "repair-receipts/$($rolledBack.ReceiptId).json"
        ) -Raw | ConvertFrom-Json
        $rollbackReceipt.mode | Should -Be 'rollback'
        $rollbackReceipt.observationId | Should -Be $snapshot.ObservationId
    }
}
