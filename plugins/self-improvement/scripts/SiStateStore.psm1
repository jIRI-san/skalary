#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Installed shared closure: .github/skills/si/scripts/AtomicStore.psm1
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force

$script:SiStateContract = [pscustomobject]@{
    ManifestVersion          = 2
    RunVersion               = 2
    ResolverReceiptVersion   = 1
    RepairObservationVersion = 1
    RepairReceiptVersion     = 1
    Status                   = [pscustomobject]@{
        Absent = 0; Valid = 0
        RepairableOrphans = 2; RepairableCorrupt = 2; MigrationRequired = 2
        ForwardReadonly = 3; ForwardBlocked = 3
        CapacityBlocked = 4; Invalid = 5; LockTimeout = 6
        CasConflict = 7; CasExhausted = 8; ApplyIncomplete = 9
    }
    Limits                   = [pscustomobject]@{
        ManifestBytes = 256KB; PendingDues = 128; RecentRunReferences = 64
        ActiveCompletedRuns = 32; ActiveInFlightRuns = 16
        ArchivedRuns = 4096; RunsPerShard = 256; RunBytes = 1MB
        RankedCandidates = 5; LockSeconds = 30; CasRetries = 3
        AuxiliaryRecordsPerKind = 256; ResolverReceipts = 512; HarvestIndexBytes = 8MB
    }
    RunStatuses              = [pscustomobject]@{
        Terminal         = @('declined-before-ranking', 'no-candidates', 'completed')
        Active           = @('resumable', 'ranked', 'proposal-pending')
        ProposalAdmitted = @('proposal-pending', 'no-candidates')
        Completed        = @('completed', 'no-candidates')
        BeginResume      = @('ranked', 'proposal-pending', 'no-candidates', 'completed')
    }
    Transitions              = [pscustomobject]@{
        Begin           = @('resumable')
        RecordRanking   = @('resumable')
        RecordChoices   = @('ranked')
        ProposalPending = @('ranked', 'proposal-pending')
        Complete        = @('resumable', 'proposal-pending')
    }
    Topology                 = [pscustomobject]@{
        RootSegments = @('docs', 'self-improvement'); ManifestName = 'state.json'
        ActiveRunsSegments = @('runs'); ArchiveSegments = @('archive')
        BackupSegments = @('backups'); QuarantineSegments = @('quarantine')
        ObservationSegments = @('repair-observations')
        ReceiptSegments     = @('repair-receipts')
        ResolverReceiptSegments = @('resolver-receipts'); HarvestIndexName = 'harvest-index.json'
        LockName            = '.state.lock'
    }
    TransactionOrder         = @(
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

function Test-SiRunStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)]
        [ValidateSet('Terminal', 'Active', 'ProposalAdmitted', 'Completed', 'BeginResume')]
        [string]$Set
    )

    return [string[]]$script:SiStateContract.RunStatuses.$Set -ccontains $Status
}

function Get-SiStateRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'Root', 'Manifest', 'ActiveRuns', 'Archive', 'Backups', 'Quarantine',
            'RepairObservations', 'RepairReceipts', 'ResolverReceipts', 'HarvestIndex'
        )]
        [string]$Kind,
        [string[]]$Child = @()
    )

    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in @($script:SiStateContract.Topology.RootSegments)) {
        $segments.Add([string]$segment)
    }
    switch ($Kind) {
        'Manifest' { $segments.Add([string]$script:SiStateContract.Topology.ManifestName) }
        'ActiveRuns' {
            foreach ($segment in @($script:SiStateContract.Topology.ActiveRunsSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'Archive' {
            foreach ($segment in @($script:SiStateContract.Topology.ArchiveSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'Backups' {
            foreach ($segment in @($script:SiStateContract.Topology.BackupSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'Quarantine' {
            foreach ($segment in @($script:SiStateContract.Topology.QuarantineSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'RepairObservations' {
            foreach ($segment in @($script:SiStateContract.Topology.ObservationSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'RepairReceipts' {
            foreach ($segment in @($script:SiStateContract.Topology.ReceiptSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'ResolverReceipts' {
            foreach ($segment in @($script:SiStateContract.Topology.ResolverReceiptSegments)) {
                $segments.Add([string]$segment)
            }
        }
        'HarvestIndex' { $segments.Add([string]$script:SiStateContract.Topology.HarvestIndexName) }
    }
    foreach ($segment in @($Child)) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..') -or
            $segment.Contains('/') -or $segment.Contains('\')) {
            throw "Invalid SI state relative path segment '$segment'."
        }
        $segments.Add($segment)
    }
    return @($segments) -join '/'
}

function Resolve-SiRepoRoot {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $root = [System.IO.Path]::TrimEndingDirectorySeparator(
        [System.IO.Path]::GetFullPath($RepoRoot)
    )
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Repository root not found: $root"
    }
    return $root
}

function Get-SiStateLockScope {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $stateRoot = Resolve-SiPhysicalPath -Path (
        Split-Path -Parent (Get-SiManifestPath -RepoRoot $root)
    )
    $stateRoot = [System.IO.Path]::TrimEndingDirectorySeparator($stateRoot)
    if ($IsWindows) { $stateRoot = $stateRoot.ToLowerInvariant() }
    return "$stateRoot|si-state"
}

function Resolve-SiPhysicalPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $pathRoot
    foreach ($segment in @($fullPath.Substring($pathRoot.Length) -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $segment
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $target = $item.ResolveLinkTarget($true)
                if ($null -eq $target) {
                    throw "Cannot resolve SI state link '$candidate'."
                }
                $current = [System.IO.Path]::GetFullPath($target.FullName)
                continue
            }
        }
        $current = [System.IO.Path]::GetFullPath($candidate)
    }
    return $current
}

function Test-SiPhysicalDescendant {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $physicalRoot = Resolve-SiPhysicalPath -Path $Root
    $physicalPath = Resolve-SiPhysicalPath -Path $Path
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $prefix = $physicalRoot.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    return $physicalPath.StartsWith($prefix, $comparison)
}

function Resolve-SiStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Segments
    )

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $path = $root
    foreach ($segment in @($script:SiStateContract.Topology.RootSegments) + $Segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..') -or
            $segment.Contains('/') -or $segment.Contains('\')) {
            throw "Invalid SI state path segment '$segment'."
        }
        $path = Join-Path $path $segment
    }
    $full = [System.IO.Path]::GetFullPath($path)
    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $full.StartsWith($prefix, $pathComparison)) {
        throw "Resolved SI state path '$full' escapes repository root."
    }
    if (-not (Test-SiPhysicalDescendant -Root $root -Path $full)) {
        throw "Resolved SI state path '$full' escapes repository root via link."
    }
    return $full
}

function Get-SiManifestPath {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return Resolve-SiStatePath -RepoRoot $RepoRoot `
        -Segments @([string]$script:SiStateContract.Topology.ManifestName)
}

function Get-SiSchemaPath {
    param([Parameter(Mandatory)][ValidateSet('manifest', 'run', 'resolver-receipt', 'repair-observation', 'repair-receipt')][string]$Name)
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
        generation    = 0
        pending       = @()
        inFlight      = @()
        recentRuns    = @()
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

function Get-SiRepoId {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $gitExitCode = 1
    $remote = try {
        $remoteOutput = & git -C $root remote get-url origin 2>$null
        $gitExitCode = $LASTEXITCODE
        ([string]($remoteOutput | Select-Object -First 1)).Trim()
    }
    catch {
        ''
    }
    if ($gitExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($remote)) {
        $uri = $null
        if ([System.Uri]::TryCreate($remote, [System.UriKind]::Absolute, [ref]$uri) -and
            -not [string]::IsNullOrWhiteSpace($uri.Host)) {
            $repositoryPath = $uri.AbsolutePath.Trim('/').Replace('\', '/')
            if ($repositoryPath.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
                $repositoryPath = $repositoryPath.Substring(0, $repositoryPath.Length - 4)
            }
            return 'origin:' + $uri.Host.ToLowerInvariant() + '/' + $repositoryPath
        }
        $scp = [regex]::Match($remote, '^(?:[^@]+@)?(?<host>[^:]+):(?<path>.+)$')
        if ($scp.Success) {
            $repositoryPath = $scp.Groups['path'].Value.Trim('/').Replace('\', '/')
            if ($repositoryPath.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
                $repositoryPath = $repositoryPath.Substring(0, $repositoryPath.Length - 4)
            }
            return 'origin:' + $scp.Groups['host'].Value.ToLowerInvariant() + '/' + $repositoryPath
        }
        $digest = [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($remote)
        )
        return 'origin-sha256:' + [Convert]::ToHexString($digest).ToLowerInvariant()
    }
    return 'path:' + $root.Replace('\', '/').TrimEnd('/')
}

function Get-SiArtifactDigest {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Bytes')]
        [AllowEmptyCollection()][byte[]]$Bytes
    )
    if ($PSCmdlet.ParameterSetName -eq 'Bytes') {
        return [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($Bytes)
        ).ToLowerInvariant()
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-SiArtifactDigest -Bytes ([System.IO.File]::ReadAllBytes($Path))
    }
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes('si-absent-v1')
        )
    ).ToLowerInvariant()
}

function Get-SiRunPath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RunId,
        [datetime]$Timestamp = [datetime]::UtcNow
    )
    return Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @(
        @($script:SiStateContract.Topology.ActiveRunsSegments) +
        @($Timestamp.ToString('yyyy'), $Timestamp.ToString('MM'), "$RunId.json")
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
    $choiceIds = @($Run.choices | ForEach-Object { [string]$_.candidateId })
    if (@($choiceIds | Select-Object -Unique).Count -ne $choiceIds.Count) {
        throw 'Choice candidate IDs must be unique.'
    }
    if ($choiceIds.Count -gt 0 -and
        (($choiceIds | Sort-Object) -join ',') -ne (($ids | Sort-Object) -join ',')) {
        throw 'Choices must cover the complete ranked candidate set.'
    }
    if ([string]$Run.status -in @('resumable', 'declined-before-ranking')) {
        if ([string]$Run.rankedSet.digest -ne ('0' * 64)) {
            throw 'Unranked runs must carry the zero ranked-set digest.'
        }
        return
    }
    $candidateBodies = @($Run.rankedSet.candidates | ForEach-Object {
            [pscustomobject][ordered]@{
                title = [string]$_.title
                rationale = [string]$_.rationale
                sources = [string[]]$_.sources
                targets = [string[]]$_.targets
            }
        })
    $canonical = New-SiRankedCandidates -Candidate $candidateBodies
    if (($canonical.CandidateIds -join ',') -ne ($ids -join ',')) {
        throw 'Ranked-set candidate IDs failed canonical verification.'
    }
    if ([string]$Run.rankedSet.digest -ne [string]$canonical.RankedSetDigest) {
        throw 'Ranked-set digest failed canonical verification.'
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
    $runFiles = @(Get-ChildItem -LiteralPath (Resolve-SiStatePath -RepoRoot $RepoRoot `
                -Segments @($script:SiStateContract.Topology.ActiveRunsSegments)) `
            -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)
    $completedCount = 0
    $inFlightCount = 0
    foreach ($file in $runFiles) {
        $existing = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100
        if (Test-SiRunStatus -Status ([string]$existing.status) -Set Terminal) {
            $completedCount++
        }
        else {
            $inFlightCount++
        }
    }
    $targetExists = Test-Path -LiteralPath $path -PathType Leaf
    $targetWasCompleted = $false
    if ($targetExists) {
        $targetWasCompleted = Test-SiRunStatus -Status ([string](Get-Content -LiteralPath $path -Raw |
                    ConvertFrom-Json -Depth 100).status) -Set Terminal
    }
    $targetIsCompleted = Test-SiRunStatus -Status ([string]$Run.status) -Set Terminal
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
        return Invoke-WithAtomicStoreLock -Scope (Get-SiStateLockScope -RepoRoot $root) `
            -TimeoutSeconds $script:SiStateContract.Limits.LockSeconds -Action {
            $backupsRoot = Resolve-SiStatePath -RepoRoot $root `
                -Segments @($script:SiStateContract.Topology.BackupSegments)
            if (@(Get-ChildItem -LiteralPath $backupsRoot -Filter 'apply-journal.json' `
                    -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0) {
                throw 'apply-incomplete: SI manifest mutation is blocked until repair rollback.'
            }
            $preparedValue = $null
            for ($attempt = 1; $attempt -le $script:SiStateContract.Limits.CasRetries; $attempt++) {
                $generation = Get-AtomicStoreGeneration -Path $path
                $current = if ($generation -eq 'absent') { $null } else { [System.IO.File]::ReadAllText($path) }
                $manifest = if ($null -eq $current) { [pscustomobject](New-SiManifest) } else {
                    Test-SiJsonSchema -Json $current -Schema manifest
                    $current | ConvertFrom-Json -Depth 100
                }
                $value = & $Transform $manifest $attempt $preparedValue
                if ($null -eq $preparedValue) {
                    $preparedValue = $value
                }
                if ($null -ne $value -and
                    $value.PSObject.Properties.Name -contains 'Mutated' -and -not $value.Mutated) {
                    return [pscustomobject]@{
                        Status = 'complete'; Path = $path; Generation = $generation
                        Attempts = $attempt; Value = $value
                    }
                }
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
            return [pscustomobject]@{
                DueId = $dueId; Written = $false; Mutated = $false; Note = 'already-known'
            }
        }
        if (@($manifest.pending).Count + @($manifest.inFlight).Count -ge $script:SiStateContract.Limits.PendingDues) {
            throw 'capacity-blocked: SI pending/in-flight due limit reached.'
        }
        $manifest.pending = @($manifest.pending) + [pscustomobject][ordered]@{
            dueId = $dueId; repoId = $RepoId; planId = $PlanId; sourceCommit = $SourceCommit
            createdAtUtc = [datetime]::UtcNow.ToString('o'); deferUntilUtc = $null
            status = 'pending'; runId = $null
        }
        return [pscustomobject]@{
            DueId = $dueId; Written = $true; Mutated = $true; Note = ''
        }
    }
    return [pscustomobject]@{
        Status   = $result.Status
        DueId    = $dueId
        Written  = ($result.Status -eq 'complete' -and $result.Value.Written)
        Note     = if ($result.Status -eq 'complete') { $result.Value.Note } else { $result.Status }
        Attempts = $result.Attempts
    }
}

function Get-SiStoreInspection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $manifestPath = Get-SiManifestPath -RepoRoot $root
    $runsRoot = Resolve-SiStatePath -RepoRoot $root `
        -Segments @($script:SiStateContract.Topology.ActiveRunsSegments)
    $backupsRoot = Resolve-SiStatePath -RepoRoot $root `
        -Segments @($script:SiStateContract.Topology.BackupSegments)
    $journalFiles = @(Get-ChildItem -LiteralPath $backupsRoot `
            -Filter 'apply-journal.json' -Recurse -File -ErrorAction SilentlyContinue)
    $journalPathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $incompleteApplies = @($journalFiles | ForEach-Object {
            $journal = $null
            try {
                $journal = [System.IO.File]::ReadAllText($_.FullName) |
                    ConvertFrom-Json -Depth 20
            }
            catch { }
            $journalProperties = if ($null -eq $journal) {
                @()
            }
            else {
                @($journal.PSObject.Properties | ForEach-Object Name)
            }
            $directoryObservationId = [string]$_.Directory.Name
            $expectedJournalPath = [System.IO.Path]::GetFullPath(
                (Join-Path (Join-Path $backupsRoot $directoryObservationId) 'apply-journal.json')
            )
            $journalPathMatches = [string]::Equals(
                [System.IO.Path]::GetFullPath($_.FullName),
                $expectedJournalPath,
                $journalPathComparison
            )
            $journalIdMatches = $journalProperties -contains 'observationId' -and
                [string]$journal.observationId -match '^[0-9a-f]{64}$' -and
                [string]$journal.observationId -ceq $directoryObservationId -and
                $journalPathMatches
            [pscustomobject][ordered]@{
                observationId = $directoryObservationId
                stage = if ($journalIdMatches -and
                    $journalProperties -contains 'stage' -and [string]$journal.stage -in @(
                        'backup-pending', 'backup-complete', 'mutation-started'
                    )) {
                    [string]$journal.stage
                }
                else {
                    'invalid'
                }
                journalPath = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
            }
        } | Sort-Object observationId, journalPath)
    $runFiles = @(Get-ChildItem -LiteralPath $runsRoot -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)
    $observed = [System.Collections.Generic.List[object]]::new()
    $currentRuns = 0
    $forwardRuns = 0
    $corruptRuns = 0
    $legacyRuns = 0
    $completedRuns = 0
    $inFlightRuns = 0
    $currentRunRecords = [System.Collections.Generic.List[object]]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    foreach ($file in $runFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        try {
            $json = $utf8.GetString($bytes)
            $obj = $json | ConvertFrom-Json -Depth 100
            if ([int]$obj.schemaVersion -gt $script:SiStateContract.RunVersion) { $forwardRuns++ }
            elseif ([int]$obj.schemaVersion -lt $script:SiStateContract.RunVersion) { $legacyRuns++ }
            else {
                Test-SiJsonSchema -Json $json -Schema run
                Assert-SiRunIntegrity -Run $obj
                $canonicalDueId = Get-SiDueId -RepoId ([string]$obj.provenance.repoId) `
                    -PlanId ([string]$obj.provenance.planId) `
                    -SourceCommit ([string]$obj.provenance.sourceCommit)
                if ([string]$obj.dueId -ne $canonicalDueId) {
                    throw "Run '$($obj.runId)' due identity does not match its provenance."
                }
                $canonicalRunPath = [System.IO.Path]::GetRelativePath(
                    $root,
                    (Get-SiRunPath -RepoRoot $root -RunId ([string]$obj.runId) `
                        -Timestamp ([datetime]$obj.createdAtUtc))
                ).Replace('\', '/')
                if ([string]$relative -cne $canonicalRunPath) {
                    throw "Run '$($obj.runId)' is stored at a noncanonical active path."
                }
                $currentRuns++
                if (Test-SiRunStatus -Status ([string]$obj.status) -Set Terminal) {
                    $completedRuns++
                }
                else {
                    $inFlightRuns++
                }
                $currentRunRecords.Add([pscustomobject]@{
                        Run = $obj
                        Path = $relative
                    })
            }
        }
        catch {
            $corruptRuns++
        }
        $observed.Add([pscustomobject]@{
                path = $relative
                sha256 = Get-SiArtifactDigest -Bytes $bytes
            })
    }

    $manifestKind = 'absent'
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
        try {
            $raw = $utf8.GetString($manifestBytes)
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
                path = Get-SiStateRelativePath -Kind Manifest
                sha256 = Get-SiArtifactDigest -Bytes $manifestBytes
            })
    }

    $graphDivergent = $false
    if ($manifestKind -eq 'current') {
        $runById = @{}
        $runDueIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($record in $currentRunRecords) {
            $runId = [string]$record.Run.runId
            if ($runById.ContainsKey($runId) -or
                -not $runDueIds.Add([string]$record.Run.dueId)) {
                $graphDivergent = $true
            }
            else {
                $runById[$runId] = $record
            }
        }
        $referenced = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $activeDueIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($entry in @($manifest.pending)) {
            $canonicalDueId = Get-SiDueId -RepoId ([string]$entry.repoId) `
                -PlanId ([string]$entry.planId) `
                -SourceCommit ([string]$entry.sourceCommit)
            if ([string]$entry.dueId -ne $canonicalDueId -or
                -not $activeDueIds.Add([string]$entry.dueId)) {
                $graphDivergent = $true
            }
        }
        foreach ($entry in @($manifest.inFlight)) {
            if (-not $activeDueIds.Add([string]$entry.dueId)) {
                $graphDivergent = $true
            }
            $runId = [string]$entry.runId
            if (-not $referenced.Add($runId) -or -not $runById.ContainsKey($runId)) {
                $graphDivergent = $true
                continue
            }
            $run = $runById[$runId].Run
            if ((Test-SiRunStatus -Status ([string]$run.status) -Set Terminal) -or
                [string]$run.dueId -ne [string]$entry.dueId -or
                [string]$run.provenance.repoId -ne [string]$entry.repoId -or
                [string]$run.provenance.planId -ne [string]$entry.planId -or
                [string]$run.provenance.sourceCommit -ne [string]$entry.sourceCommit) {
                $graphDivergent = $true
            }
        }
        foreach ($entry in @($manifest.recentRuns)) {
            $runId = [string]$entry.runId
            if (-not $referenced.Add($runId) -or -not $runById.ContainsKey($runId)) {
                $graphDivergent = $true
                continue
            }
            $record = $runById[$runId]
            $run = $record.Run
            if (-not (Test-SiRunStatus -Status ([string]$run.status) -Set Terminal) -or
                [string]$run.dueId -ne [string]$entry.dueId -or
                [string]$run.status -ne [string]$entry.status -or
                [string]$record.Path -ne [string]$entry.path) {
                $graphDivergent = $true
            }
        }
        foreach ($runId in $runById.Keys) {
            if (-not $referenced.Contains($runId)) {
                $graphDivergent = $true
            }
        }
    }

    $underlyingStatus = if ($completedRuns -gt $script:SiStateContract.Limits.ActiveCompletedRuns) { 'capacity-blocked' }
    elseif ($inFlightRuns -gt $script:SiStateContract.Limits.ActiveInFlightRuns) { 'capacity-blocked' }
    elseif ($manifestKind -eq 'forward' -or $forwardRuns -gt 0) {
        if ($manifestKind -eq 'current' -or $currentRuns -gt 0 -or $corruptRuns -gt 0) { 'forward-blocked' } else { 'forward-readonly' }
    }
    elseif ($manifestKind -eq 'corrupt' -or $corruptRuns -gt 0) { 'repairable-corrupt' }
    elseif ($manifestKind -eq 'legacy' -or $legacyRuns -gt 0) { 'migration-required' }
    elseif ($graphDivergent) { 'repairable-orphans' }
    elseif ($manifestKind -eq 'absent' -and $currentRuns -gt 0) { 'repairable-orphans' }
    elseif ($manifestKind -eq 'absent') { 'absent' }
    else { 'valid' }
    $status = if ($journalFiles.Count -gt 0) { 'apply-incomplete' } else { $underlyingStatus }

    return [pscustomobject]@{
        Status       = $status
        UnderlyingStatus = $underlyingStatus
        ExitCode     = [int]$script:SiStateContract.Status.($status -replace '-(\w)', { $_.Groups[1].Value.ToUpperInvariant() })
        ManifestPath = $manifestPath
        RunFiles     = $runFiles
        Observed     = @($observed | Sort-Object path)
        IncompleteApplies = $incompleteApplies
    }
}

function Get-SiObservationPayload {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$PinnedBaseOid
    )
    $inspection = Get-SiStoreInspection -RepoRoot $RepoRoot
    return [ordered]@{
        protocol      = 'si-repair-observation-v1'
        pinnedBaseOid = $PinnedBaseOid
        status        = $inspection.Status
        observed      = @($inspection.Observed)
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

function New-SiRepairReceipt {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ObservationId,
        [Parameter(Mandatory)][ValidateSet('apply', 'rollback')][string]$Mode,
        [Parameter(Mandatory)][string]$BeforeDigest,
        [Parameter(Mandatory)][string]$AfterDigest
    )
    $payload = [ordered]@{
        protocol      = 'si-repair-receipt-v1'
        observationId = $ObservationId
        mode          = $Mode
        beforeDigest  = $BeforeDigest
        afterDigest   = $AfterDigest
        createdAtUtc  = [datetime]::UtcNow.ToString('o')
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
    $receiptId = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
    [void]($payload.receiptId = $receiptId)
    $json = ConvertTo-SiJson -Value $payload
    Test-SiJsonSchema -Json $json -Schema repair-receipt
    $path = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-receipts', "$receiptId.json")
    [void](Set-AtomicStoreContent -Path $path -Content $json)
    return [pscustomobject]@{ ReceiptId = $receiptId; Path = $path }
}

function Read-SiRepairObservation {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ObservationId
    )

    if ($ObservationId -notmatch '^[0-9a-f]{64}$') {
        throw "Repair observation '$ObservationId' has an invalid id."
    }
    $path = Resolve-SiStatePath -RepoRoot $RepoRoot `
        -Segments (@($script:SiStateContract.Topology.ObservationSegments) +
            "$ObservationId.json")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Repair observation '$ObservationId' not found."
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -gt $script:SiStateContract.Limits.RunBytes) {
        throw "Repair observation '$ObservationId' exceeds its byte limit."
    }
    try {
        $json = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch {
        throw "Repair observation '$ObservationId' is not valid UTF-8."
    }
    Test-SiJsonSchema -Json $json -Schema repair-observation
    $envelope = $json | ConvertFrom-Json -Depth 100
    $payloadJson = $envelope.payload | ConvertTo-Json -Depth 100 -Compress
    $calculated = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes(
                'si-repair-observation-v1' + $payloadJson
            )
        )
    ).ToLowerInvariant()
    if ([string]$envelope.observationId -ne $ObservationId -or
        $calculated -ne $ObservationId) {
        throw "Repair observation '$ObservationId' failed its content-address check."
    }
    return [pscustomobject]@{
        Path = $path
        Envelope = $envelope
        PayloadJson = $payloadJson
    }
}

function Get-SiVerifiedRepairBackups {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)]$ObservationEnvelope
    )

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $stateRoot = Split-Path -Parent (Get-SiManifestPath -RepoRoot $root)
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $statePrefix = $stateRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    $filesRoot = Join-Path $BackupRoot 'files'
    $verified = [ordered]@{}
    foreach ($observed in @($ObservationEnvelope.payload.observed)) {
        $relative = [string]$observed.path
        if ($verified.Contains($relative) -or [System.IO.Path]::IsPathRooted($relative)) {
            throw "Repair observation contains duplicate or rooted backup path '$relative'."
        }
        $target = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $target.StartsWith($statePrefix, $comparison) -or
            -not (Test-SiPhysicalDescendant -Root $stateRoot -Path $target)) {
            throw "Repair observation backup target '$relative' escapes the SI state root."
        }
        $backup = [System.IO.Path]::GetFullPath((Join-Path $filesRoot $relative))
        if (-not (Test-SiPhysicalDescendant -Root $BackupRoot -Path $backup) -or
            -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Repair backup '$relative' is missing or escapes its observation root."
        }
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-SiPhysicalPath -Path $backup))
        if ((Get-SiArtifactDigest -Bytes $bytes) -ne [string]$observed.sha256) {
            throw "Repair backup '$relative' failed its observation digest."
        }
        $verified[$relative] = [pscustomobject]@{
            Target = $target
            Bytes = $bytes
        }
    }
    $actual = @(Get-ChildItem -LiteralPath $filesRoot -File -Recurse `
            -ErrorAction SilentlyContinue | ForEach-Object {
                [System.IO.Path]::GetRelativePath($filesRoot, $_.FullName).Replace('\', '/')
            })
    if ($actual.Count -ne $verified.Count -or
        @($actual | Where-Object { -not $verified.Contains($_) }).Count -gt 0) {
        throw 'Repair backup file set does not exactly match its observation.'
    }
    return $verified
}

function Assert-SiRollbackTargetsUnchanged {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ObservationId,
        [Parameter(Mandatory)]$ObservationEnvelope
    )

    $root = Resolve-SiRepoRoot -RepoRoot $RepoRoot
    $stateRoot = Split-Path -Parent (Get-SiManifestPath -RepoRoot $root)
    $manifestRelative = Get-SiStateRelativePath -Kind Manifest
    foreach ($observed in @($ObservationEnvelope.payload.observed)) {
        $relative = [string]$observed.path
        if ($relative -ceq $manifestRelative) { continue }
        $target = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
        $backupPath = [System.IO.Path]::GetFullPath((
                Join-Path (Join-Path (
                        Resolve-SiStatePath -RepoRoot $root `
                            -Segments (@($script:SiStateContract.Topology.BackupSegments) +
                                @($ObservationId))
                    ) 'files') $relative
            ))
        $beforeBytes = [System.IO.File]::ReadAllBytes(
            (Resolve-SiPhysicalPath -Path $backupPath)
        )
        $expectedTargetDigest = $null
        try {
            $runJson = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                $beforeBytes
            )
            $run = $runJson | ConvertFrom-Json -Depth 100
            if ([int]$run.schemaVersion -lt $script:SiStateContract.RunVersion) {
                $run.schemaVersion = $script:SiStateContract.RunVersion
                $runJson = ConvertTo-SiJson -Value $run
            }
            Test-SiJsonSchema -Json $runJson -Schema run
            Assert-SiRunIntegrity -Run $run
            $expectedTargetDigest = Get-SiArtifactDigest -Bytes (
                [System.Text.UTF8Encoding]::new($false).GetBytes($runJson)
            )
        }
        catch {
            $expectedTargetDigest = $null
        }
        if ($null -ne $expectedTargetDigest) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $relativeTail = [System.IO.Path]::GetRelativePath($stateRoot, $target) `
                    -split '[\\/]'
                $quarantinePath = Resolve-SiStatePath -RepoRoot $root `
                    -Segments (@($script:SiStateContract.Topology.QuarantineSegments) +
                        @($ObservationId) + $relativeTail)
                if (-not (Test-Path -LiteralPath $quarantinePath -PathType Leaf)) {
                    throw "Repair target '$relative' is missing after apply."
                }
                $quarantineBytes = [System.IO.File]::ReadAllBytes(
                    (Resolve-SiPhysicalPath -Path $quarantinePath)
                )
                if ((Get-SiArtifactDigest -Bytes $quarantineBytes) -ne
                    [string]$observed.sha256) {
                    throw "Repair quarantine for '$relative' failed its observation digest."
                }
                continue
            }
            $currentBytes = [System.IO.File]::ReadAllBytes(
                (Resolve-SiPhysicalPath -Path $target)
            )
            $currentDigest = Get-SiArtifactDigest -Bytes $currentBytes
            if ($currentDigest -notin @(
                    $expectedTargetDigest,
                    [string]$observed.sha256
                )) {
                throw "Repair target '$relative' changed after apply; refusing rollback."
            }
            continue
        }

        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $currentBytes = [System.IO.File]::ReadAllBytes(
                (Resolve-SiPhysicalPath -Path $target)
            )
            if ((Get-SiArtifactDigest -Bytes $currentBytes) -eq
                [string]$observed.sha256) {
                continue
            }
            throw "Quarantined repair target '$relative' was recreated after apply."
        }
        $relativeTail = [System.IO.Path]::GetRelativePath($stateRoot, $target) `
            -split '[\\/]'
        $quarantinePath = Resolve-SiStatePath -RepoRoot $root `
            -Segments (@($script:SiStateContract.Topology.QuarantineSegments) +
                @($ObservationId) + $relativeTail)
        if (-not (Test-Path -LiteralPath $quarantinePath -PathType Leaf)) {
            throw "Repair target '$relative' is missing without its observation quarantine."
        }
        $quarantineBytes = [System.IO.File]::ReadAllBytes(
            (Resolve-SiPhysicalPath -Path $quarantinePath)
        )
        if ((Get-SiArtifactDigest -Bytes $quarantineBytes) -ne
            [string]$observed.sha256) {
            throw "Repair quarantine for '$relative' failed its observation digest."
        }
    }
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
            return Invoke-WithAtomicStoreLock -Scope (Get-SiStateLockScope -RepoRoot $root) `
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
        $observationRecord = Read-SiRepairObservation -RepoRoot $RepoRoot `
            -ObservationId $Observation
        $envelope = $observationRecord.Envelope
        $payloadJson = $observationRecord.PayloadJson
        $repairableStatuses = @(
            'migration-required', 'repairable-corrupt', 'repairable-orphans'
        )
        if ([string]$envelope.payload.status -notin $repairableStatuses) {
            throw "Repair Apply refuses observed status '$($envelope.payload.status)'."
        }
        $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $Observation)
        $backupsRoot = Resolve-SiStatePath -RepoRoot $RepoRoot `
            -Segments @($script:SiStateContract.Topology.BackupSegments)
        $otherJournal = @(Get-ChildItem -LiteralPath $backupsRoot `
                -Filter 'apply-journal.json' -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1)
        if ($otherJournal.Count -gt 0) {
            throw 'apply-incomplete: another SI repair must be rolled back before Apply.'
        }
        [void](New-Item -ItemType Directory -Path $backupRoot -Force)
        $backupFilesRoot = Join-Path $backupRoot 'files'
        $repoRootPath = Resolve-SiRepoRoot -RepoRoot $RepoRoot
        $manifestPath = Get-SiManifestPath -RepoRoot $RepoRoot
        $journalPath = Join-Path $backupRoot 'apply-journal.json'
        if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
            throw "Repair observation '$Observation' already has an incomplete apply journal; rollback before retry."
        }
        $currentPayload = Get-SiObservationPayload -RepoRoot $RepoRoot `
            -PinnedBaseOid ([string]$envelope.payload.pinnedBaseOid)
        if (($currentPayload | ConvertTo-Json -Depth 100 -Compress) -ne $payloadJson) {
            throw "Repair observation '$Observation' is stale; the observed store changed."
        }
        $stateRootPath = Split-Path -Parent (Get-SiManifestPath -RepoRoot $RepoRoot)
        $statePrefix = $stateRootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
        $physicalPathComparison = if ($IsWindows) {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else {
            [System.StringComparison]::Ordinal
        }
        $verifiedManifestBytes = $null
        $verifiedArtifactBytes = @{}
        foreach ($observed in @($envelope.payload.observed)) {
            $observedPath = [string]$observed.path
            if ([System.IO.Path]::IsPathRooted($observedPath)) {
                throw "Repair observation '$Observation' contains rooted path '$observedPath'."
            }
            $source = [System.IO.Path]::GetFullPath((Join-Path $repoRootPath $observedPath))
            if (-not $source.StartsWith($statePrefix, $physicalPathComparison)) {
                throw "Repair observation '$Observation' path '$observedPath' escapes the SI state root."
            }
            if (-not (Test-SiPhysicalDescendant -Root $stateRootPath -Path $source)) {
                throw "Repair observation '$Observation' path '$observedPath' escapes the SI state root via link."
            }
            $physicalSource = Resolve-SiPhysicalPath -Path $source
            $sourceBytes = [System.IO.File]::ReadAllBytes($physicalSource)
            $sourceDigest = Get-SiArtifactDigest -Bytes $sourceBytes
            if ($sourceDigest -ne [string]$observed.sha256 -or
                -not (Test-SiPhysicalDescendant -Root $stateRootPath -Path $source) -or
                -not [string]::Equals(
                    (Resolve-SiPhysicalPath -Path $source),
                    $physicalSource,
                    $physicalPathComparison
                )) {
                throw "Repair observation '$Observation' source '$observedPath' changed before backup."
            }
            if ($observedPath -ceq (Get-SiStateRelativePath -Kind Manifest)) {
                $verifiedManifestBytes = $sourceBytes
            }
            $verifiedArtifactBytes[$observedPath] = $sourceBytes
        }
        $beforeDigest = if ($null -eq $verifiedManifestBytes) {
            Get-SiArtifactDigest -Path $manifestPath
        }
        else {
            Get-SiArtifactDigest -Bytes $verifiedManifestBytes
        }
        $journal = [ordered]@{
            schemaVersion = 1
            observationId = $Observation
            beforeDigest = $beforeDigest
            stage = 'backup-pending'
        }
        [void](Set-AtomicStoreContent -Path $journalPath `
                -Content ((ConvertTo-SiJson -Value $journal)))
        $physicalBackupRoot = Resolve-SiPhysicalPath -Path $backupRoot
        foreach ($observedPath in @($verifiedArtifactBytes.Keys | Sort-Object)) {
            $backup = Join-Path $backupFilesRoot $observedPath
            if (-not (Test-SiPhysicalDescendant -Root $backupRoot -Path $backup)) {
                throw "Repair backup '$observedPath' escapes its observation root via link."
            }
            $physicalBackup = Resolve-SiPhysicalPath -Path $backup
            if (-not (Test-SiPhysicalDescendant -Root $physicalBackupRoot `
                    -Path $physicalBackup)) {
                throw "Repair backup '$observedPath' escapes its physical observation root."
            }
            $backupParent = Split-Path -Parent $physicalBackup
            if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $backupParent -Force)
            }
            [void](Set-AtomicStoreBytes -Path $physicalBackup `
                    -Bytes ([byte[]]$verifiedArtifactBytes[$observedPath]))
        }
        if ($null -eq $verifiedManifestBytes) {
            [void](Set-AtomicStoreContent -Path (Join-Path $backupRoot 'manifest.absent') -Content "absent`n")
        }
        $journal.stage = 'backup-complete'
        [void](Set-AtomicStoreContent -Path $journalPath `
                -Content ((ConvertTo-SiJson -Value $journal)))
        $manifest = New-SiManifest
        $preserveManifestReferences = $false
        if ($null -ne $verifiedManifestBytes) {
            $manifestText = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                $verifiedManifestBytes
            )
            try {
                Test-SiJsonSchema -Json $manifestText -Schema manifest
                $manifest = $manifestText | ConvertFrom-Json -Depth 100
                $manifest.generation = [int]$manifest.generation + 1
                $preserveManifestReferences = $true
            }
            catch {
                $storedManifest = try {
                    $manifestText | ConvertFrom-Json -Depth 100
                }
                catch {
                    $null
                }
                $storedProperties = if ($null -eq $storedManifest) {
                    @()
                }
                else {
                    @($storedManifest.PSObject.Properties | ForEach-Object { $_.Name })
                }
                if ($storedProperties -notcontains 'schemaVersion' -or
                    [int]$storedManifest.schemaVersion -ge $script:SiStateContract.ManifestVersion) {
                    $manifest.generation = 1
                }
                else {
                    foreach ($field in @('pending', 'inFlight', 'recentRuns')) {
                        if ($storedManifest.PSObject.Properties.Name -contains $field) {
                            $manifest[$field] = @($storedManifest.$field)
                        }
                    }
                    $manifest.generation = [int]$storedManifest.generation + 1
                    $preserveManifestReferences = $true
                }
            }
        }
        else {
            $manifest.generation = 1
        }

        $quarantineEntries = [System.Collections.Generic.List[object]]::new()
        $quarantineCandidates = [System.Collections.Generic.List[object]]::new()
        $validRunRecords = [System.Collections.Generic.List[object]]::new()
        $runByDueId = @{}
        $conflictedDueIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $activeRunsPrefix = (Get-SiStateRelativePath -Kind ActiveRuns).TrimEnd('/') + '/'
        foreach ($observedPath in @($verifiedArtifactBytes.Keys | Sort-Object)) {
            if (-not $observedPath.StartsWith(
                    $activeRunsPrefix,
                    [System.StringComparison]::Ordinal
                )) {
                continue
            }
            $runPath = [System.IO.Path]::GetFullPath((Join-Path $repoRootPath $observedPath))
            $runBytes = [byte[]]$verifiedArtifactBytes[$observedPath]
            $run = $null
            $runValidated = $false
            try {
                $runJson = [System.Text.UTF8Encoding]::new($false, $true).GetString($runBytes)
                $run = $runJson | ConvertFrom-Json -Depth 100
                $needsMigration = [int]$run.schemaVersion -lt $script:SiStateContract.RunVersion
                if ([int]$run.schemaVersion -lt $script:SiStateContract.RunVersion) {
                    $run.schemaVersion = $script:SiStateContract.RunVersion
                    $runJson = ConvertTo-SiJson -Value $run
                    Test-SiJsonSchema -Json $runJson -Schema run
                    Assert-SiRunIntegrity -Run $run
                }
                else {
                    Test-SiJsonSchema -Json $runJson -Schema run
                    Assert-SiRunIntegrity -Run $run
                }
                $runValidated = $true
                $canonicalDueId = Get-SiDueId -RepoId ([string]$run.provenance.repoId) `
                    -PlanId ([string]$run.provenance.planId) `
                    -SourceCommit ([string]$run.provenance.sourceCommit)
                if ([string]$run.dueId -ne $canonicalDueId) {
                    throw "Run '$($run.runId)' due identity does not match its provenance."
                }
                $canonicalPath = [System.IO.Path]::GetRelativePath(
                    $repoRootPath,
                    (Get-SiRunPath -RepoRoot $RepoRoot -RunId ([string]$run.runId) `
                        -Timestamp ([datetime]$run.createdAtUtc))
                ).Replace('\', '/')
                $record = [pscustomobject]@{
                    Run = $run; Path = $observedPath; ObservedPath = $observedPath
                    FullName = $runPath
                    Bytes = $runBytes
                }
                if ([string]$observedPath -cne $canonicalPath) {
                    $quarantineCandidates.Add($record)
                    continue
                }
                $dueId = [string]$run.dueId
                if ($conflictedDueIds.Contains($dueId)) {
                    $quarantineCandidates.Add($record)
                    continue
                }
                if ($runByDueId.ContainsKey($dueId)) {
                    $prior = $runByDueId[$dueId]
                    [void]$validRunRecords.Remove($prior)
                    $quarantineCandidates.Add($prior)
                    $quarantineCandidates.Add($record)
                    [void]$runByDueId.Remove($dueId)
                    [void]$conflictedDueIds.Add($dueId)
                    continue
                }
                $runByDueId[$dueId] = $record
                if ($needsMigration) {
                    if ([string]$journal.stage -ne 'mutation-started') {
                        $journal.stage = 'mutation-started'
                        $journal['expectedAfterDigest'] = [string]$journal.beforeDigest
                        [void](Set-AtomicStoreContent -Path $journalPath `
                                -Content ((ConvertTo-SiJson -Value $journal)))
                    }
                    [void](Set-AtomicStoreContent -Path $runPath -Content $runJson)
                }
                $validRunRecords.Add($record)
            }
            catch {
                $quarantineCandidates.Add([pscustomobject]@{
                        FullName = $runPath
                        ObservedPath = $observedPath
                        Bytes = $runBytes
                        Run = if ($runValidated) { $run } else { $null }
                    })
            }
        }
        $previousInFlight = @($manifest.inFlight)
        $canonicalPending = [System.Collections.Generic.List[object]]::new()
        $pendingDueIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($entry in @($manifest.pending)) {
            $expectedDueId = Get-SiDueId -RepoId ([string]$entry.repoId) `
                -PlanId ([string]$entry.planId) -SourceCommit ([string]$entry.sourceCommit)
            if (-not $pendingDueIds.Add($expectedDueId)) {
                continue
            }
            $canonicalPending.Add([pscustomobject][ordered]@{
                    dueId = $expectedDueId; repoId = [string]$entry.repoId
                    planId = [string]$entry.planId
                    sourceCommit = [string]$entry.sourceCommit
                    createdAtUtc = [string]$entry.createdAtUtc
                    deferUntilUtc = $entry.deferUntilUtc
                    status = 'pending'; runId = $null
                })
        }
        $manifest.pending = @($canonicalPending)
        $validRunIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $manifest.inFlight = @()
        $manifest.recentRuns = @()
        foreach ($record in $validRunRecords) {
            $run = $record.Run
            $runId = [string]$run.runId
            [void]$validRunIds.Add($runId)
            $manifest.pending = @($manifest.pending | Where-Object {
                    [string]$_.dueId -ne [string]$run.dueId
                })
            if (Test-SiRunStatus -Status ([string]$run.status) -Set Terminal) {
                $manifest.recentRuns = @($manifest.recentRuns) + [pscustomobject][ordered]@{
                    runId = $runId; dueId = [string]$run.dueId
                    status = [string]$run.status; path = [string]$record.Path
                    completedAtUtc = [string]$run.completedAtUtc
                }
            }
            else {
                $manifest.inFlight = @($manifest.inFlight) + [pscustomobject][ordered]@{
                    dueId = [string]$run.dueId
                    repoId = [string]$run.provenance.repoId
                    planId = [string]$run.provenance.planId
                    sourceCommit = [string]$run.provenance.sourceCommit
                    createdAtUtc = [string]$run.createdAtUtc
                    deferUntilUtc = $null
                    status = 'in-flight'; runId = $runId
                }
            }
        }
        foreach ($entry in $previousInFlight) {
            $expectedDueId = Get-SiDueId -RepoId ([string]$entry.repoId) `
                -PlanId ([string]$entry.planId) -SourceCommit ([string]$entry.sourceCommit)
            if ([string]$entry.dueId -ne $expectedDueId) { continue }
            if ($validRunIds.Contains([string]$entry.runId) -or
                @($manifest.pending | Where-Object {
                        [string]$_.dueId -eq [string]$entry.dueId
                    }).Count -gt 0) {
                continue
            }
            $manifest.pending = @($manifest.pending) + [pscustomobject][ordered]@{
                dueId = [string]$entry.dueId; repoId = [string]$entry.repoId
                planId = [string]$entry.planId
                sourceCommit = [string]$entry.sourceCommit
                createdAtUtc = [string]$entry.createdAtUtc
                deferUntilUtc = $entry.deferUntilUtc
                status = 'pending'; runId = $null
            }
        }
        foreach ($candidate in $quarantineCandidates) {
            if ($null -eq $candidate.Run) { continue }
            $run = $candidate.Run
            $candidateDueId = Get-SiDueId -RepoId ([string]$run.provenance.repoId) `
                -PlanId ([string]$run.provenance.planId) `
                -SourceCommit ([string]$run.provenance.sourceCommit)
            if (@($manifest.pending | Where-Object {
                        [string]$_.dueId -eq $candidateDueId
                    }).Count -eq 0) {
                $manifest.pending = @($manifest.pending) + [pscustomobject][ordered]@{
                    dueId = $candidateDueId
                    repoId = [string]$run.provenance.repoId
                    planId = [string]$run.provenance.planId
                    sourceCommit = [string]$run.provenance.sourceCommit
                    createdAtUtc = [string]$run.createdAtUtc
                    deferUntilUtc = $null; status = 'pending'; runId = $null
                }
            }
        }
        $manifest.recentRuns = @($manifest.recentRuns | Sort-Object completedAtUtc -Descending)
        if (@($manifest.inFlight).Count -gt $script:SiStateContract.Limits.ActiveInFlightRuns -or
            @($manifest.recentRuns).Count -gt $script:SiStateContract.Limits.RecentRunReferences) {
            throw 'capacity-blocked: repair result exceeds active history limits.'
        }
        if ($quarantineCandidates.Count -gt 0) {
            if ([string]$journal.stage -ne 'mutation-started') {
                $journal.stage = 'mutation-started'
                $journal['expectedAfterDigest'] = [string]$journal.beforeDigest
                [void](Set-AtomicStoreContent -Path $journalPath `
                        -Content ((ConvertTo-SiJson -Value $journal)))
            }
        }
        foreach ($runFile in $quarantineCandidates) {
            $relativeTail = [System.IO.Path]::GetRelativePath(
                (Split-Path -Parent (Get-SiManifestPath -RepoRoot $RepoRoot)), $runFile.FullName
            ) -split '[\\/]'
            $quarantinePath = Resolve-SiStatePath -RepoRoot $RepoRoot `
                -Segments (@($script:SiStateContract.Topology.QuarantineSegments) +
                    @($Observation) + $relativeTail)
            $parent = Split-Path -Parent $quarantinePath
            $quarantineRoot = Resolve-SiStatePath -RepoRoot $RepoRoot `
                -Segments (@($script:SiStateContract.Topology.QuarantineSegments) +
                    @($Observation))
            $physicalQuarantine = Resolve-SiPhysicalPath -Path $quarantinePath
            if (-not (Test-SiPhysicalDescendant -Root $quarantineRoot `
                    -Path $physicalQuarantine)) {
                throw "Repair quarantine '$($runFile.ObservedPath)' escapes its observation root."
            }
            $parent = Split-Path -Parent $physicalQuarantine
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }
            [void](Set-AtomicStoreBytes -Path $physicalQuarantine `
                    -Bytes ([byte[]]$runFile.Bytes))
            Remove-Item -LiteralPath $runFile.FullName -Force
            $quarantineEntries.Add([pscustomobject][ordered]@{
                    observationId  = $Observation
                    path           = [string]$runFile.ObservedPath
                    quarantinePath = [System.IO.Path]::GetRelativePath($repoRootPath, $physicalQuarantine).Replace('\', '/')
                    sha256         = Get-SiArtifactDigest -Bytes ([byte[]]$runFile.Bytes)
                })
        }
        if ($quarantineEntries.Count -gt 0) {
            $indexPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('quarantine', 'index.json')
            $existingIndex = if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
                @((Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json -Depth 100).entries)
            }
            else { @() }
            $indexJson = ConvertTo-SiJson -Value ([ordered]@{
                    schemaVersion = 1
                    entries       = @($existingIndex) + @($quarantineEntries)
                })
            [void](Set-AtomicStoreContent -Path $indexPath -Content $indexJson)
        }
        $manifestJson = ConvertTo-SiJson -Value $manifest
        Test-SiJsonSchema -Json $manifestJson -Schema manifest
        $journal['expectedAfterDigest'] = Get-SiArtifactDigest -Bytes (
            [System.Text.UTF8Encoding]::new($false).GetBytes($manifestJson)
        )
        if ([string]$journal.stage -ne 'mutation-started') {
            $journal.stage = 'mutation-started'
        }
        [void](Set-AtomicStoreContent -Path $journalPath `
                -Content ((ConvertTo-SiJson -Value $journal)))
        [void](Set-AtomicStoreContent -Path $manifestPath -Content $manifestJson)
        $after = Get-SiArtifactDigest -Path $manifestPath
        $finalStatus = (Get-SiStoreInspection -RepoRoot $RepoRoot).UnderlyingStatus
        if ($finalStatus -ne 'valid') {
            throw "Repair Apply produced unresolved state '$finalStatus'."
        }
        $issuedReceipt = New-SiRepairReceipt -RepoRoot $RepoRoot -ObservationId $Observation -Mode apply `
            -BeforeDigest ([string](Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json).beforeDigest) `
            -AfterDigest $after
        Remove-Item -LiteralPath $journalPath -Force
        return [pscustomobject]@{
            Status = $finalStatus
            ReceiptId = $issuedReceipt.ReceiptId
            ObservationId = $Observation; Mutated = $true
        }
    }

    $lookup = if ($Receipt) { $Receipt } else { $Observation }
    if ($lookup -notmatch '^[0-9a-f]{64}$') { throw 'Rollback requires -Receipt or -Observation.' }
    $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $lookup)
    $applyReceipt = $null
    if ($Receipt) {
        $receiptPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('repair-receipts', "$Receipt.json")
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Repair receipt '$Receipt' not found." }
        $receiptJson = Get-Content -LiteralPath $receiptPath -Raw
        Test-SiJsonSchema -Json $receiptJson -Schema repair-receipt
        $storedReceipt = $receiptJson | ConvertFrom-Json -Depth 100 -DateKind String
        $receiptPayload = [ordered]@{
            protocol      = [string]$storedReceipt.protocol
            observationId = [string]$storedReceipt.observationId
            mode          = [string]$storedReceipt.mode
            beforeDigest  = [string]$storedReceipt.beforeDigest
            afterDigest   = [string]$storedReceipt.afterDigest
            createdAtUtc  = [string]$storedReceipt.createdAtUtc
        }
        $calculatedReceipt = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes(($receiptPayload | ConvertTo-Json -Compress))
            )
        ).ToLowerInvariant()
        if ($storedReceipt.receiptId -ne $Receipt -or $calculatedReceipt -ne $Receipt) {
            throw "Repair receipt '$Receipt' failed its content-address check."
        }
        if ($storedReceipt.mode -ne 'apply') {
            throw "Repair receipt '$Receipt' is not an apply receipt."
        }
        $applyReceipt = $storedReceipt
        $lookup = [string]$storedReceipt.observationId
        $backupRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('backups', $lookup)
    }
    elseif (-not $Receipt) {
        $journalPath = Join-Path $backupRoot 'apply-journal.json'
        if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
            throw "Observation '$lookup' has no incomplete apply journal; rollback requires its apply receipt."
        }
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -Depth 20
        if ([string]$journal.observationId -ne $lookup -or
            [string]$journal.stage -notin @(
                'backup-pending', 'backup-complete', 'mutation-started'
            )) {
            throw "Observation '$lookup' has an invalid apply journal."
        }
    }
    $absentMarker = Join-Path $backupRoot 'manifest.absent'
    $manifestPath = Get-SiManifestPath -RepoRoot $RepoRoot
    $beforeRollback = Get-SiArtifactDigest -Path $manifestPath
    if ($applyReceipt -and $beforeRollback -notin @(
            [string]$applyReceipt.afterDigest,
            [string]$applyReceipt.beforeDigest
        )) {
        throw "Repair receipt '$Receipt' is stale; state changed after apply."
    }
    if (-not $applyReceipt -and [string]$journal.stage -ne 'mutation-started') {
        if ($beforeRollback -ne [string]$journal.beforeDigest) {
            throw "Observation '$lookup' changed before repair mutation; refusing rollback."
        }
        Remove-Item -LiteralPath $journalPath -Force
        $rollbackReceipt = New-SiRepairReceipt -RepoRoot $RepoRoot `
            -ObservationId $lookup -Mode rollback -BeforeDigest $beforeRollback `
            -AfterDigest $beforeRollback
        return [pscustomobject]@{
            Status = (Get-SiStoreInspection -RepoRoot $RepoRoot).Status
            ObservationId = $lookup
            ReceiptId = $rollbackReceipt.ReceiptId
            Mutated = $false
        }
    }
    if (-not $applyReceipt -and [string]$journal.stage -eq 'mutation-started') {
        $journalProperties = @($journal.PSObject.Properties.Name)
        if ($journalProperties -notcontains 'expectedAfterDigest' -or
            [string]$journal.expectedAfterDigest -notmatch '^[0-9a-f]{64}$' -or
            $beforeRollback -notin @(
                [string]$journal.beforeDigest,
                [string]$journal.expectedAfterDigest
            )) {
            throw "Observation '$lookup' manifest changed after repair mutation; refusing rollback."
        }
    }
    $observationRecord = Read-SiRepairObservation -RepoRoot $RepoRoot `
        -ObservationId $lookup
    $verifiedBackups = Get-SiVerifiedRepairBackups -RepoRoot $RepoRoot `
        -BackupRoot $backupRoot -ObservationEnvelope $observationRecord.Envelope
    Assert-SiRollbackTargetsUnchanged -RepoRoot $RepoRoot `
        -ObservationId $lookup -ObservationEnvelope $observationRecord.Envelope
    $manifestRelative = Get-SiStateRelativePath -Kind Manifest
    $manifestWasObserved = $verifiedBackups.Contains($manifestRelative)
    if ($manifestWasObserved -eq (Test-Path -LiteralPath $absentMarker -PathType Leaf)) {
        throw "Rollback backup for observation '$lookup' has inconsistent manifest state."
    }
    foreach ($relative in @($verifiedBackups.Keys | Sort-Object)) {
        $backup = $verifiedBackups[$relative]
        [void](Set-AtomicStoreBytes -Path $backup.Target -Bytes ([byte[]]$backup.Bytes))
    }
    if (-not $manifestWasObserved) {
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
    }
    $quarantineRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('quarantine', $lookup)
    if (Test-Path -LiteralPath $quarantineRoot -PathType Container) {
        Remove-Item -LiteralPath $quarantineRoot -Recurse -Force
    }
    $quarantineIndexPath = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('quarantine', 'index.json')
    if (Test-Path -LiteralPath $quarantineIndexPath -PathType Leaf) {
        $index = Get-Content -LiteralPath $quarantineIndexPath -Raw | ConvertFrom-Json -Depth 100
        $index.entries = @($index.entries | Where-Object { [string]$_.observationId -ne $lookup })
        [void](Set-AtomicStoreContent -Path $quarantineIndexPath -Content (ConvertTo-SiJson -Value $index))
    }
    $journalPath = Join-Path $backupRoot 'apply-journal.json'
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        Remove-Item -LiteralPath $journalPath -Force
    }
    $afterRollback = Get-SiArtifactDigest -Path $manifestPath
    $rollbackReceipt = New-SiRepairReceipt -RepoRoot $RepoRoot -ObservationId $lookup -Mode rollback `
        -BeforeDigest $beforeRollback -AfterDigest $afterRollback
    return [pscustomobject]@{
        Status = (Get-SiStoreInspection -RepoRoot $RepoRoot).Status
        ObservationId = $lookup; ReceiptId = $rollbackReceipt.ReceiptId; Mutated = $true
    }
}

Export-ModuleMember -Function Get-SiStateContract, Test-SiRunStatus, Get-SiStateRelativePath,
Get-SiStateLockScope,
Resolve-SiStatePath, New-SiManifest,
Read-SiManifest, Get-SiManifestPath, Get-SiArtifactDigest, Get-SiDueId, Get-SiRepoId,
Get-SiRunPath, Assert-SiRunIntegrity, Write-SiRun,
Invoke-SiManifestUpdate, Add-SiDue, Get-SiStoreInspection, Get-SiObservationPayload,
Save-SiRepairObservation, New-SiRepairReceipt, Invoke-SiRepair
