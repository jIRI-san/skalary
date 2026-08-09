#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Installed shared closure: .github/skills/si/scripts/AtomicStore.psm1
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$script:SiStateContract = [pscustomobject]@{
    ManifestVersion = 2
    RunVersion = 2
    ResolverReceiptVersion = 1
    RepairObservationVersion = 1
    RepairReceiptVersion = 1
    Status = [pscustomobject]@{
        Absent = 0; Valid = 0
        RepairableOrphans = 2; RepairableCorrupt = 2; MigrationRequired = 2
        ForwardReadonly = 3; ForwardBlocked = 3
        CapacityBlocked = 4; Invalid = 5; LockTimeout = 6
        CasConflict = 7; CasExhausted = 8; ApplyIncomplete = 9
    }
    Limits = [pscustomobject]@{
        ManifestBytes = 256KB; PendingDues = 128; RecentRunReferences = 64
        ActiveCompletedRuns = 32; ActiveInFlightRuns = 16
        ArchivedRuns = 4096; RunsPerShard = 256; RunBytes = 1MB
        RankedCandidates = 5; LockSeconds = 30; CasRetries = 3
        AuxiliaryRecordsPerKind = 256; ResolverReceipts = 512
    }
    Topology = [pscustomobject]@{
        RootSegments = @('docs', 'self-improvement'); ManifestName = 'state.json'
        ActiveRunsSegments = @('runs'); ArchiveSegments = @('archive')
        BackupSegments = @('backups'); QuarantineSegments = @('quarantine')
        ObservationSegments = @('repair-observations')
        ReceiptSegments = @('repair-receipts')
        ResolverReceiptSegments = @('resolver-receipts'); LockName = '.state.lock'
    }
    TransactionOrder = @(
        'acquire-lock', 'read-generation', 'write-random-temp', 'validate-temp',
        'recheck-generation', 'replace-run-before-manifest', 'replace-manifest', 'release-lock'
    )
}
$script:SiRepairLockHeld = $false

function Get-SiStateContract {
    [CmdletBinding()]
    param()
    return $script:SiStateContract
}

function Resolve-SiRepoRoot {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Repository root not found: $root"
    }
    return $root
}

function Resolve-SiStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Segments
    )

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $path = $root
    foreach ($segment in @('docs', 'self-improvement') + $Segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..') -or
            $segment.Contains('/') -or $segment.Contains('\')) {
            throw "Invalid SI state path segment '$segment'."
        }
        $path = Join-Path $path $segment
    }
    $full = [System.IO.Path]::GetFullPath($path)
    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved SI state path '$full' escapes repository root."
    }
    return $full
}

function Get-SiManifestPath {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('state.json')
}

function Get-SiSchemaPath {
    param([Parameter(Mandatory)][ValidateSet('manifest', 'run', 'repair-observation', 'repair-receipt')][string]$Name)
    $path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../schemas/$Name.schema.json"))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "SI state schema not found: $path"
    }
    return $path
}

function ConvertTo-SiJson {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"
}

function Test-SiJsonSchema {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$Schema
    )
    $errors = @()
    if (-not ($Json | Test-Json -SchemaFile (Get-SiSchemaPath -Name $Schema) -ErrorVariable errors)) {
        $detail = if ($errors.Count -gt 0) { [string]$errors[0] } else { 'schema mismatch' }
        throw "Invalid SI $Schema document: $detail"
    }
}

function New-SiManifest {
    return [ordered]@{
        schemaVersion = $script:SiStateContract.ManifestVersion
        generation = 0
        pending = @()
        inFlight = @()
        recentRuns = @()
    }
}

function Read-SiManifest {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$AllowAbsent
    )
    $path = Get-SiManifestPath -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($AllowAbsent) { return $null }
        throw "SI manifest not found: $path"
    }
    $json = [System.IO.File]::ReadAllText($path)
    if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:SiStateContract.Limits.ManifestBytes) {
        throw 'SI manifest exceeds the 256 KiB limit.'
    }
    Test-SiJsonSchema -Json $json -Schema manifest
    return $json | ConvertFrom-Json -Depth 100
}

function Get-SiDueId {
    param(
        [Parameter(Mandatory)][string]$RepoId,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$SourceCommit
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$RepoId|$PlanId|$SourceCommit|si-due-v1")
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-SiRunPath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RunId,
        [datetime]$Timestamp = [datetime]::UtcNow
    )
    return Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @(
        'runs', $Timestamp.ToString('yyyy'), $Timestamp.ToString('MM'), "$RunId.json"
    )
}

function Assert-SiRunIntegrity {
    param([Parameter(Mandatory)]$Run)
    if ([int]$Run.rankedSet.count -ne @($Run.rankedSet.candidates).Count) {
        throw 'Ranked-set count does not match the candidate array.'
    }
    $ids = @($Run.rankedSet.candidates | ForEach-Object { [string]$_.candidateId })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) {
        throw 'Ranked-set candidate IDs must be unique.'
    }
    $ranks = @($Run.rankedSet.candidates | ForEach-Object { [int]$_.rank })
    if (($ranks -join ',') -ne ((1..$ranks.Count) -join ',') -and $ranks.Count -gt 0) {
        throw 'Ranked-set candidates must carry contiguous rank order.'
    }
    foreach ($choice in @($Run.choices)) {
        if ($ids -notcontains [string]$choice.candidateId) {
            throw "Choice references candidate '$($choice.candidateId)' outside the ranked set."
        }
    }
}

function Write-SiRun {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Run
    )
    Assert-SiRunIntegrity -Run $Run
    $json = ConvertTo-SiJson -Value $Run
    if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:SiStateContract.Limits.RunBytes) {
        throw 'SI run exceeds the 1 MiB limit.'
    }
    Test-SiJsonSchema -Json $json -Schema run
    $path = Get-SiRunPath -RepoRoot $RepoRoot -RunId ([string]$Run.runId) -Timestamp ([datetime]$Run.createdAtUtc)
    $runFiles = @(Get-ChildItem -LiteralPath (Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('runs')) `
            -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)
    $completedCount = 0
    $inFlightCount = 0
    foreach ($file in $runFiles) {
        $existing = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100
        if ([string]$existing.status -in @('declined-before-ranking', 'no-candidates', 'completed')) {
            $completedCount++
        }
        else {
            $inFlightCount++
        }
    }
    $targetExists = Test-Path -LiteralPath $path -PathType Leaf
    $targetWasCompleted = $false
    if ($targetExists) {
        $targetWasCompleted = [string](Get-Content -LiteralPath $path -Raw |
                ConvertFrom-Json -Depth 100).status -in @('declined-before-ranking', 'no-candidates', 'completed')
    }
    $targetIsCompleted = [string]$Run.status -in @('declined-before-ranking', 'no-candidates', 'completed')
    if ($targetIsCompleted -and -not $targetWasCompleted -and
        $completedCount -ge $script:SiStateContract.Limits.ActiveCompletedRuns) {
        throw 'capacity-blocked: active completed-run limit reached.'
    }
    if (-not $targetIsCompleted -and (-not $targetExists -or $targetWasCompleted) -and
        $inFlightCount -ge $script:SiStateContract.Limits.ActiveInFlightRuns) {
        throw 'capacity-blocked: active in-flight run limit reached.'
    }
    $result = Set-AtomicStoreContent -Path $path -Content $json -Validate {
        param($temp)
        Test-SiJsonSchema -Json ([System.IO.File]::ReadAllText($temp)) -Schema run
    }
    if ($result.Status -ne 'complete') {
        throw "SI run write failed with status '$($result.Status)'."
    }
    return $path
}

function Invoke-SiManifestUpdate {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][scriptblock]$Transform
    )
    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $path = Get-SiManifestPath -RepoRoot $root
    try {
        return Invoke-WithAtomicStoreLock -Scope "$root|si-state" `
            -TimeoutSeconds $script:SiStateContract.Limits.LockSeconds -Action {
                for ($attempt = 1; $attempt -le $script:SiStateContract.Limits.CasRetries; $attempt++) {
                    $generation = Get-AtomicStoreGeneration -Path $path
                    $current = if ($generation -eq 'absent') { $null } else { [System.IO.File]::ReadAllText($path) }
                    $manifest = if ($null -eq $current) { [pscustomobject](New-SiManifest) } else {
                        Test-SiJsonSchema -Json $current -Schema manifest
                        $current | ConvertFrom-Json -Depth 100
                    }
                    $value = & $Transform $manifest $attempt
                    $manifest.generation = [int]$manifest.generation + 1
                    $json = ConvertTo-SiJson -Value $manifest
                    if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:SiStateContract.Limits.ManifestBytes) {
                        throw 'capacity-blocked: SI manifest exceeds 256 KiB.'
                    }
                    Test-SiJsonSchema -Json $json -Schema manifest
                    $write = Set-AtomicStoreContent -Path $path -Content $json `
                        -ExpectedGeneration $generation -Validate {
                            param($temp)
                            Test-SiJsonSchema -Json ([System.IO.File]::ReadAllText($temp)) -Schema manifest
                        }
                    if ($write.Status -eq 'complete') {
                        return [pscustomobject]@{
                            Status = 'complete'; Path = $path; Generation = $write.Generation
                            Attempts = $attempt; Value = $value
                        }
                    }
                }
                return [pscustomobject]@{
                    Status = 'cas-exhausted'; Path = $path
                    Attempts = $script:SiStateContract.Limits.CasRetries; Value = $null
                }
            }
    }
    catch [System.TimeoutException] {
        return [pscustomobject]@{ Status = 'lock-timeout'; Path = $path; Attempts = 0; Value = $null }
    }
}

function Add-SiDue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RepoId,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$SourceCommit
    )
    $dueId = Get-SiDueId -RepoId $RepoId -PlanId $PlanId -SourceCommit $SourceCommit
    $result = Invoke-SiManifestUpdate -RepoRoot $RepoRoot -Transform {
        param($manifest)
        $known = @($manifest.pending) + @($manifest.inFlight) + @($manifest.recentRuns)
        if (@($known | Where-Object { [string]$_.dueId -eq $dueId }).Count -gt 0) {
            return [pscustomobject]@{ DueId = $dueId; Written = $false; Note = 'already-known' }
        }
        if (@($manifest.pending).Count + @($manifest.inFlight).Count -ge $script:SiStateContract.Limits.PendingDues) {
            throw 'capacity-blocked: SI pending/in-flight due limit reached.'
        }
        $manifest.pending = @($manifest.pending) + [pscustomobject][ordered]@{
            dueId = $dueId; repoId = $RepoId; planId = $PlanId; sourceCommit = $SourceCommit
            createdAtUtc = [datetime]::UtcNow.ToString('o'); deferUntilUtc = $null
            status = 'pending'; runId = $null
        }
        return [pscustomobject]@{ DueId = $dueId; Written = $true; Note = '' }
    }
    return [pscustomobject]@{
        Status = $result.Status
        DueId = $dueId
        Written = ($result.Status -eq 'complete' -and $result.Value.Written)
        Note = if ($result.Status -eq 'complete') { $result.Value.Note } else { $result.Status }
        Attempts = $result.Attempts
    }
}

function Get-SiStoreInspection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $manifestPath = Get-SiManifestPath -RepoRoot $root
    $runsRoot = Resolve-SiStatePath -RepoRoot $root -Segments @('runs')
    $journalFiles = @(Get-ChildItem -LiteralPath (Resolve-SiStatePath -RepoRoot $root -Segments @('backups')) `
            -Filter 'apply-journal.json' -Recurse -File -ErrorAction SilentlyContinue)
    $runFiles = @(Get-ChildItem -LiteralPath $runsRoot -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)
    $observed = [System.Collections.Generic.List[object]]::new()
    $currentRuns = 0
    $forwardRuns = 0
    $corruptRuns = 0
    foreach ($file in $runFiles) {
        try {
            $json = [System.IO.File]::ReadAllText($file.FullName)
            $obj = $json | ConvertFrom-Json -Depth 100
            if ([int]$obj.schemaVersion -gt $script:SiStateContract.RunVersion) { $forwardRuns++ }
            elseif ([int]$obj.schemaVersion -lt $script:SiStateContract.RunVersion) { }
            else {
                Test-SiJsonSchema -Json $json -Schema run
                Assert-SiRunIntegrity -Run $obj
                $currentRuns++
            }
        }
        catch {
            $corruptRuns++
        }
        $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $observed.Add([pscustomobject]@{ path = $relative; sha256 = Get-AtomicStoreGeneration -Path $file.FullName })
    }

    $manifestKind = 'absent'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $raw = [System.IO.File]::ReadAllText($manifestPath)
            $manifest = $raw | ConvertFrom-Json -Depth 100
            if ([int]$manifest.schemaVersion -gt $script:SiStateContract.ManifestVersion) {
                $manifestKind = 'forward'
            }
            elseif ([int]$manifest.schemaVersion -lt $script:SiStateContract.ManifestVersion) {
                $manifestKind = 'legacy'
            }
            else {
                Test-SiJsonSchema -Json $raw -Schema manifest
                $manifestKind = 'current'
            }
        }
        catch {
            $manifestKind = 'corrupt'
        }
        $observed.Add([pscustomobject]@{
            path = 'docs/self-improvement/state.json'
            sha256 = Get-AtomicStoreGeneration -Path $manifestPath
        })
    }

    $status = if ($journalFiles.Count -gt 0) { 'apply-incomplete' }
    elseif ($runFiles.Count -gt $script:SiStateContract.Limits.ActiveCompletedRuns + $script:SiStateContract.Limits.ActiveInFlightRuns) { 'capacity-blocked' }
    elseif ($manifestKind -eq 'forward' -or $forwardRuns -gt 0) {
        if ($manifestKind -eq 'current' -or $currentRuns -gt 0 -or $corruptRuns -gt 0) { 'forward-blocked' } else { 'forward-readonly' }
    }
    elseif ($manifestKind -eq 'legacy' -or @($runFiles | Where-Object {
                try { [int](Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).schemaVersion -lt 2 } catch { $false }
            }).Count -gt 0) { 'migration-required' }
    elseif ($manifestKind -eq 'corrupt' -or $corruptRuns -gt 0) { 'repairable-corrupt' }
    elseif ($manifestKind -eq 'absent' -and $currentRuns -gt 0) { 'repairable-orphans' }
    elseif ($manifestKind -eq 'absent') { 'absent' }
    else { 'valid' }

    return [pscustomobject]@{
        Status = $status
        ExitCode = [int]$script:SiStateContract.Status.($status -replace '-(\w)', { $_.Groups[1].Value.ToUpperInvariant() })
        ManifestPath = $manifestPath
        RunFiles = $runFiles
        Observed = @($observed | Sort-Object path)
    }
}

function Get-SiObservationPayload {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$PinnedBaseOid
    )
    $inspection = Get-SiStoreInspection -RepoRoot $RepoRoot
    return [ordered]@{
        protocol = 'si-repair-observation-v1'
        pinnedBaseOid = $PinnedBaseOid
        status = $inspection.Status
        observed = @($inspection.Observed)
    }
}

function Save-SiRepairObservation {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$PinnedBaseOid
    )
    $payload = Get-SiObservationPayload -RepoRoot $RepoRoot -PinnedBaseOid $PinnedBaseOid
    $payloadJson = $payload | ConvertTo-Json -Depth 100 -Compress
    $framed = [System.Text.Encoding]::UTF8.GetBytes('si-repair-observation-v1' + $payloadJson)
    $id = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($framed)).ToLowerInvariant()
    $envelope = [ordered]@{ schemaVersion = 1; observationId = $id; payload = $payload }
    $json = ConvertTo-SiJson -Value $envelope
    Test-SiJsonSchema -Json $json -Schema repair-observation
    $path = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-observations', "$id.json")
    [void](Set-AtomicStoreContent -Path $path -Content $json)
    return [pscustomobject]@{ Status = $payload.status; ObservationId = $id; Path = $path; Payload = $payload }
}

function Invoke-SiRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet('Inspect', 'Snapshot', 'Apply', 'Rollback')][string]$Mode,
        [string]$PinnedBaseOid,
        [string]$Observation,
        [string]$Receipt
    )
    if ($Mode -ne 'Inspect' -and -not $script:SiRepairLockHeld) {
        $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
        try {
            return Invoke-WithAtomicStoreLock -Scope "$root|si-state" `
                -TimeoutSeconds $script:SiStateContract.Limits.LockSeconds -Action {
                    $script:SiRepairLockHeld = $true
                    try {
                        Invoke-SiRepair -RepoRoot $root -Mode $Mode -PinnedBaseOid $PinnedBaseOid `
                            -Observation $Observation -Receipt $Receipt
                    }
                    finally {
                        $script:SiRepairLockHeld = $false
                    }
                }
        }
        catch [System.TimeoutException] {
            return [pscustomobject]@{ Status = 'lock-timeout'; Mutated = $false }
        }
    }
    if ($Mode -in @('Inspect', 'Snapshot') -and $PinnedBaseOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw "$Mode requires -PinnedBaseOid."
    }
    if ($Mode -eq 'Inspect') {
        $payload = Get-SiObservationPayload -RepoRoot $RepoRoot -PinnedBaseOid $PinnedBaseOid
        return [pscustomobject]@{ Status = $payload.status; Payload = $payload; Mutated = $false }
    }
    if ($Mode -eq 'Snapshot') {
        return Save-SiRepairObservation -RepoRoot $RepoRoot -PinnedBaseOid $PinnedBaseOid
    }
    if ($Mode -eq 'Apply') {
        if ($Observation -notmatch '^[0-9a-f]{64}$') { throw 'Apply requires a valid -Observation id.' }
        $observationPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-observations', "$Observation.json")
        if (-not (Test-Path -LiteralPath $observationPath -PathType Leaf)) { throw "Repair observation '$Observation' not found." }
        $observationJson = Get-Content -LiteralPath $observationPath -Raw
        Test-SiJsonSchema -Json $observationJson -Schema repair-observation
        $envelope = $observationJson | ConvertFrom-Json -Depth 100
        $payloadJson = $envelope.payload | ConvertTo-Json -Depth 100 -Compress
        $calculatedObservation = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes('si-repair-observation-v1' + $payloadJson)
            )
        ).ToLowerInvariant()
        if ($envelope.observationId -ne $Observation -or $calculatedObservation -ne $Observation) {
            throw "Repair observation '$Observation' failed its content-address check."
        }
        $currentPayload = Get-SiObservationPayload -RepoRoot $RepoRoot -PinnedBaseOid ([string]$envelope.payload.pinnedBaseOid)
        if (($currentPayload | ConvertTo-Json -Depth 100 -Compress) -ne $payloadJson) {
            throw "Repair observation '$Observation' is stale; the observed store changed."
        }
        $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $Observation)
        [void](New-Item -ItemType Directory -Path $backupRoot -Force)
        $manifestPath = Get-SiManifestPath -RepoRoot $RepoRoot
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            [System.IO.File]::Copy($manifestPath, (Join-Path $backupRoot 'state.json'), $true)
        }
        else {
            [void](Set-AtomicStoreContent -Path (Join-Path $backupRoot 'manifest.absent') -Content "absent`n")
        }
        $journalPath = Join-Path $backupRoot 'apply-journal.json'
        [void](Set-AtomicStoreContent -Path $journalPath -Content (([ordered]@{
                    observationId = $Observation
                    beforeDigest = Get-AtomicStoreGeneration -Path $manifestPath
                } | ConvertTo-Json -Compress) + "`n"))
        $manifest = New-SiManifest
        if ($envelope.payload.status -eq 'migration-required' -and
            (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $legacyManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
            foreach ($field in @('pending', 'inFlight', 'recentRuns')) {
                if ($legacyManifest.PSObject.Properties.Name -contains $field) {
                    $manifest[$field] = @($legacyManifest.$field)
                }
            }
            $manifest.generation = [int]$legacyManifest.generation + 1
        }
        else {
            $manifest.generation = 1
        }
        $manifestJson = ConvertTo-SiJson -Value $manifest
        Test-SiJsonSchema -Json $manifestJson -Schema manifest
        [void](Set-AtomicStoreContent -Path $manifestPath -Content $manifestJson)
        $after = Get-AtomicStoreGeneration -Path $manifestPath
        $receiptPayload = [ordered]@{
            protocol = 'si-repair-receipt-v1'; observationId = $Observation; mode = 'apply'
            beforeDigest = [string](Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json).beforeDigest
            afterDigest = $after; createdAtUtc = [datetime]::UtcNow.ToString('o')
        }
        $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes(($receiptPayload | ConvertTo-Json -Compress))
        $receiptId = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($receiptBytes)).ToLowerInvariant()
        $receiptPayload.receiptId = $receiptId
        $receiptJson = ConvertTo-SiJson -Value $receiptPayload
        Test-SiJsonSchema -Json $receiptJson -Schema repair-receipt
        $receiptPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-receipts', "$receiptId.json")
        [void](Set-AtomicStoreContent -Path $receiptPath -Content $receiptJson)
        Remove-Item -LiteralPath $journalPath -Force
        return [pscustomobject]@{ Status = 'valid'; ReceiptId = $receiptId; ObservationId = $Observation; Mutated = $true }
    }

    $lookup = if ($Receipt) { $Receipt } else { $Observation }
    if ($lookup -notmatch '^[0-9a-f]{64}$') { throw 'Rollback requires -Receipt or -Observation.' }
    $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $lookup)
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container) -and $Receipt) {
        $receiptPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-receipts', "$Receipt.json")
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Repair receipt '$Receipt' not found." }
        $receiptJson = Get-Content -LiteralPath $receiptPath -Raw
        Test-SiJsonSchema -Json $receiptJson -Schema repair-receipt
        $storedReceipt = $receiptJson | ConvertFrom-Json -Depth 100 -DateKind String
        $receiptPayload = [ordered]@{
            protocol = [string]$storedReceipt.protocol
            observationId = [string]$storedReceipt.observationId
            mode = [string]$storedReceipt.mode
            beforeDigest = [string]$storedReceipt.beforeDigest
            afterDigest = [string]$storedReceipt.afterDigest
            createdAtUtc = [string]$storedReceipt.createdAtUtc
        }
        $calculatedReceipt = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes(($receiptPayload | ConvertTo-Json -Compress))
            )
        ).ToLowerInvariant()
        if ($storedReceipt.receiptId -ne $Receipt -or $calculatedReceipt -ne $Receipt) {
            throw "Repair receipt '$Receipt' failed its content-address check."
        }
        $lookup = [string]$storedReceipt.observationId
        $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $lookup)
    }
    $backupManifest = Join-Path $backupRoot 'state.json'
    $absentMarker = Join-Path $backupRoot 'manifest.absent'
    $manifestPath = Get-SiManifestPath -RepoRoot $RepoRoot
    if (Test-Path -LiteralPath $backupManifest -PathType Leaf) {
        [void](Set-AtomicStoreContent -Path $manifestPath -Content ([System.IO.File]::ReadAllText($backupManifest)))
    }
    elseif (Test-Path -LiteralPath $absentMarker -PathType Leaf) {
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
    }
    else {
        throw "Rollback backup for observation '$lookup' has no manifest; refusing a destructive rollback."
    }
    return [pscustomobject]@{ Status = (Get-SiStoreInspection -RepoRoot $RepoRoot).Status; ObservationId = $lookup; Mutated = $true }
}

Export-ModuleMember -Function Get-SiStateContract, Resolve-SiStatePath, New-SiManifest,
    Read-SiManifest, Get-SiDueId, Get-SiRunPath, Assert-SiRunIntegrity, Write-SiRun,
    Invoke-SiManifestUpdate, Add-SiDue, Get-SiStoreInspection, Get-SiObservationPayload,
    Save-SiRepairObservation, Invoke-SiRepair
