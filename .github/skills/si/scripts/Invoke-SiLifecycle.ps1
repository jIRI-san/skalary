#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [ValidateSet('Surface', 'Begin', 'RecordChoices')][string]$Operation = 'Surface',
    [ValidatePattern('^[0-9a-f]{64}$')][string]$DueId,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$RunId,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$Receipt,
    [string]$InputPath,
    [datetimeoffset]$AsOfUtc = [datetimeoffset]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force

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

function Read-SiLifecycleInput {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][ValidateSet('candidates', 'choices')][string]$Property
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Lifecycle input file not found: $Path"
        }
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -gt 1MB) {
            throw 'Lifecycle input exceeds 1 MiB.'
        }
        try {
            $json = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $value = $json | ConvertFrom-Json -Depth 100
        }
        catch {
            throw "Lifecycle input is not valid UTF-8 JSON: $($_.Exception.Message)"
        }
        if ($null -eq $value -or
            $value.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            throw "Lifecycle input must be an object containing only '$Property'."
        }
        $names = @($value.PSObject.Properties.Name)
        if ($names.Count -ne 1 -or $names[0] -ne $Property -or
            $value.$Property -isnot [System.Array]) {
            throw "Lifecycle input must contain only a '$Property' array."
        }
        return ,@($value.$Property)
    }

    function Read-SiHarvestIndex {
        param([Parameter(Mandatory)][string]$Root)

        $path = Resolve-SiStatePath -RepoRoot $Root -Segments @('harvest-index.json')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Current SI harvest index is absent.'
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -gt (Get-SiStateContract).Limits.HarvestIndexBytes) {
            throw 'Current SI harvest index exceeds its byte limit.'
        }
        try {
            $json = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $index = $json | ConvertFrom-Json -Depth 100
        }
        catch {
            throw 'Current SI harvest index is malformed.'
        }
        $required = @(
            'schemaVersion', 'protocol', 'planId', 'planPath', 'pinnedBaseOid',
            'snapshotDigest', 'selectedDigest', 'fileCount', 'scannedByteCount',
            'sourceCount', 'recordCount', 'selectedByteCount', 'sources', 'selectedRecords'
        )
        $names = @($index.PSObject.Properties.Name)
        if ($names.Count -ne $required.Count -or
            @($required | Where-Object { $names -notcontains $_ }).Count -gt 0 -or
            [int]$index.schemaVersion -ne 1 -or
            [string]$index.protocol -ne 'si-harvest-index-v1') {
            throw 'Current SI harvest index failed closed-shape validation.'
        }
        return $index
    }

    function Assert-SiReceiptBinding {
        param(
            [Parameter(Mandatory)]$VerifiedReceipt,
            [Parameter(Mandatory)]$HarvestIndex,
            [Parameter(Mandatory)][string]$PinnedOid,
            [Parameter(Mandatory)][string]$ExpectedDueId,
            [Parameter(Mandatory)][string]$ExpectedRunId
        )

        $payload = $VerifiedReceipt.Payload
        if ([string]$payload.dueId -ne $ExpectedDueId -or
            [string]$payload.runId -ne $ExpectedRunId) {
            throw 'Resolver receipt belongs to a different due or run.'
        }
        if ([string]$payload.pinnedBaseOid -ne $PinnedOid) {
            throw 'Resolver receipt is stale for the current pinned origin/main.'
        }
        if ([string]$HarvestIndex.pinnedBaseOid -ne $PinnedOid -or
            [string]$HarvestIndex.snapshotDigest -ne [string]$payload.snapshotDigest -or
            [string]$HarvestIndex.selectedDigest -ne [string]$payload.selectedDigest) {
            throw 'Resolver receipt is stale for the current harvest snapshot.'
        }
    }

    function ConvertTo-SiValidatedRanking {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidate,
            [Parameter(Mandatory)]$ReceiptPayload
        )

        $ranked = New-SiRankedCandidates -Candidate $Candidate
        if (($ranked.CandidateIds -join ',') -ne
            (@($ReceiptPayload.candidates) -join ',') -or
            [string]$ranked.RankedSetDigest -ne [string]$ReceiptPayload.rankedSetDigest) {
            throw 'Candidate input does not exactly match the resolver receipt.'
        }
        return [pscustomobject][ordered]@{
            count      = $ranked.Candidates.Count
            digest     = $ranked.RankedSetDigest
            candidates = $ranked.Candidates
        }
    }

    function ConvertTo-SiValidatedChoices {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Choice,
            [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CandidateId
        )

        if ($Choice.Count -ne $CandidateId.Count) {
            throw 'Choices must cover the complete resolver candidate set.'
        }
        $byId = @{}
        foreach ($item in $Choice) {
            if ($null -eq $item -or
                $item.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
                throw 'Each choice must be a closed JSON object.'
            }
            $names = @($item.PSObject.Properties.Name)
            if ($names.Count -ne 3 -or
                @('candidateId', 'disposition', 'proposalPr' |
                    Where-Object { $names -notcontains $_ }).Count -gt 0) {
                throw 'Each choice must contain only candidateId, disposition, and proposalPr.'
            }
            $candidate = [string]$item.candidateId
            if ($candidate -notmatch '^[0-9a-f]{64}$' -or
                $CandidateId -notcontains $candidate) {
                throw "Choice references fabricated candidate '$candidate'."
            }
            if ($byId.ContainsKey($candidate)) {
                throw "Choice candidate '$candidate' is duplicated."
            }
            if ([string]$item.disposition -notin @('accepted', 'declined', 'deferred')) {
                throw "Choice for '$candidate' has an invalid disposition."
            }
            if ($null -ne $item.proposalPr) {
                throw 'RecordChoices requires proposalPr to remain null before proposal creation.'
            }
            $byId[$candidate] = [pscustomobject][ordered]@{
                candidateId = $candidate
                disposition = [string]$item.disposition
                proposalPr  = $null
            }
        }
        return ,@($CandidateId | ForEach-Object { $byId[$_] })
    }

    function Test-SiGitRef {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$Ref
        )

        & git -C $Root show-ref --verify --quiet $Ref
        $code = $LASTEXITCODE
        if ($code -eq 0) { return $true }
        if ($code -eq 1) { return $false }
        throw "git 'show-ref' failed with exit code $code."
    }

    function Set-SiFixedBranch {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$PinnedOid,
            [Parameter(Mandatory)][string]$ExpectedDueId
        )

        $branch = "si/$ExpectedDueId"
        $localRef = "refs/heads/$branch"
        $remoteRef = "refs/remotes/origin/$branch"
        $currentHead = ((Invoke-SiGit -Root $Root -Argument @(
                    'rev-parse', '--verify', 'HEAD^{commit}'
                )) | Select-Object -First 1).Trim()
        $current = try {
            ((Invoke-SiGit -Root $Root -Argument @(
                        'symbolic-ref', '--quiet', '--short', 'HEAD'
                    )) | Select-Object -First 1).Trim()
        }
        catch {
            $null
        }
        if ($current -ne $branch) {
            if (Test-SiGitRef -Root $Root -Ref $localRef) {
                $localHead = ((Invoke-SiGit -Root $Root -Argument @(
                            'rev-parse', '--verify', "$localRef^{commit}"
                        )) | Select-Object -First 1).Trim()
                if ($currentHead -ne $localHead) {
                    throw "Resume fixed SI branch '$branch' from a worktree pinned at '$localHead' before generating lifecycle artifacts."
                }
                [void](Invoke-SiGit -Root $Root -Argument @('switch', '--quiet', $branch))
            }
            else {
                $remote = @(Invoke-SiGitBoundedLines -Root $Root -Argument @(
                        'ls-remote', '--heads', 'origin', "refs/heads/$branch"
                    ) -MaximumLines 1)
                if ($remote.Count -eq 1) {
                    [void](Invoke-SiGit -Root $Root -Argument @(
                            'fetch', '--quiet', '--no-tags', 'origin',
                            "+refs/heads/$branch`:$remoteRef"
                        ))
                    $remoteHead = ((Invoke-SiGit -Root $Root -Argument @(
                                'rev-parse', '--verify', "$remoteRef^{commit}"
                            )) | Select-Object -First 1).Trim()
                    if ($currentHead -ne $remoteHead) {
                        throw "Resume fixed SI branch '$branch' from a worktree pinned at '$remoteHead' before generating lifecycle artifacts."
                    }
                    [void](Invoke-SiGit -Root $Root -Argument @(
                            'switch', '--quiet', '--create', $branch, $remoteRef
                        ))
                }
                else {
                    [void](Invoke-SiGit -Root $Root -Argument @(
                            'switch', '--quiet', '--create', $branch, $PinnedOid
                        ))
                }
            }
        }
        & git -C $Root merge-base --is-ancestor $PinnedOid $branch
        if ($LASTEXITCODE -ne 0) {
            throw "Fixed SI branch '$branch' does not contain the pinned origin/main."
        }
        return $branch
    }

    function Get-SiLifecycleRun {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$ExpectedRunId
        )

        $runsRoot = Resolve-SiStatePath -RepoRoot $Root -Segments @('runs')
        $matches = @(Get-ChildItem -LiteralPath $runsRoot -Filter "$ExpectedRunId.json" `
                -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 2)
        if ($matches.Count -gt 1) {
            throw "Run '$ExpectedRunId' exists at multiple active paths."
        }
        if ($matches.Count -eq 0) { return $null }
        if ($matches[0].Length -gt (Get-SiStateContract).Limits.RunBytes) {
            throw "Run '$ExpectedRunId' exceeds its byte limit."
        }
        try {
            $json = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                [System.IO.File]::ReadAllBytes($matches[0].FullName)
            )
            $run = $json | ConvertFrom-Json -Depth 100
        }
        catch {
            throw "Run '$ExpectedRunId' is not valid UTF-8 JSON."
        }
        $schemaPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '../schemas/run.schema.json')
        )
        if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
            throw "Run '$ExpectedRunId' failed closed-schema validation."
        }
        Assert-SiJsonTimestamps -Json $json -Schema run
        Assert-SiRunIntegrity -Run $run
        return $run
    }

    function Invoke-SiStateTransition {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][ValidateSet('Begin', 'RecordRanking', 'RecordChoices')][string]$Transition,
            [Parameter(Mandatory)]$Request
        )

        $temporary = Join-Path ([System.IO.Path]::GetTempPath()) (
            'si-lifecycle-' + [Guid]::NewGuid().ToString('N') + '.json'
        )
        try {
            [System.IO.File]::WriteAllText(
                $temporary,
                (($Request | ConvertTo-Json -Depth 100 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )
            return & (Join-Path $PSScriptRoot 'Update-SiState.ps1') `
                -RepoRoot $Root -Operation $Transition -InputPath $temporary
        }
        finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force
            }
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
    $pinnedRunId = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if ($runPathById.ContainsKey($pinnedRunId)) {
        throw "Pinned SI run '$pinnedRunId' exists at multiple paths."
    }
    $runPathById[$pinnedRunId] = $path
}
$runById = @{}
$completedRunCount = 0
$inFlightRunCount = 0
foreach ($pinnedRunId in $runPathById.Keys) {
    $run = Read-SiPinnedJson -Root $root -PinnedOid $pinnedOid `
        -Path $runPathById[$pinnedRunId] -Schema run -MaximumBytes $contract.Limits.RunBytes
    if ([string]$run.runId -ne $pinnedRunId) {
        throw "Pinned run '$pinnedRunId' does not match its file name."
    }
    Assert-SiRunDueIdentity -Run $run
    $runById[$pinnedRunId] = $run
    if ([string]$run.status -in @('declined-before-ranking', 'no-candidates', 'completed')) {
        $completedRunCount++
    }
    else {
        $inFlightRunCount++
    }
}

if ($Operation -ne 'Surface') {
    foreach ($requiredArgument in @('DueId', 'RunId', 'Receipt', 'InputPath')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $requiredArgument -ValueOnly))) {
            throw "$Operation requires -$requiredArgument."
        }
    }
    if ($null -eq $manifest) {
        throw 'Pinned origin/main has no authoritative SI manifest.'
    }
    $authoritativeDue = @(
        @($manifest.pending) + @($manifest.inFlight) |
            Where-Object { [string]$_.dueId -eq $DueId }
    )
    if ($authoritativeDue.Count -ne 1) {
        throw "Due '$DueId' is absent from authoritative active state."
    }
    Assert-SiDueIdentity -Due $authoritativeDue[0]
    if ([string]$authoritativeDue[0].status -eq 'in-flight' -and
        [string]$authoritativeDue[0].runId -ne $RunId) {
        throw "Due '$DueId' is already bound to a different run."
    }

    $verifiedReceipt = & (Join-Path $PSScriptRoot 'Test-SiResolverReceipt.ps1') `
        -RepoRoot $root -Receipt $Receipt
    $harvestIndex = Read-SiHarvestIndex -Root $root
    Assert-SiReceiptBinding -VerifiedReceipt $verifiedReceipt `
        -HarvestIndex $harvestIndex -PinnedOid $pinnedOid `
        -ExpectedDueId $DueId -ExpectedRunId $RunId

    $candidateIds = [string[]]@($verifiedReceipt.Payload.candidates)
    $rankedSet = $null
    $choices = $null
    if ($Operation -eq 'Begin') {
        $candidateInput = Read-SiLifecycleInput -Path $InputPath -Property candidates
        $rankedSet = ConvertTo-SiValidatedRanking -Candidate $candidateInput `
            -ReceiptPayload $verifiedReceipt.Payload
    }
    else {
        $choiceInput = Read-SiLifecycleInput -Path $InputPath -Property choices
        $choices = ConvertTo-SiValidatedChoices -Choice $choiceInput `
            -CandidateId $candidateIds
    }

    $branchName = Set-SiFixedBranch -Root $root -PinnedOid $pinnedOid `
        -ExpectedDueId $DueId
    $run = Get-SiLifecycleRun -Root $root -ExpectedRunId $RunId
    if ($null -ne $run) {
        if ([string]$run.dueId -ne $DueId -or
            [string]$run.provenance.pinnedBaseOid -ne $pinnedOid) {
            throw "Run '$RunId' does not match the current due and pinned base."
        }
        if ([string]$run.status -ne 'resumable') {
            if ([string]$run.provenance.resolverReceiptId -ne $Receipt -or
                [string]$run.rankedSet.digest -ne
                [string]$verifiedReceipt.Payload.rankedSetDigest -or
                (@($run.rankedSet.candidates | ForEach-Object {
                            [string]$_.candidateId
                        }) -join ',') -ne ($candidateIds -join ',')) {
                throw "Run '$RunId' is bound to different resolver input."
            }
        }
    }

    $mutated = $false
    if ($Operation -eq 'Begin') {
        if ($null -eq $run -or [string]$run.status -eq 'resumable') {
            [void](Invoke-SiStateTransition -Root $root -Transition Begin -Request ([ordered]@{
                        dueId         = $DueId
                        runId         = $RunId
                        pinnedBaseOid = $pinnedOid
                    }))
            [void](Invoke-SiStateTransition -Root $root -Transition RecordRanking -Request ([ordered]@{
                        dueId             = $DueId
                        runId             = $RunId
                        resolverReceiptId = $Receipt
                        rankedSet         = $rankedSet
                    }))
            $mutated = $true
            $run = Get-SiLifecycleRun -Root $root -ExpectedRunId $RunId
        }
        elseif ([string]$run.status -notin @(
                'ranked', 'proposal-pending', 'no-candidates', 'completed'
            )) {
            throw "Begin cannot resume run status '$($run.status)'."
        }
    }
    elseif ($null -eq $run) {
        throw "RecordChoices requires existing run '$RunId'."
    }
    elseif ($candidateIds.Count -eq 0 -and [string]$run.status -eq 'no-candidates') {
        if ($choices.Count -ne 0) {
            throw 'A no-candidate run cannot record choices.'
        }
    }
    elseif ([string]$run.status -eq 'ranked') {
        [void](Invoke-SiStateTransition -Root $root -Transition RecordChoices -Request ([ordered]@{
                    dueId  = $DueId
                    runId  = $RunId
                    choices = $choices
                }))
        $mutated = $true
        $run = Get-SiLifecycleRun -Root $root -ExpectedRunId $RunId
    }
    elseif ([string]$run.status -eq 'proposal-pending') {
        if ((ConvertTo-SiJcsJson -Value @($run.choices)) -ne
            (ConvertTo-SiJcsJson -Value @($choices))) {
            throw "Run '$RunId' already records different choices."
        }
    }
    else {
        throw "RecordChoices cannot resume run status '$($run.status)'."
    }

    return [pscustomobject][ordered]@{
        Status         = 'complete'
        Operation      = $Operation
        PinnedBaseOid  = $pinnedOid
        DueId          = $DueId
        RunId          = $RunId
        ReceiptId      = $Receipt
        BranchName     = $branchName
        RunStatus      = [string]$run.status
        CandidateCount = $candidateIds.Count
        Mutated        = $mutated
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
