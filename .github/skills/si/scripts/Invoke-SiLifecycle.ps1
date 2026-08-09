#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [ValidateSet('Surface')][string]$Operation = 'Surface',
    [datetimeoffset]$AsOfUtc = [datetimeoffset]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force

function Invoke-SiGit {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument
    )

    $output = @(& git -C $Root @Argument 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git '$($Argument[0])' failed with exit code $LASTEXITCODE."
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Invoke-SiGitBoundedLines {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument,
        [Parameter(Mandatory)][int]$MaximumLines
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in @('-C', $Root) + $Argument) {
        $startInfo.ArgumentList.Add($item)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $lines = [System.Collections.Generic.List[string]]::new()
    try {
        if (-not $process.Start()) {
            throw "Unable to start git '$($Argument[0])'."
        }
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
            $lines.Add($line)
            if ($lines.Count -gt $MaximumLines) {
                $process.Kill($true)
                $process.WaitForExit()
                [void]$stderrTask.GetAwaiter().GetResult()
                throw "git '$($Argument[0])' output exceeds its line limit."
            }
        }
        $process.WaitForExit()
        [void]$stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "git '$($Argument[0])' failed with exit code $($process.ExitCode)."
        }
        return $lines.ToArray()
    }
    finally {
        $process.Dispose()
    }
}

function Assert-SiTimestamp {
    param(
        [AllowNull()]$Value,
        [switch]$AllowNull
    )

    if ($null -eq $Value) {
        if ($AllowNull) { return }
        throw 'Pinned SI document contains an invalid timestamp.'
    }
    $text = [string]$Value
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        throw 'Pinned SI document contains an invalid timestamp.'
    }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse(
            $text,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        throw 'Pinned SI document contains an invalid timestamp.'
    }
}

function Assert-SiTimestampElement {
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Element,
        [switch]$AllowNull
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) {
        if ($AllowNull) { return }
        throw 'Pinned SI document contains an invalid timestamp.'
    }
    if ($Element.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
        throw 'Pinned SI document contains an invalid timestamp.'
    }
    Assert-SiTimestamp -Value $Element.GetString()
}

function Assert-SiJsonTimestamps {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][ValidateSet('manifest', 'run')][string]$Schema
    )

    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        $rootElement = $document.RootElement
        if ($Schema -eq 'manifest') {
            foreach ($arrayName in @('pending', 'inFlight')) {
                foreach ($due in $rootElement.GetProperty($arrayName).EnumerateArray()) {
                    Assert-SiTimestampElement -Element $due.GetProperty('createdAtUtc')
                    $deferElement = [System.Text.Json.JsonElement]::new()
                    if ($due.TryGetProperty('deferUntilUtc', [ref]$deferElement)) {
                        Assert-SiTimestampElement -Element $deferElement -AllowNull
                    }
                }
            }
            foreach ($reference in $rootElement.GetProperty('recentRuns').EnumerateArray()) {
                Assert-SiTimestampElement -Element $reference.GetProperty('completedAtUtc')
            }
            return
        }
        Assert-SiTimestampElement -Element $rootElement.GetProperty('createdAtUtc')
        Assert-SiTimestampElement -Element $rootElement.GetProperty('updatedAtUtc')
        Assert-SiTimestampElement -Element $rootElement.GetProperty('completedAtUtc') -AllowNull
    }
    finally {
        $document.Dispose()
    }
}

function Test-SiGitObject {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Object
    )

    & git -C $Root cat-file -e $Object 2>$null
    return $LASTEXITCODE -eq 0
}

function Read-SiPinnedJson {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PinnedOid,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('manifest', 'run')][string]$Schema,
        [Parameter(Mandatory)][long]$MaximumBytes
    )

    $object = "$PinnedOid`:$Path"
    if (-not (Test-SiGitObject -Root $Root -Object $object)) {
        return $null
    }
    $sizeOutput = Invoke-SiGit -Root $Root -Argument @('cat-file', '-s', $object)
    $sizeText = ([string]($sizeOutput | Select-Object -First 1)).Trim()
    $blobBytes = [long]0
    if (-not [long]::TryParse(
            $sizeText,
            [System.Globalization.NumberStyles]::None,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$blobBytes)) {
        throw "Pinned SI $Schema '$Path' did not report a valid blob size."
    }
    if ($blobBytes -gt $MaximumBytes) {
        throw "Pinned SI $Schema '$Path' exceeds its byte limit."
    }
    $json = (Invoke-SiGit -Root $Root -Argument @('show', $object)) -join "`n"
    $schemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../schemas/$Schema.schema.json"))
    if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
        throw 'Pinned SI document failed schema validation.'
    }
    Assert-SiJsonTimestamps -Json $json -Schema $Schema
    $value = $json | ConvertFrom-Json -Depth 100
    if ($Schema -eq 'run') {
        Assert-SiRunIntegrity -Run $value
    }
    return $value
}

function Get-SiOutcomeCounts {
    param([Parameter(Mandatory)]$Run)

    $choices = @($Run.choices)
    return [pscustomobject]@{
        CandidateCount = [int]$Run.rankedSet.count
        AcceptedCount  = @($choices | Where-Object { [string]$_.disposition -eq 'accepted' }).Count
        DeclinedCount  = @($choices | Where-Object { [string]$_.disposition -eq 'declined' }).Count
        DeferredCount  = @($choices | Where-Object { [string]$_.disposition -eq 'deferred' }).Count
        ProposalCount  = @($choices | Where-Object { $null -ne $_.proposalPr }).Count
    }
}

function Assert-SiDueIdentity {
    param([Parameter(Mandatory)]$Due)

    $expected = Get-SiDueId -RepoId ([string]$Due.repoId) -PlanId ([string]$Due.planId) `
        -SourceCommit ([string]$Due.sourceCommit)
    if ($expected -ne [string]$Due.dueId) {
        throw 'Pinned SI due failed its content-address identity check.'
    }
}

function Assert-SiRunDueIdentity {
    param([Parameter(Mandatory)]$Run)

    $expected = Get-SiDueId -RepoId ([string]$Run.provenance.repoId) `
        -PlanId ([string]$Run.provenance.planId) `
        -SourceCommit ([string]$Run.provenance.sourceCommit)
    if ($expected -ne [string]$Run.dueId) {
        throw 'Pinned SI run failed its due identity check.'
    }
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Repository root not found: $root"
}

[void](Invoke-SiGit -Root $root -Argument @(
        'fetch', '--quiet', '--no-tags', 'origin',
        '+refs/heads/main:refs/remotes/origin/main'
    ))
$pinnedOutput = Invoke-SiGit -Root $root -Argument @(
    'rev-parse', '--verify', 'refs/remotes/origin/main^{commit}'
)
$pinnedOid = ([string]($pinnedOutput | Select-Object -First 1)).Trim()
if ($pinnedOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw 'Fetched origin/main did not resolve to a valid commit OID.'
}

$contract = Get-SiStateContract
$stateRoot = @($contract.Topology.RootSegments) -join '/'
$activeRunsRoot = @(
    @($contract.Topology.RootSegments) + @($contract.Topology.ActiveRunsSegments)
) -join '/'
$manifest = Read-SiPinnedJson -Root $root -PinnedOid $pinnedOid `
    -Path "$stateRoot/$($contract.Topology.ManifestName)" -Schema manifest `
    -MaximumBytes $contract.Limits.ManifestBytes
if ($null -ne $manifest) {
    if (@($manifest.pending).Count + @($manifest.inFlight).Count -gt
        $contract.Limits.PendingDues) {
        throw 'Pinned SI pending/in-flight due set exceeds its combined limit.'
    }
    if (@($manifest.inFlight).Count -gt $contract.Limits.ActiveInFlightRuns) {
        throw 'Pinned SI in-flight run set exceeds its limit.'
    }
    if (@($manifest.recentRuns).Count -gt $contract.Limits.ActiveCompletedRuns) {
        throw 'Pinned SI completed run set exceeds its limit.'
    }
    $maximumActiveRuns = $contract.Limits.ActiveCompletedRuns +
        $contract.Limits.ActiveInFlightRuns
}
else {
    $maximumActiveRuns = $contract.Limits.ActiveCompletedRuns +
        $contract.Limits.ActiveInFlightRuns
}
$runPaths = @(Invoke-SiGitBoundedLines -Root $root -Argument @(
        'ls-tree', '-r', '--name-only', $pinnedOid, '--', $activeRunsRoot
    ) -MaximumLines $maximumActiveRuns)
foreach ($runPath in $runPaths) {
    if ($runPath -notmatch ('^' + [regex]::Escape($activeRunsRoot) +
            '/[0-9]{4}/[0-9]{2}/[0-9a-f]{64}\.json$')) {
        throw 'Pinned SI active run tree contains an invalid path.'
    }
}
$runPathById = @{}
foreach ($path in $runPaths) {
    $runId = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if ($runPathById.ContainsKey($runId)) {
        throw "Pinned SI run '$runId' exists at multiple paths."
    }
    $runPathById[$runId] = $path
}
$runById = @{}
$completedRunCount = 0
$inFlightRunCount = 0
foreach ($runId in $runPathById.Keys) {
    $run = Read-SiPinnedJson -Root $root -PinnedOid $pinnedOid `
        -Path $runPathById[$runId] -Schema run -MaximumBytes $contract.Limits.RunBytes
    if ([string]$run.runId -ne $runId) {
        throw "Pinned run '$runId' does not match its file name."
    }
    Assert-SiRunDueIdentity -Run $run
    $runById[$runId] = $run
    if ([string]$run.status -in @('declined-before-ranking', 'no-candidates', 'completed')) {
        $completedRunCount++
    }
    else {
        $inFlightRunCount++
    }
}
if ($completedRunCount -gt $contract.Limits.ActiveCompletedRuns) {
    throw 'Pinned SI completed run file set exceeds its limit.'
}
if ($inFlightRunCount -gt $contract.Limits.ActiveInFlightRuns) {
    throw 'Pinned SI in-flight run file set exceeds its limit.'
}

$maximumDueBranches = $contract.Limits.PendingDues + $contract.Limits.RecentRunReferences
$maximumBranches = $maximumDueBranches + $contract.Limits.AuxiliaryRecordsPerKind
$remoteLines = Invoke-SiGitBoundedLines -Root $root -Argument @(
    'ls-remote', '--heads', 'origin', 'refs/heads/si/*', 'refs/heads/si-repair/*'
) -MaximumLines $maximumBranches
$dueBranches = @{}
$repairBranches = [System.Collections.Generic.List[object]]::new()
foreach ($line in $remoteLines) {
    if ($line -notmatch '^(?<oid>[0-9a-f]{40}|[0-9a-f]{64})\s+refs/heads/(?<branch>.+)$') {
        throw 'Remote SI branch listing contained an invalid record.'
    }
    $headOid = $Matches.oid
    $branch = $Matches.branch
    if ($branch -match '^si/(?<id>[0-9a-f]{64})$') {
        if ($dueBranches.ContainsKey($Matches.id)) {
            throw "Remote due branch '$branch' was listed more than once."
        }
        $dueBranches[$Matches.id] = $headOid
    }
    elseif ($branch -match '^si-repair/(?<id>[0-9a-f]{64})$') {
        $repairBranches.Add([pscustomobject][ordered]@{
                observationId = $Matches.id
                branchName    = $branch
                headOid       = $headOid
                state         = 'repair-pending'
            })
    }
    else {
        throw 'Remote SI branch does not use a fixed lifecycle identifier.'
    }
}
if ($dueBranches.Count -gt $maximumDueBranches -or
    $repairBranches.Count -gt $contract.Limits.AuxiliaryRecordsPerKind) {
    throw 'Remote SI fixed-branch set exceeds its limit.'
}

$items = [System.Collections.Generic.List[object]]::new()
$knownDueIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)
$referencedRunIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)
if ($null -ne $manifest) {
    foreach ($due in @($manifest.pending)) {
        $dueId = [string]$due.dueId
        Assert-SiDueIdentity -Due $due
        if (-not $knownDueIds.Add($dueId)) {
            throw 'Pinned SI manifest contains a duplicate due identity.'
        }
        $hasDeferUntil = $due.PSObject.Properties.Name -contains 'deferUntilUtc' -and
            $null -ne $due.deferUntilUtc
        $deferInstant = if ($hasDeferUntil) {
            [datetimeoffset]$due.deferUntilUtc
        }
        else {
            $null
        }
        $deferUntil = if ($null -eq $deferInstant) { $null } else {
            $deferInstant.ToUniversalTime().ToString('o')
        }
        $state = if ($null -ne $deferInstant -and
            $deferInstant -gt $AsOfUtc.ToUniversalTime()) {
            'deferred-until'
        }
        else {
            'pending'
        }
        $items.Add([pscustomobject][ordered]@{
                dueId          = $dueId
                runId          = $null
                state          = $state
                deferUntilUtc  = $deferUntil
                branchName     = "si/$dueId"
                branchState    = if ($dueBranches.ContainsKey($dueId)) { 'present' } else { 'absent' }
                branchHeadOid  = if ($dueBranches.ContainsKey($dueId)) { $dueBranches[$dueId] } else { $null }
                candidateCount = 0
                acceptedCount  = 0
                declinedCount  = 0
                deferredCount  = 0
                proposalCount  = 0
            })
    }

    foreach ($due in @($manifest.inFlight)) {
        $dueId = [string]$due.dueId
        $runId = [string]$due.runId
        Assert-SiDueIdentity -Due $due
        if (-not $knownDueIds.Add($dueId)) {
            throw 'Pinned SI manifest contains a duplicate due identity.'
        }
        if (-not $runById.ContainsKey($runId)) {
            throw "Pinned in-flight run '$runId' is missing."
        }
        if (-not $referencedRunIds.Add($runId)) {
            throw 'Pinned SI manifest contains a duplicate run reference.'
        }
        $run = $runById[$runId]
        Assert-SiRunDueIdentity -Run $run
        if ([string]$run.runId -ne $runId -or [string]$run.dueId -ne $dueId -or
            [string]$run.status -notin @('resumable', 'ranked', 'proposal-pending') -or
            [string]$run.provenance.repoId -ne [string]$due.repoId -or
            [string]$run.provenance.planId -ne [string]$due.planId -or
            [string]$run.provenance.sourceCommit -ne [string]$due.sourceCommit) {
            throw "Pinned in-flight run '$runId' does not match its manifest reference."
        }
        $counts = Get-SiOutcomeCounts -Run $run
        $items.Add([pscustomobject][ordered]@{
                dueId          = $dueId
                runId          = $runId
                state          = [string]$run.status
                deferUntilUtc  = $null
                branchName     = "si/$dueId"
                branchState    = if ($dueBranches.ContainsKey($dueId)) { 'present' } else { 'absent' }
                branchHeadOid  = if ($dueBranches.ContainsKey($dueId)) { $dueBranches[$dueId] } else { $null }
                candidateCount = $counts.CandidateCount
                acceptedCount  = $counts.AcceptedCount
                declinedCount  = $counts.DeclinedCount
                deferredCount  = $counts.DeferredCount
                proposalCount  = $counts.ProposalCount
            })
    }

    foreach ($reference in @($manifest.recentRuns)) {
        $dueId = [string]$reference.dueId
        $runId = [string]$reference.runId
        if (-not $knownDueIds.Add($dueId)) {
            throw 'Pinned SI manifest contains a duplicate due identity.'
        }
        if (-not $runById.ContainsKey($runId) -or
            $runPathById[$runId] -ne [string]$reference.path) {
            throw "Pinned recent run '$runId' is missing or has a different path."
        }
        if (-not $referencedRunIds.Add($runId)) {
            throw 'Pinned SI manifest contains a duplicate run reference.'
        }
        $run = $runById[$runId]
        Assert-SiRunDueIdentity -Run $run
        if ([string]$run.runId -ne $runId -or
            [string]$run.dueId -ne $dueId -or
            [string]$run.status -ne [string]$reference.status) {
            throw "Pinned recent run '$runId' does not match its manifest reference."
        }
        $counts = Get-SiOutcomeCounts -Run $run
        $items.Add([pscustomobject][ordered]@{
                dueId          = $dueId
                runId          = $runId
                state          = [string]$run.status
                deferUntilUtc  = $null
                branchName     = "si/$dueId"
                branchState    = if ($dueBranches.ContainsKey($dueId)) { 'present' } else { 'absent' }
                branchHeadOid  = if ($dueBranches.ContainsKey($dueId)) { $dueBranches[$dueId] } else { $null }
                candidateCount = $counts.CandidateCount
                acceptedCount  = $counts.AcceptedCount
                declinedCount  = $counts.DeclinedCount
                deferredCount  = $counts.DeferredCount
                proposalCount  = $counts.ProposalCount
            })
    }
}

$orphanDueBranches = @($dueBranches.GetEnumerator() |
        Where-Object { -not $knownDueIds.Contains([string]$_.Key) } |
        Sort-Object Key |
        ForEach-Object {
            [pscustomobject][ordered]@{
                dueId = [string]$_.Key
                branchName = "si/$($_.Key)"
                headOid = [string]$_.Value
                state = 'orphan-due-branch'
            }
        })
$orphanRuns = @($runById.GetEnumerator() |
        Where-Object { -not $referencedRunIds.Contains([string]$_.Key) } |
        Sort-Object Key |
        ForEach-Object {
            [pscustomobject][ordered]@{
                runId = [string]$_.Key
                dueId = [string]$_.Value.dueId
                runStatus = [string]$_.Value.status
                state = 'repairable-orphan'
            }
        })

return [pscustomobject][ordered]@{
    Status            = if ($null -eq $manifest -and $dueBranches.Count -eq 0 -and
        $repairBranches.Count -eq 0 -and $runById.Count -eq 0) { 'empty' } else { 'complete' }
    Operation         = $Operation
    PinnedBaseOid     = $pinnedOid
    ManifestStatus    = if ($null -eq $manifest) { 'absent' } else { 'valid' }
    Generation        = if ($null -eq $manifest) { $null } else { [int]$manifest.generation }
    Items             = @($items | Sort-Object dueId)
    RepairBranches    = @($repairBranches | Sort-Object observationId)
    OrphanDueBranches = $orphanDueBranches
    OrphanRuns        = $orphanRuns
}
