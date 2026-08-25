#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][datetime]$BeforeUtc,
    [ValidateRange(1, [int]::MaxValue)][int]$MaximumRuns = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

function Get-SiArchiveTransactionId {
    param(
        [Parameter(Mandatory)][string]$BeforeManifestDigest,
        [Parameter(Mandatory)][string]$AfterManifestDigest,
        [Parameter(Mandatory)][object[]]$Entries
    )

    $payload = [ordered]@{
        protocol = 'si-archive-journal-v1'
        beforeManifestDigest = $BeforeManifestDigest
        afterManifestDigest = $AfterManifestDigest
        entries = @($Entries | ForEach-Object {
                [ordered]@{
                    runId = [string]$_.runId
                    source = [string]$_.source
                    target = [string]$_.target
                    sha256 = [string]$_.sha256
                }
            })
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        'si-archive-journal-v1' + ($payload | ConvertTo-Json -Depth 20 -Compress)
    )
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function Resolve-SiArchiveJournalEntryPath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][ValidateSet('source', 'target')][string]$Kind,
        [Parameter(Mandatory)][string]$RunId
    )

    $rootName = if ($Kind -eq 'source') { 'runs' } else { 'archive' }
    $stateRootRelative = Get-SiStateRelativePath -Kind Root
    $pattern = '^' + [regex]::Escape($stateRootRelative) +
        "/$rootName/[0-9]{4}/[0-9]{2}/$RunId\.json$"
    if ($RelativePath -cnotmatch $pattern) {
        throw "Archive journal $Kind path '$RelativePath' is invalid."
    }
    $treeRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @($rootName)
    if (Test-Path -LiteralPath $treeRoot) {
        $treeRootItem = Get-Item -LiteralPath $treeRoot -Force
        if (($treeRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Archive journal $Kind root '$treeRoot' is a reparse point."
        }
    }
    $segments = @($RelativePath.Substring(($stateRootRelative + '/').Length) -split '/')
    $path = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments $segments
    if (-not (Test-SiPhysicalDescendant -Root $treeRoot -Path $path)) {
        throw "Archive journal $Kind path '$RelativePath' escapes its state tree."
    }
    return $path
}

function Read-SiArchiveJournal {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $contract = Get-SiStateContract
    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        if ($stream.Length -gt $contract.Limits.RunBytes) {
            throw 'Archive journal exceeds its 1 MiB limit.'
        }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -eq 0) {
                throw 'Archive journal ended before its declared length.'
            }
            $offset += $read
        }
    }
    finally {
        $stream.Dispose()
    }
    try {
        $journal = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) |
            ConvertFrom-Json -Depth 20
    }
    catch {
        throw 'Archive journal is not strict UTF-8 JSON.'
    }
    $properties = @($journal.PSObject.Properties.Name)
    $expectedProperties = @(
        'protocol', 'transactionId', 'beforeManifestDigest',
        'afterManifestDigest', 'entries'
    )
    if ($properties.Count -ne $expectedProperties.Count -or
        @($properties | Where-Object { $_ -notin $expectedProperties }).Count -gt 0 -or
        [string]$journal.protocol -cne 'si-archive-journal-v1' -or
        [string]$journal.transactionId -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$journal.beforeManifestDigest -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$journal.afterManifestDigest -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Archive journal does not match its closed contract.'
    }
    $entries = @($journal.entries)
    if ($entries.Count -lt 1 -or
        $entries.Count -gt $contract.Limits.ActiveCompletedRuns) {
        throw 'Archive journal entry count is outside the active completed-run limit.'
    }
    $runIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($entry in $entries) {
        $entryProperties = @($entry.PSObject.Properties.Name)
        if ($entryProperties.Count -ne 4 -or
            @($entryProperties | Where-Object {
                    $_ -notin @('runId', 'source', 'target', 'sha256')
                }).Count -gt 0 -or
            [string]$entry.runId -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not $runIds.Add([string]$entry.runId)) {
            throw 'Archive journal contains an invalid or duplicate entry.'
        }
        [void](Resolve-SiArchiveJournalEntryPath -RepoRoot $RepoRoot `
                -RelativePath ([string]$entry.source) -Kind source `
                -RunId ([string]$entry.runId))
        [void](Resolve-SiArchiveJournalEntryPath -RepoRoot $RepoRoot `
                -RelativePath ([string]$entry.target) -Kind target `
                -RunId ([string]$entry.runId))
    }
    $expectedId = Get-SiArchiveTransactionId `
        -BeforeManifestDigest ([string]$journal.beforeManifestDigest) `
        -AfterManifestDigest ([string]$journal.afterManifestDigest) `
        -Entries $entries
    if ([string]$journal.transactionId -cne $expectedId) {
        throw 'Archive journal failed its content-address check.'
    }
    return $journal
}

function Resolve-SiArchiveRecovery {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$JournalPath
    )

    if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'none'; Count = 0 }
    }
    $journal = Read-SiArchiveJournal -RepoRoot $RepoRoot -Path $JournalPath
    $manifestDigest = Get-SiArtifactDigest -Path (Get-SiManifestPath -RepoRoot $RepoRoot)
    $mode = if ($manifestDigest -ceq [string]$journal.beforeManifestDigest) {
        'rollback'
    }
    elseif ($manifestDigest -ceq [string]$journal.afterManifestDigest) {
        'complete'
    }
    else {
        throw 'Archive journal does not bind the current manifest generation.'
    }

    foreach ($entry in @($journal.entries)) {
        $source = Resolve-SiArchiveJournalEntryPath -RepoRoot $RepoRoot `
            -RelativePath ([string]$entry.source) -Kind source `
            -RunId ([string]$entry.runId)
        $target = Resolve-SiArchiveJournalEntryPath -RepoRoot $RepoRoot `
            -RelativePath ([string]$entry.target) -Kind target `
            -RunId ([string]$entry.runId)
        $sourceExists = Test-Path -LiteralPath $source -PathType Leaf
        $targetExists = Test-Path -LiteralPath $target -PathType Leaf
        foreach ($candidate in @($source, $target)) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                if ((Get-SiArtifactDigest -Path $candidate) -cne [string]$entry.sha256) {
                    throw "Archive recovery artifact '$candidate' failed its journal digest."
                }
            }
        }
        if ($mode -eq 'rollback') {
            if (-not $sourceExists -and -not $targetExists) {
                throw "Archive recovery lost run '$($entry.runId)'."
            }
            if (-not $sourceExists) {
                $parent = Split-Path -Parent $source
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $parent -Force)
                }
                [System.IO.File]::Move($target, $source, $false)
            }
            elseif ($targetExists) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        else {
            if (-not $targetExists) {
                throw "Committed archive target for run '$($entry.runId)' is missing."
            }
            if ($sourceExists) {
                Remove-Item -LiteralPath $source -Force
            }
        }
    }
    Remove-Item -LiteralPath $JournalPath -Force
    return [pscustomobject]@{ Status = $mode; Count = @($journal.entries).Count }
}

$stateContract = Get-SiStateContract
if ($MaximumRuns -gt $stateContract.Limits.ActiveCompletedRuns) {
    throw "MaximumRuns exceeds the active completed-run limit."
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
try {
    return Invoke-WithAtomicStoreLock -Scope (Get-SiStateLockScope -RepoRoot $root) `
        -TimeoutSeconds (Get-SiStateContract).Limits.LockSeconds -Action {
            $journalPath = Resolve-SiStatePath -RepoRoot $root `
                -Segments @($stateContract.Topology.ArchiveJournalName)
            $recovery = Resolve-SiArchiveRecovery -RepoRoot $root -JournalPath $journalPath
            $inspection = Get-SiStoreInspection -RepoRoot $root
            if ($inspection.Status -notin @('valid', 'capacity-blocked')) {
                throw "Archive-SiState refuses store status '$($inspection.Status)'."
            }
            $manifestPath = Get-SiManifestPath -RepoRoot $root
            $manifestGeneration = Get-AtomicStoreGeneration -Path $manifestPath
            $manifest = Read-SiManifest -RepoRoot $root
            $inFlightRunIds = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($entry in @($manifest.inFlight)) {
                [void]$inFlightRunIds.Add([string]$entry.runId)
            }
            $eligible = @($inspection.RunFiles | Where-Object {
                    $run = Get-Content -LiteralPath $_.FullName -Raw |
                        ConvertFrom-Json -Depth 100
                    $_.LastWriteTimeUtc -lt $BeforeUtc -and
                    (Test-SiRunStatus -Status ([string]$run.status) -Set Terminal) -and
                    -not $inFlightRunIds.Contains([string]$run.runId)
                } | Sort-Object FullName | Select-Object -First $MaximumRuns)
            if ($eligible.Count -eq 0) {
                return [pscustomobject]@{
                    Status = 'complete'; Archived = 0; Paths = @(); Recovery = $recovery.Status
                }
            }

            $archiveRoot = Resolve-SiStatePath -RepoRoot $root `
                -Segments @($stateContract.Topology.ArchiveSegments)
            $archiveDiscovery = Get-SiBoundedFileSet -Root $archiveRoot -Extension '.json' `
                -MaxFiles $stateContract.Limits.ArchivedRuns `
                -MaxFileBytes $stateContract.Limits.RunBytes `
                -MaxTotalBytes ([long]$stateContract.Limits.ArchivedRuns *
                    $stateContract.Limits.RunBytes)
            if ($archiveDiscovery.Status -ne 'complete') {
                throw "$($archiveDiscovery.Status): $($archiveDiscovery.Reason)"
            }
            $existingArchive = @($archiveDiscovery.Files)
            if ($existingArchive.Count + $eligible.Count -gt (Get-SiStateContract).Limits.ArchivedRuns) {
                throw 'capacity-blocked: SI archive limit reached.'
            }
            foreach ($group in @($existingArchive | Group-Object DirectoryName)) {
                if ($group.Count -gt $stateContract.Limits.RunsPerShard) {
                    throw "capacity-blocked: SI archive shard '$($group.Name)' exceeds 256 runs."
                }
            }

            $moves = [System.Collections.Generic.List[object]]::new()
            $manifestBeforeDigest = Get-SiArtifactDigest -Path $manifestPath
            foreach ($file in $eligible) {
                $runBytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $run = [System.Text.UTF8Encoding]::new($false, $true).GetString($runBytes) |
                    ConvertFrom-Json -Depth 100
                $created = [datetime]$run.createdAtUtc
                $target = Resolve-SiStatePath -RepoRoot $root -Segments @(
                    @($stateContract.Topology.ArchiveSegments) +
                    @($created.ToString('yyyy'), $created.ToString('MM'), $file.Name)
                )
                if (Test-Path -LiteralPath $target) {
                    throw "Archive target already exists for run '$($run.runId)'."
                }
                $moves.Add([pscustomobject][ordered]@{
                        RunId = [string]$run.runId
                        Source = $file.FullName
                        Target = $target
                        Sha256 = Get-SiArtifactDigest -Bytes $runBytes
                    })
            }
            foreach ($group in @($moves | Group-Object { Split-Path -Parent $_.Target })) {
                $existingInShard = @($existingArchive | Where-Object {
                        [string]::Equals(
                            $_.DirectoryName, [string]$group.Name,
                            [System.StringComparison]::Ordinal
                        )
                    }).Count
                if ($existingInShard + $group.Count -gt $stateContract.Limits.RunsPerShard) {
                    throw "capacity-blocked: SI archive shard '$($group.Name)' exceeds 256 runs."
                }
            }
            $archivedIds = @($moves | ForEach-Object { $_.RunId })
            $manifest.recentRuns = @($manifest.recentRuns | Where-Object {
                    $archivedIds -notcontains [string]$_.runId
                })
            $manifest.generation = [int]$manifest.generation + 1
            $manifestJson = ($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n"
            $manifestAfterDigest = Get-SiArtifactDigest -Bytes (
                [System.Text.UTF8Encoding]::new($false).GetBytes($manifestJson)
            )
            $journalEntries = @($moves | ForEach-Object {
                    [ordered]@{
                        runId = $_.RunId
                        source = [System.IO.Path]::GetRelativePath(
                            $root, $_.Source
                        ).Replace('\', '/')
                        target = [System.IO.Path]::GetRelativePath(
                            $root, $_.Target
                        ).Replace('\', '/')
                        sha256 = $_.Sha256
                    }
                })
            $journal = [ordered]@{
                protocol = 'si-archive-journal-v1'
                transactionId = Get-SiArchiveTransactionId `
                    -BeforeManifestDigest $manifestBeforeDigest `
                    -AfterManifestDigest $manifestAfterDigest `
                    -Entries $journalEntries
                beforeManifestDigest = $manifestBeforeDigest
                afterManifestDigest = $manifestAfterDigest
                entries = $journalEntries
            }
            $journalContent = ($journal | ConvertTo-Json -Depth 20 -Compress) + "`n"
            $journalWrite = Set-AtomicStoreContent -Path $journalPath `
                -Content $journalContent -Validate {
                    param($temp)
                    [void](Read-SiArchiveJournal -RepoRoot $root -Path $temp)
                }
            if ($journalWrite.Status -ne 'complete') {
                throw "Archive journal write failed with status '$($journalWrite.Status)'."
            }
            try {
                foreach ($move in $moves) {
                    if ((Get-SiArtifactDigest -Path $move.Source) -cne $move.Sha256) {
                        throw "Archive source changed for run '$($move.RunId)'."
                    }
                    $parent = Split-Path -Parent $move.Target
                    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                        [void](New-Item -ItemType Directory -Path $parent -Force)
                    }
                    [System.IO.File]::Move($move.Source, $move.Target, $false)
                }

                $write = Set-AtomicStoreContent -Path $manifestPath -Content $manifestJson `
                    -ExpectedGeneration $manifestGeneration -Validate {
                        param($temp)
                        if (-not (Get-Content -LiteralPath $temp -Raw |
                                Test-Json -SchemaFile (Join-Path $PSScriptRoot '../schemas/manifest.schema.json'))) {
                            throw 'Archive-SiState produced an invalid manifest.'
                        }
                    }
                if ($write.Status -ne 'complete') {
                    throw "Archive-SiState manifest update failed with status '$($write.Status)'."
                }
                Remove-Item -LiteralPath $journalPath -Force
            }
            catch {
                $failure = $_
                try {
                    [void](Resolve-SiArchiveRecovery -RepoRoot $root -JournalPath $journalPath)
                }
                catch {
                    throw "$($failure.Exception.Message) Archive recovery also failed: $($_.Exception.Message)"
                }
                throw $failure
            }
            return [pscustomobject]@{
                Status = 'complete'
                Archived = $moves.Count
                Paths = @($moves | ForEach-Object { $_.Target })
                Recovery = $recovery.Status
            }
        }
}
catch [System.TimeoutException] {
    return [pscustomobject]@{ Status = 'lock-timeout'; Archived = 0; Paths = @() }
}
