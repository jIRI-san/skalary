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
                rankedSet = [pscustomobject][ordered]@{ count = 0; digest = ('0' * 64); candidates = @() }
                choices = @(); proposalPr = $null
            }
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

    It 'test:SiState.SchemaManifestAndRuns validates every persisted manifest and run against the owned schemas' {
        $enqueued = & $script:enqueue -RepoRoot $script:stateRoot -RepoId 'owner/repo' `
            -PlanId '1936cb' -SourceCommit ('a' * 40)
        $enqueued.Status | Should -Be 'complete'

        $manifestPath = Join-Path $script:stateRoot 'docs/self-improvement/state.json'
        (Get-Content -LiteralPath $manifestPath -Raw |
                Test-Json -SchemaFile (Join-Path $script:siSchemas 'manifest.schema.json')) | Should -BeTrue

        $input = Write-JsonInput -Root $script:stateRoot -Value ([ordered]@{
                dueId = $enqueued.DueId
                runId = ('1' * 64)
                pinnedBaseOid = ('b' * 40)
                createdAtUtc = '2026-08-09T00:00:00.0000000Z'
            })
        $updated = & $script:update -RepoRoot $script:stateRoot -Operation Begin -InputPath $input
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
                rank = $rank
                title = 'Candidate'
                rationale = 'Because'
                sources = @('docs/review-ledger/testing.md')
                targets = @('plugins/self-improvement/skills/si/SKILL.md')
            }
        }
        $run = [pscustomobject]@{
            rankedSet = [pscustomobject]@{
                count = 2
                candidates = @((& $candidate ('1' * 64) 1))
            }
            choices = @()
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
        $resumable = [ordered]@{
            schemaVersion = 2; runId = ('4' * 64); dueId = ('5' * 64); status = 'resumable'
            createdAtUtc = '2026-08-09T00:00:00Z'; updatedAtUtc = '2026-08-09T00:00:00Z'; completedAtUtc = $null
            provenance = [ordered]@{
                repoId = 'owner/repo'; planId = '1936cb'; sourceCommit = ('a' * 40)
                pinnedBaseOid = ('b' * 40); resolverReceiptId = $null
            }
            rankedSet = [ordered]@{ count = 0; digest = ('0' * 64); candidates = @() }
            choices = @(); proposalPr = $null
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $runDir "$('4' * 64).json"),
            (($resumable | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'repairable-orphans'

        $backup = Join-Path $script:stateRoot "docs/self-improvement/backups/$('6' * 64)"
        [void](New-Item -ItemType Directory -Path $backup -Force)
        [System.IO.File]::WriteAllText((Join-Path $backup 'apply-journal.json'), '{}')
        (Get-SiStoreInspection -RepoRoot $script:stateRoot).Status | Should -Be 'apply-incomplete'
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
}

Describe 'Shared atomic writer closure' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:writers = @(
            'scripts/skalary/Update-FeedbackQueue.ps1',
            'scripts/skalary/Add-WorkflowNote.ps1',
            'scripts/skalary/LedgerStore.psm1',
            'scripts/skalary/Invoke-PhaseHarvest.ps1',
            'plugins/self-improvement/scripts/SiStateStore.psm1'
        )
        function Script:Get-NonAtomicWriters {
            param([string]$Root, [string[]]$Paths)
            return @($Paths | Where-Object {
                    $text = [System.IO.File]::ReadAllText((Join-Path $Root $_))
                    $text -notmatch "Import-Module.+AtomicStore\.psm1" -or
                    $text -notmatch '(Invoke-AtomicStoreUpdate|Invoke-WithAtomicStoreLock|Set-AtomicStoreContent)'
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
        $text = $text -replace "(?m)^Import-Module.+AtomicStore\.psm1.+\r?\n", ''
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
                            dueId = $dues[0].DueId
                            runId = ('1' * 64)
                            pinnedBaseOid = ('d' * 40)
                            createdAtUtc = '2026-08-09T00:00:00Z'
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
