#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$PullRequestNumber,
    [ValidateSet('MERGE', 'SQUASH', 'REBASE')][string]$MergeMethod = 'SQUASH',
    [Parameter(Mandatory, ParameterSetName = 'Run')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$DueId,
    [Parameter(Mandatory, ParameterSetName = 'Run')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$RunId,
    [Parameter(Mandatory, ParameterSetName = 'Run')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$Receipt,
    [Parameter(Mandatory, ParameterSetName = 'Run')]
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$LifecycleHeadOid,
    [Parameter(Mandatory, ParameterSetName = 'Repair')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$Observation,
    [Parameter(Mandatory, ParameterSetName = 'Repair')]
    [ValidatePattern('^[0-9a-f]{64}$')][string]$RepairReceipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SiCompletionParameterSet = $PSCmdlet.ParameterSetName

function Invoke-SiCompletionGit {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument,
        [switch]$AllowFailure
    )

    $output = @(& git -C $Root @Argument 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git '$($Argument[0])' failed with exit code $code."
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Get-SiCompletionOid {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Ref
    )

    $result = Invoke-SiCompletionGit -Root $Root -Argument @(
        'rev-parse', '--verify', "$Ref^{commit}"
    )
    $oid = ([string]($result.Output | Select-Object -First 1)).Trim()
    if ($oid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw "Git ref '$Ref' did not resolve to a valid commit OID."
    }
    return $oid
}

function Get-SiCompletionRemoteHead {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Branch
    )

    $result = Invoke-SiCompletionGit -Root $Root -Argument @(
        'ls-remote', '--heads', 'origin', "refs/heads/$Branch"
    )
    $lines = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -ne 1 -or [string]$lines[0] -notmatch
        '^(?<oid>[0-9a-f]{40}|[0-9a-f]{64})\s+refs/heads/.+$') {
        throw "Remote branch '$Branch' did not return exactly one valid head."
    }
    return $Matches.oid
}

function Get-SiCompletionDiffPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Range
    )

    $result = Invoke-SiCompletionGit -Root $Root -Argument @(
        'diff', '--name-only', '--no-renames', '-z', $Range
    )
    return @(($result.Output -join "`n").Split([char]0, [char]10) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-SiProvider {
    param([Parameter(Mandatory)][string[]]$Argument)

    $output = @(& gh @Argument 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub provider request failed with exit code $LASTEXITCODE."
    }
    $json = $output -join "`n"
    try {
        return $json | ConvertFrom-Json -Depth 100 -DateKind String
    }
    catch {
        throw 'GitHub provider returned malformed JSON.'
    }
}

function Get-SiProviderRepository {
    param([Parameter(Mandatory)][string]$Root)

    $remoteResult = Invoke-SiCompletionGit -Root $Root -Argument @(
        'remote', 'get-url', 'origin'
    )
    $remote = ([string]($remoteResult.Output | Select-Object -First 1)).Trim()
    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw 'Git origin URL is absent.'
    }
    $result = @(& gh repo view $remote --json nameWithOwner --jq .nameWithOwner 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to resolve the GitHub repository identity.'
    }
    $name = ([string]($result | Select-Object -First 1)).Trim()
    if ($name -notmatch '^[^/\s]+/[^/\s]+$') {
        throw 'GitHub repository identity is invalid.'
    }
    return $name
}

function Get-SiPullRequest {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Number
    )

    $query = @'
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      id number url state merged isDraft baseRefName headRefName headRefOid
      baseRefOid mergedAt mergeCommit{oid}
      headRepository{nameWithOwner}
    }
  }
}
'@
    $response = Invoke-SiProvider -Argument @(
        'api', 'graphql', '-f', "query=$query",
        '-F', "owner=$Owner", '-F', "name=$Name", '-F', "number=$Number"
    )
    if ($response.PSObject.Properties.Name -contains 'errors' -or
        $null -eq $response.data.repository.pullRequest) {
        throw "GitHub pull request '$Number' could not be resolved."
    }
    return $response.data.repository.pullRequest
}

function Assert-SiPullRequestIdentity {
    param(
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ExpectedHeadOid,
        [Parameter(Mandatory)][string]$ExpectedBaseOid
    )

    if ([bool]$PullRequest.merged -or [string]$PullRequest.state -ne 'OPEN' -or
        [string]$PullRequest.baseRefName -ne 'main' -or
        [string]$PullRequest.headRefName -ne $Branch -or
        [string]$PullRequest.headRepository.nameWithOwner -ne $RepositoryName -or
        [string]$PullRequest.headRefOid -ne $ExpectedHeadOid -or
        [string]$PullRequest.baseRefOid -ne $ExpectedBaseOid) {
        throw 'GitHub pull request does not match the open fixed-branch SI transition.'
    }
}

function Get-SiMergedPullRequestBase {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$PinnedMainOid
    )

    $baseOid = [string]$PullRequest.baseRefOid
    $mergeOid = [string]$PullRequest.mergeCommit.oid
    if ($baseOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        $mergeOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'Merged GitHub pull request has invalid base or merge authority.'
    }
    foreach ($edge in @(
            [pscustomobject]@{
                Ancestor = $baseOid
                Descendant = $mergeOid
                Message = 'Merged GitHub pull request does not descend from its historical base.'
            },
            [pscustomobject]@{
                Ancestor = $mergeOid
                Descendant = $PinnedMainOid
                Message = 'Merged GitHub pull request is absent from fetched origin/main.'
            }
        )) {
        if ((Invoke-SiCompletionGit -Root $Root -Argument @(
                    'merge-base', '--is-ancestor', $edge.Ancestor, $edge.Descendant
                ) -AllowFailure).ExitCode -ne 0) {
            throw $edge.Message
        }
    }
    return $baseOid
}

function Invoke-SiExpectedHeadMerge {
    param(
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$ExpectedHeadOid
    )

    $query = if ([bool]$PullRequest.isDraft) {
        @'
mutation($id:ID!,$expectedHeadOid:GitObjectID!,$mergeMethod:PullRequestMergeMethod!){
  ready:markPullRequestReadyForReview(input:{pullRequestId:$id}){pullRequest{isDraft}}
  merge:mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$expectedHeadOid,mergeMethod:$mergeMethod}){
    pullRequest{merged mergedAt}
  }
}
'@
    }
    else {
        @'
mutation($id:ID!,$expectedHeadOid:GitObjectID!,$mergeMethod:PullRequestMergeMethod!){
  merge:mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$expectedHeadOid,mergeMethod:$mergeMethod}){
    pullRequest{merged mergedAt}
  }
}
'@
    }
    $response = Invoke-SiProvider -Argument @(
        'api', 'graphql', '-f', "query=$query",
        '-F', "id=$($PullRequest.id)", '-F', "expectedHeadOid=$ExpectedHeadOid",
        '-F', "mergeMethod=$MergeMethod"
    )
    if ($response.PSObject.Properties.Name -contains 'errors' -or
        -not [bool]$response.data.merge.pullRequest.merged) {
        throw 'GitHub refused the expected-head SI proposal merge.'
    }
    return $response.data.merge.pullRequest
}

function Invoke-SiTrustedScopeGuard {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseRef
    )

    $guard = Join-Path $PSScriptRoot 'Test-SiWriteScope.ps1'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @(
            '-NoProfile', '-File', $guard, '-RepoRoot', $Root, '-BaseRef', $BaseRef
        )) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Unable to start trusted SI scope guard.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Trusted SI write-scope guard refused the proposal: $($output.Trim())"
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-SiCompletionPaths {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseOid,
        [Parameter(Mandatory)][string]$HeadOid,
        [switch]$RepairOnly
    )

    $paths = @(Get-SiCompletionDiffPath -Root $Root -Range "$BaseOid...$HeadOid")
    $validator = Join-Path $PSScriptRoot 'Invoke-SiProposalSync.ps1'
    $validation = @(& $validator -Operation ValidatePaths -Path $paths)
    $denied = @($validation | Where-Object Denied)
    if ($denied.Count -gt 0) {
        throw "Proposal touches protected SI trust anchor '$($denied[0].Path)'."
    }
    if ($RepairOnly) {
        $outsideState = @($paths | Where-Object {
                -not $_.Replace('\', '/').StartsWith(
                    'docs/self-improvement/',
                    [System.StringComparison]::Ordinal
                )
            })
        if ($outsideState.Count -gt 0) {
            throw "Repair proposal contains non-state path '$($outsideState[0])'."
        }
    }
    Invoke-SiTrustedScopeGuard -Root $Root -BaseRef $BaseOid
}

function Get-SiCompletionRun {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ExpectedRunId
    )

    $runsRoot = Resolve-SiStatePath -RepoRoot $Root -Segments @('runs')
    $matches = @(Get-ChildItem -LiteralPath $runsRoot -Filter "$ExpectedRunId.json" `
            -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 2)
    if ($matches.Count -ne 1) {
        throw "Proposal requires exactly one active run '$ExpectedRunId'."
    }
    $json = [System.IO.File]::ReadAllText($matches[0].FullName)
    if (-not ($json | Test-Json -SchemaFile (
                Join-Path $PSScriptRoot '../schemas/run.schema.json'
            ) -ErrorAction SilentlyContinue)) {
        throw "Proposal run '$ExpectedRunId' failed closed-schema validation."
    }
    $run = $json | ConvertFrom-Json -Depth 100
    Assert-SiRunIntegrity -Run $run
    return [pscustomobject]@{ Value = $run; Path = $matches[0].FullName }
}

function Assert-SiLifecycleChoiceBinding {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$RunRecord
    )

    if ((Invoke-SiCompletionGit -Root $Root -Argument @(
                'merge-base', '--is-ancestor', $LifecycleHeadOid, 'HEAD'
            ) -AllowFailure).ExitCode -ne 0) {
        throw "Lifecycle head '$LifecycleHeadOid' is not an ancestor of the live proposal."
    }
    $runRelative = [System.IO.Path]::GetRelativePath(
        $Root, [string]$RunRecord.Path
    ).Replace('\', '/')
    $object = "$LifecycleHeadOid`:$runRelative"
    $json = (Invoke-SiCompletionGit -Root $Root -Argument @(
            'show', $object
        )).Output -join "`n"
    if (-not ($json | Test-Json -SchemaFile (
                Join-Path $PSScriptRoot '../schemas/run.schema.json'
            ) -ErrorAction SilentlyContinue)) {
        throw 'Operator-held lifecycle run failed schema validation.'
    }
    $lifecycleRun = $json | ConvertFrom-Json -Depth 100
    Assert-SiRunIntegrity -Run $lifecycleRun
    $liveRun = $RunRecord.Value
    $baseOid = [string]$lifecycleRun.provenance.pinnedBaseOid
    if ($baseOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'Operator-held lifecycle run has an invalid pinned base OID.'
    }
    $lifecycleChoices = @($lifecycleRun.choices | ForEach-Object {
            [ordered]@{
                candidateId = [string]$_.candidateId
                disposition = [string]$_.disposition
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    $liveChoices = @($liveRun.choices | ForEach-Object {
            [ordered]@{
                candidateId = [string]$_.candidateId
                disposition = [string]$_.disposition
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    if ([string]$lifecycleRun.runId -ne $RunId -or
        [string]$lifecycleRun.dueId -ne $DueId -or
        [string]$lifecycleRun.provenance.resolverReceiptId -ne $Receipt -or
        [string]$lifecycleRun.status -notin @('proposal-pending', 'no-candidates') -or
        $lifecycleChoices -ne $liveChoices) {
        throw 'Live proposal choices do not match the operator-held lifecycle head.'
    }
    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($path in @(
            'docs/self-improvement/state.json',
            $runRelative,
            "docs/self-improvement/resolver-receipts/$Receipt.json",
            'docs/self-improvement/harvest-index.json'
        )) {
        [void]$allowed.Add($path)
    }
    $lifecyclePaths = @(Get-SiCompletionDiffPath -Root $Root `
            -Range "$BaseOid...$LifecycleHeadOid")
    $unadmitted = @($lifecyclePaths | Where-Object {
            -not $allowed.Contains($_)
        })
    if ($unadmitted.Count -gt 0) {
        throw "Lifecycle head contains unadmitted path '$($unadmitted[0])'."
    }
    return $baseOid
}

function Get-SiPinnedManifest {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseOid
    )

    $object = "$BaseOid`:docs/self-improvement/state.json"
    $json = (Invoke-SiCompletionGit -Root $Root -Argument @(
            'show', $object
        )).Output -join "`n"
    if (-not ($json | Test-Json -SchemaFile (
                Join-Path $PSScriptRoot '../schemas/manifest.schema.json'
            ) -ErrorAction SilentlyContinue)) {
        throw 'Pinned origin/main SI manifest failed schema validation.'
    }
    return $json | ConvertFrom-Json -Depth 100
}

function Assert-SiRunStateDelta {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseOid,
        [Parameter(Mandatory)]$RunRecord,
        [Parameter(Mandatory)]$VerifiedReceipt,
        [Parameter(Mandatory)]$CurrentManifest,
        [Parameter(Mandatory)][string]$ExpectedStatus
    )

    $runRelative = [System.IO.Path]::GetRelativePath(
        $Root, [string]$RunRecord.Path
    ).Replace('\', '/')
    $receiptRelative = [System.IO.Path]::GetRelativePath(
        $Root, [string]$VerifiedReceipt.Path
    ).Replace('\', '/')
    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($path in @(
            'docs/self-improvement/state.json', $runRelative, $receiptRelative
        )) {
        [void]$allowed.Add($path)
    }
    $statePaths = @(Get-SiCompletionDiffPath -Root $Root `
            -Range "$BaseOid...HEAD" | Where-Object {
                $_.Replace('\', '/').StartsWith(
                    'docs/self-improvement/',
                    [System.StringComparison]::Ordinal
                )
            })
    $unexpected = @($statePaths | Where-Object { -not $allowed.Contains($_) })
    if ($unexpected.Count -gt 0) {
        throw "SI completion contains unadmitted state path '$($unexpected[0])'."
    }
    $run = $RunRecord.Value
    if (@($run.choices | Where-Object {
                [string]$_.disposition -eq 'accepted'
            }).Count -eq 0) {
        $allPaths = @(Get-SiCompletionDiffPath -Root $Root -Range "$BaseOid...HEAD")
        $unadmitted = @($allPaths | Where-Object { -not $allowed.Contains($_) })
        if ($unadmitted.Count -gt 0) {
            throw "Record-only SI completion contains non-state path '$($unadmitted[0])'."
        }
    }
    $pinned = Get-SiPinnedManifest -Root $Root -BaseOid $BaseOid
    $pinnedActive = @(
        @($pinned.pending) + @($pinned.inFlight) |
            Where-Object { [string]$_.dueId -eq $DueId }
    )
    if ($pinnedActive.Count -ne 1) {
        throw "Pinned origin/main does not contain exactly one active due '$DueId'."
    }
    $due = $pinnedActive[0]
    if ([string]$run.provenance.repoId -ne [string]$due.repoId -or
        [string]$run.provenance.planId -ne [string]$due.planId -or
        [string]$run.provenance.sourceCommit -ne [string]$due.sourceCommit -or
        [string]$run.provenance.pinnedBaseOid -ne $BaseOid) {
        throw 'SI completion run provenance does not match pinned origin/main.'
    }
    $expectedGeneration = [int]$pinned.generation + $(if (
            [string]$run.status -eq 'completed'
        ) { 2 } else { 1 })
    if ([int64]$CurrentManifest.generation -ne $expectedGeneration) {
        throw "SI completion manifest generation is not the trusted '$expectedGeneration'."
    }
    foreach ($field in @('pending', 'inFlight')) {
        $before = @($pinned.$field | Where-Object {
                [string]$_.dueId -ne $DueId
            }) | ConvertTo-Json -Depth 100 -Compress
        $after = @($CurrentManifest.$field | Where-Object {
                [string]$_.dueId -ne $DueId
            }) | ConvertTo-Json -Depth 100 -Compress
        if ($before -ne $after) {
            throw "SI completion changed unrelated manifest '$field' state."
        }
    }
    $beforeRecent = @($pinned.recentRuns | Where-Object {
            [string]$_.dueId -ne $DueId
        } | Select-Object -First 63) | ConvertTo-Json -Depth 100 -Compress
    $afterRecent = @($CurrentManifest.recentRuns | Where-Object {
            [string]$_.dueId -ne $DueId
        }) | ConvertTo-Json -Depth 100 -Compress
    if ($beforeRecent -ne $afterRecent) {
        throw 'SI completion changed unrelated recent run references.'
    }
    $reference = @($CurrentManifest.recentRuns | Where-Object {
            [string]$_.dueId -eq $DueId -and [string]$_.runId -eq $RunId -and
            [string]$_.status -eq $ExpectedStatus
        })
    if ($reference.Count -ne 1 -or [string]$reference[0].path -ne $runRelative) {
        throw "SI run '$RunId' is absent from the exact recent run reference."
    }
}

function Assert-SiCompletedRun {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$HeadOid,
        [Parameter(Mandatory)][string]$BaseOid
    )

    $verified = & (Join-Path $PSScriptRoot 'Test-SiResolverReceipt.ps1') `
        -RepoRoot $Root -Receipt $Receipt
    $record = Get-SiCompletionRun -Root $Root -ExpectedRunId $RunId
    $run = $record.Value
    if ([string]$run.runId -ne $RunId -or [string]$run.dueId -ne $DueId -or
        [string]$run.status -notin @('completed', 'no-candidates') -or
        [string]$run.provenance.resolverReceiptId -ne $Receipt) {
        throw 'Completed SI run identity or status is invalid.'
    }
    if ([string]$verified.Payload.dueId -ne $DueId -or
        [string]$verified.Payload.runId -ne $RunId -or
        [string]$verified.Payload.rankedSetDigest -ne [string]$run.rankedSet.digest -or
        (@($verified.Payload.candidates) -join ',') -ne
        (@($run.rankedSet.candidates | ForEach-Object { [string]$_.candidateId }) -join ',')) {
        throw 'Completed SI run does not exactly match its resolver receipt.'
    }
    if ([string]$run.status -eq 'no-candidates') {
        if ($null -ne $run.proposalPr -or [int]$run.rankedSet.count -ne 0 -or
            @($run.choices).Count -ne 0) {
            throw 'No-candidate SI record contains proposal or candidate state.'
        }
    }
    else {
        $proposal = $run.proposalPr
        if ($null -eq $proposal -or [string]$proposal.url -ne [string]$PullRequest.url) {
            throw 'Completed SI run does not record the live proposal URL.'
        }
        $proposalHead = [string]$proposal.headOid
        if ($proposalHead -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
            (Invoke-SiCompletionGit -Root $Root -Argument @(
                    'merge-base', '--is-ancestor', $proposalHead, $HeadOid
                ) -AllowFailure).ExitCode -ne 0) {
            throw 'Completed SI run proposal head is not an ancestor of the live head.'
        }
        foreach ($choice in @($run.choices)) {
            if ([string]$choice.disposition -eq 'accepted') {
                if ($null -eq $choice.proposalPr -or
                    [string]$choice.proposalPr.url -ne [string]$PullRequest.url -or
                    [string]$choice.proposalPr.headOid -ne $proposalHead) {
                    throw 'Accepted SI choice does not record the proposal.'
                }
            }
            elseif ($null -ne $choice.proposalPr) {
                throw 'Declined or deferred SI choice records a proposal unexpectedly.'
            }
        }
    }
    $manifest = Read-SiManifest -RepoRoot $Root
    if (@(@($manifest.pending) + @($manifest.inFlight) |
            Where-Object { [string]$_.dueId -eq $DueId }).Count -ne 0) {
        throw "Completed SI due '$DueId' remains active in the proposal manifest."
    }
    Assert-SiRunStateDelta -Root $Root -BaseOid $BaseOid -RunRecord $record `
        -VerifiedReceipt $verified -CurrentManifest $manifest `
        -ExpectedStatus ([string]$run.status)
}

function Complete-SiRunState {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$LiveHeadOid
    )

    $record = Get-SiCompletionRun -Root $Root -ExpectedRunId $RunId
    $run = $record.Value
    if ([string]$run.status -in @('completed', 'no-candidates')) { return $false }
    if ([string]$run.status -ne 'proposal-pending' -or
        [string]$run.dueId -ne $DueId -or
        [string]$run.provenance.resolverReceiptId -ne $Receipt) {
        throw 'SI proposal is not in a completable lifecycle state.'
    }
    $proposal = [pscustomobject][ordered]@{
        url = [string]$PullRequest.url
        headOid = $LiveHeadOid
    }
    $choices = @($run.choices | ForEach-Object {
            [pscustomobject][ordered]@{
                candidateId = [string]$_.candidateId
                disposition = [string]$_.disposition
                proposalPr = if ([string]$_.disposition -eq 'accepted') {
                    $proposal
                }
                else {
                    $null
                }
            }
        })
    $inputPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        'si-complete-' + [Guid]::NewGuid().ToString('N') + '.json'
    )
    try {
        [System.IO.File]::WriteAllText(
            $inputPath,
            (([ordered]@{
                        dueId = $DueId
                        runId = $RunId
                        choices = $choices
                        proposalPr = $proposal
                    } | ConvertTo-Json -Depth 100 -Compress) + "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        $result = & (Join-Path $PSScriptRoot 'Update-SiState.ps1') `
            -RepoRoot $Root -Operation Complete -InputPath $inputPath
        if ($result.Status -ne 'complete') {
            throw "SI completion state update failed with status '$($result.Status)'."
        }
    }
    finally {
        if (Test-Path -LiteralPath $inputPath) {
            Remove-Item -LiteralPath $inputPath -Force
        }
    }
    return $true
}

function Get-SiRepairStateMap {
    param([Parameter(Mandatory)][string]$Root)

    $stateRoot = Split-Path -Parent (Get-SiManifestPath -RepoRoot $Root)
    $files = @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse `
            -ErrorAction SilentlyContinue | Where-Object {
                $relative = [System.IO.Path]::GetRelativePath(
                    $stateRoot, $_.FullName
                ).Replace('\', '/')
                -not $relative.StartsWith(
                    'repair-receipts/',
                    [System.StringComparison]::Ordinal
                ) -and $relative -ne '.state.lock'
            } | Select-Object -First 258)
    if ($files.Count -gt 256) {
        throw 'Repair proposal state exceeds its comparison file limit.'
    }
    $map = [ordered]@{}
    foreach ($file in $files | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath(
            $stateRoot, $file.FullName
        ).Replace('\', '/')
        $map[$relative] = Get-SiArtifactDigest -Path $file.FullName
    }
    return $map
}

function Assert-SiRepairReceipt {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseOid
    )

    $observationPath = Resolve-SiStatePath -RepoRoot $Root -Segments @(
        'repair-observations', "$Observation.json"
    )
    $receiptPath = Resolve-SiStatePath -RepoRoot $Root -Segments @(
        'repair-receipts', "$RepairReceipt.json"
    )
    if (-not (Test-Path -LiteralPath $observationPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw 'Repair proposal is missing its observation or final receipt.'
    }
    $observationJson = [System.IO.File]::ReadAllText($observationPath)
    $repairJson = [System.IO.File]::ReadAllText($receiptPath)
    if (-not ($observationJson | Test-Json -SchemaFile (
                Join-Path $PSScriptRoot '../schemas/repair-observation.schema.json'
            ) -ErrorAction SilentlyContinue) -or
        -not ($repairJson | Test-Json -SchemaFile (
                Join-Path $PSScriptRoot '../schemas/repair-receipt.schema.json'
            ) -ErrorAction SilentlyContinue)) {
        throw 'Repair proposal observation or receipt failed schema validation.'
    }
    $envelope = $observationJson | ConvertFrom-Json -Depth 100
    $payloadJson = $envelope.payload | ConvertTo-Json -Depth 100 -Compress
    $calculatedObservation = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes(
                'si-repair-observation-v1' + $payloadJson
            )
        )
    ).ToLowerInvariant()
    if ([string]$envelope.observationId -ne $Observation -or
        $calculatedObservation -ne $Observation) {
        throw 'Repair proposal observation failed its content-address check.'
    }
    $repair = $repairJson | ConvertFrom-Json -Depth 100 -DateKind String
    $receiptPayload = [ordered]@{
        protocol = [string]$repair.protocol
        observationId = [string]$repair.observationId
        mode = [string]$repair.mode
        beforeDigest = [string]$repair.beforeDigest
        afterDigest = [string]$repair.afterDigest
        createdAtUtc = [string]$repair.createdAtUtc
    }
    $calculatedReceipt = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes(
                ($receiptPayload | ConvertTo-Json -Compress)
            )
        )
    ).ToLowerInvariant()
    if ([string]$repair.receiptId -ne $RepairReceipt -or
        $calculatedReceipt -ne $RepairReceipt -or
        [string]$repair.observationId -ne $Observation) {
        throw 'Repair proposal receipt failed its content-address check.'
    }
    $manifestPath = Get-SiManifestPath -RepoRoot $Root
    if ((Get-SiArtifactDigest -Path $manifestPath) -ne [string]$repair.afterDigest) {
        throw 'Repair proposal state does not match its final receipt.'
    }
    $journal = Resolve-SiStatePath -RepoRoot $Root -Segments @(
        'backups', $Observation, 'apply-journal.json'
    )
    if (Test-Path -LiteralPath $journal -PathType Leaf) {
        throw 'Repair proposal still has an incomplete apply journal.'
    }
    $receiptDelta = @(Get-SiCompletionDiffPath -Root $Root `
            -Range "$BaseOid...HEAD" | Where-Object {
                $_.Replace('\', '/').StartsWith(
                    'docs/self-improvement/repair-receipts/',
                    [System.StringComparison]::Ordinal
                )
            })
    $expectedReceiptPath = "docs/self-improvement/repair-receipts/$RepairReceipt.json"
    if ($receiptDelta.Count -ne 1 -or $receiptDelta[0] -ne $expectedReceiptPath) {
        throw 'Repair proposal contains an unadmitted repair receipt.'
    }

    $replayRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'si-repair-replay-' + [Guid]::NewGuid().ToString('N')
    )
    $replayError = $null
    $cleanupError = $null
    try {
        [void](Invoke-SiCompletionGit -Root $Root -Argument @(
                'worktree', 'add', '--quiet', '--detach', $replayRoot, $BaseOid
            ))
        $replayObservationPath = Resolve-SiStatePath -RepoRoot $replayRoot `
            -Segments @('repair-observations', "$Observation.json")
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $replayObservationPath
            ) -Force)
        [System.IO.File]::WriteAllText(
            $replayObservationPath,
            $observationJson,
            [System.Text.UTF8Encoding]::new($false)
        )
        if ([string]$repair.mode -eq 'apply') {
            if ([string]$envelope.payload.pinnedBaseOid -ne $BaseOid) {
                throw 'Repair observation is not bound to the fetched origin/main OID.'
            }
            $authoritativePayload = Get-SiObservationPayload -RepoRoot $replayRoot `
                -PinnedBaseOid $BaseOid
            if (($authoritativePayload | ConvertTo-Json -Depth 100 -Compress) -ne
                $payloadJson) {
                throw 'Repair observation does not match fetched origin/main state.'
            }
            $replayed = Invoke-SiRepair -RepoRoot $replayRoot -Mode Apply `
                -Observation $Observation
        }
        else {
            $receiptRoot = Split-Path -Parent (
                Resolve-SiStatePath -RepoRoot $replayRoot -Segments @(
                    'repair-receipts', "$RepairReceipt.json"
                )
            )
            $applyReceipts = @(Get-ChildItem -LiteralPath $receiptRoot `
                    -Filter '*.json' -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try {
                            $candidate = Get-Content -LiteralPath $_.FullName -Raw |
                                ConvertFrom-Json -Depth 20
                            if ([string]$candidate.observationId -eq $Observation -and
                                [string]$candidate.mode -eq 'apply' -and
                                [string]$candidate.afterDigest -eq
                                [string]$repair.beforeDigest) {
                                $candidate
                            }
                        }
                        catch { }
                    })
            if ($applyReceipts.Count -ne 1) {
                throw 'Repair rollback has no unique authoritative apply receipt.'
            }
            $replayed = Invoke-SiRepair -RepoRoot $replayRoot -Mode Rollback `
                -Receipt ([string]$applyReceipts[0].receiptId)
        }
        $replayedReceiptPath = Resolve-SiStatePath -RepoRoot $replayRoot `
            -Segments @('repair-receipts', "$($replayed.ReceiptId).json")
        $replayedReceipt = Get-Content -LiteralPath $replayedReceiptPath -Raw |
            ConvertFrom-Json -Depth 20
        if ([string]$replayedReceipt.beforeDigest -ne [string]$repair.beforeDigest -or
            [string]$replayedReceipt.afterDigest -ne [string]$repair.afterDigest -or
            [string]$replayedReceipt.mode -ne [string]$repair.mode) {
            throw 'Repair proposal receipt does not match trusted replay.'
        }
        $proposedMap = Get-SiRepairStateMap -Root $Root
        $replayedMap = Get-SiRepairStateMap -Root $replayRoot
        if (($proposedMap | ConvertTo-Json -Compress) -ne
            ($replayedMap | ConvertTo-Json -Compress)) {
            throw 'Repair proposal state delta does not match trusted replay.'
        }
    }
    catch {
        $replayError = $_
    }
    finally {
        if (Test-Path -LiteralPath $replayRoot) {
            $cleanup = Invoke-SiCompletionGit -Root $Root -Argument @(
                'worktree', 'remove', '--force', $replayRoot
            ) -AllowFailure
            if ($cleanup.ExitCode -ne 0 -or (Test-Path -LiteralPath $replayRoot)) {
                $cleanupError = "Trusted repair replay cleanup failed for '$replayRoot'."
            }
        }
    }
    if ($cleanupError) {
        if ($replayError) {
            throw "$($replayError.Exception.Message) $cleanupError"
        }
        throw $cleanupError
    }
    if ($replayError) { throw $replayError }
}

function Assert-SiMergedPullRequestHead {
    param(
        [Parameter(Mandatory)][string]$TrustedRoot,
        [Parameter(Mandatory)]$PullRequest,
        [Parameter(Mandatory)][string]$AuthoritativeBaseOid
    )

    $headRef = "refs/remotes/origin/si-merged-pr-$PullRequestNumber"
    [void](Invoke-SiCompletionGit -Root $TrustedRoot -Argument @(
            'fetch', '--quiet', '--no-tags', 'origin',
            "+refs/pull/$PullRequestNumber/head`:$headRef"
        ))
    $headOid = Get-SiCompletionOid -Root $TrustedRoot -Ref $headRef
    if ($headOid -ne [string]$PullRequest.headRefOid) {
        throw 'Merged pull request head disagrees with its immutable provider ref.'
    }
    $mergedRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'si-merged-validation-' + [Guid]::NewGuid().ToString('N')
    )
    $validationError = $null
    $cleanupError = $null
    try {
        [void](Invoke-SiCompletionGit -Root $TrustedRoot -Argument @(
                'worktree', 'add', '--quiet', '--detach', $mergedRoot, $headOid
            ))
        if ($script:SiCompletionParameterSet -eq 'Run') {
            $record = Get-SiCompletionRun -Root $mergedRoot -ExpectedRunId $RunId
            $lifecycleBaseOid = Assert-SiLifecycleChoiceBinding -Root $mergedRoot `
                -RunRecord $record
            if ($lifecycleBaseOid -ne $AuthoritativeBaseOid) {
                throw 'Merged lifecycle state does not match the authoritative pull request base.'
            }
            Assert-SiCompletionPaths -Root $mergedRoot `
                -BaseOid $AuthoritativeBaseOid `
                -HeadOid $headOid
            Assert-SiCompletedRun -Root $mergedRoot -PullRequest $PullRequest `
                -HeadOid $headOid -BaseOid $AuthoritativeBaseOid
        }
        else {
            $observationPath = Resolve-SiStatePath -RepoRoot $mergedRoot `
                -Segments @('repair-observations', "$Observation.json")
            if (-not (Test-Path -LiteralPath $observationPath -PathType Leaf)) {
                throw 'Merged repair proposal is missing its observation.'
            }
            $envelope = Get-Content -LiteralPath $observationPath -Raw |
                ConvertFrom-Json -Depth 100
            $baseOid = [string]$envelope.payload.pinnedBaseOid
            if ($baseOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                throw 'Merged repair observation has an invalid pinned base OID.'
            }
            if ($baseOid -ne $AuthoritativeBaseOid) {
                throw 'Merged repair state does not match the authoritative pull request base.'
            }
            Assert-SiCompletionPaths -Root $mergedRoot `
                -BaseOid $AuthoritativeBaseOid `
                -HeadOid $headOid -RepairOnly
            Assert-SiRepairReceipt -Root $mergedRoot `
                -BaseOid $AuthoritativeBaseOid
        }
    }
    catch {
        $validationError = $_
    }
    finally {
        if (Test-Path -LiteralPath $mergedRoot) {
            $cleanup = Invoke-SiCompletionGit -Root $TrustedRoot -Argument @(
                'worktree', 'remove', '--force', $mergedRoot
            ) -AllowFailure
            if ($cleanup.ExitCode -ne 0 -or (Test-Path -LiteralPath $mergedRoot)) {
                $cleanupError = "Merged SI validation worktree cleanup failed for '$mergedRoot'."
            }
        }
    }
    if ($cleanupError) {
        if ($validationError) {
            throw "$($validationError.Exception.Message) $cleanupError"
        }
        throw $cleanupError
    }
    if ($validationError) { throw $validationError }
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Repository root not found: $root"
}
$scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
$expectedScript = [System.IO.Path]::GetFullPath(
    (Join-Path $root '.github/skills/si/scripts/Complete-SiProposal.ps1')
)
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
if (-not $scriptPath.Equals($expectedScript, $comparison)) {
    throw 'Complete-SiProposal must run from the installed trusted checkout.'
}
$branchResult = Invoke-SiCompletionGit -Root $root -Argument @(
    'symbolic-ref', '--quiet', '--short', 'HEAD'
) -AllowFailure
if ($branchResult.ExitCode -eq 0) {
    throw 'Trusted SI completion checkout must have a detached HEAD.'
}
if (@((Invoke-SiCompletionGit -Root $root -Argument @(
                'status', '--porcelain=v1', '--untracked-files=all'
            )).Output).Count -gt 0) {
    throw 'Trusted SI completion checkout must be clean.'
}

[void](Invoke-SiCompletionGit -Root $root -Argument @(
        'fetch', '--quiet', '--no-tags', 'origin',
        '+refs/heads/main:refs/remotes/origin/main'
    ))
$pinnedMain = Get-SiCompletionOid -Root $root -Ref 'refs/remotes/origin/main'
if ((Get-SiCompletionOid -Root $root -Ref 'HEAD') -ne $pinnedMain) {
    throw 'Trusted SI completion checkout is not pinned to fetched origin/main.'
}
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force

$repositoryName = Get-SiProviderRepository -Root $root
$parts = $repositoryName.Split('/', 2)
$pullRequest = Get-SiPullRequest -Owner $parts[0] -Name $parts[1] `
    -Number $PullRequestNumber
$branch = if ($PSCmdlet.ParameterSetName -eq 'Run') {
    "si/$DueId"
}
else {
    "si-repair/$Observation"
}
$liveHead = [string]$pullRequest.headRefOid
if ($liveHead -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw 'GitHub pull request returned an invalid live head OID.'
}
if ([bool]$pullRequest.merged -and [string]$pullRequest.state -eq 'MERGED') {
    if ([string]$pullRequest.baseRefName -ne 'main' -or
        [string]$pullRequest.headRefName -ne $branch -or
        [string]$pullRequest.headRepository.nameWithOwner -ne $repositoryName -or
        [string]::IsNullOrWhiteSpace([string]$pullRequest.mergedAt)) {
        throw 'Merged GitHub pull request does not match the fixed SI transition.'
    }
    $authoritativeBase = Get-SiMergedPullRequestBase -Root $root `
        -PullRequest $pullRequest -PinnedMainOid $pinnedMain
    Assert-SiMergedPullRequestHead -TrustedRoot $root `
        -PullRequest $pullRequest -AuthoritativeBaseOid $authoritativeBase
    return [pscustomobject][ordered]@{
        Status = 'complete'
        PullRequestNumber = $PullRequestNumber
        PullRequestUrl = [string]$pullRequest.url
        BranchName = $branch
        PinnedMainOid = $pinnedMain
        ExpectedHeadOid = $liveHead
        StateCommitted = $false
        MergedAt = [string]$pullRequest.mergedAt
    }
}
Assert-SiPullRequestIdentity -PullRequest $pullRequest `
    -RepositoryName $repositoryName -Branch $branch -ExpectedHeadOid $liveHead `
    -ExpectedBaseOid $pinnedMain
[void](Invoke-SiCompletionGit -Root $root -Argument @(
        'fetch', '--quiet', '--no-tags', 'origin',
        "+refs/heads/$branch`:refs/remotes/origin/$branch"
    ))
if ((Get-SiCompletionOid -Root $root -Ref "refs/remotes/origin/$branch") -ne $liveHead) {
    throw 'GitHub pull request head disagrees with the fetched fixed branch.'
}

$worktree = Join-Path ([System.IO.Path]::GetTempPath()) (
    'si-completion-' + [Guid]::NewGuid().ToString('N')
)
$operationError = $null
$cleanupError = $null
$validatedHead = $liveHead
$stateCommitted = $false
try {
    [void](Invoke-SiCompletionGit -Root $root -Argument @(
            'worktree', 'add', '--quiet', '--detach', $worktree, $liveHead
        ))
    Assert-SiCompletionPaths -Root $worktree -BaseOid $pinnedMain `
        -HeadOid $liveHead -RepairOnly:($PSCmdlet.ParameterSetName -eq 'Repair')
    if ($PSCmdlet.ParameterSetName -eq 'Run') {
        $liveRun = Get-SiCompletionRun -Root $worktree -ExpectedRunId $RunId
        $lifecycleBase = Assert-SiLifecycleChoiceBinding -Root $worktree `
            -RunRecord $liveRun
        if ($lifecycleBase -ne $pinnedMain) {
            throw 'Operator-held lifecycle head is not bound to fetched origin/main.'
        }
        $stateCommitted = Complete-SiRunState -Root $worktree `
            -PullRequest $pullRequest -LiveHeadOid $liveHead
        if ($stateCommitted) {
            [void](Invoke-SiCompletionGit -Root $worktree -Argument @(
                    'add', '--', 'docs/self-improvement'
                ))
            [void](Invoke-SiCompletionGit -Root $worktree -Argument @(
                    'commit', '--quiet', '-m',
                    "chore(self-improvement): complete SI proposal $DueId"
                ))
            $validatedHead = Get-SiCompletionOid -Root $worktree -Ref 'HEAD'
        }
        Assert-SiCompletionPaths -Root $worktree -BaseOid $pinnedMain `
            -HeadOid $validatedHead
        Assert-SiCompletedRun -Root $worktree -PullRequest $pullRequest `
            -HeadOid $validatedHead -BaseOid $pinnedMain
    }
    else {
        Assert-SiRepairReceipt -Root $worktree -BaseOid $pinnedMain
    }
    if ((Get-SiCompletionOid -Root $worktree -Ref 'HEAD') -ne $validatedHead -or
        @((Invoke-SiCompletionGit -Root $worktree -Argument @(
                    'status', '--porcelain=v1', '--untracked-files=all'
                )).Output).Count -gt 0) {
        throw 'SI proposal changed during trusted completion validation.'
    }
    if ((Get-SiCompletionRemoteHead -Root $root -Branch $branch) -ne $liveHead) {
        throw 'Remote SI proposal head changed during completion validation.'
    }
    if ($stateCommitted) {
        [void](Invoke-SiCompletionGit -Root $worktree -Argument @(
                'push', 'origin', "$validatedHead`:refs/heads/$branch"
            ))
        if ((Get-SiCompletionRemoteHead -Root $root -Branch $branch) -ne $validatedHead) {
            throw 'Remote SI proposal head does not equal the completed state OID.'
        }
    }
    $pullRequest = Get-SiPullRequest -Owner $parts[0] -Name $parts[1] `
        -Number $PullRequestNumber
    Assert-SiPullRequestIdentity -PullRequest $pullRequest `
        -RepositoryName $repositoryName -Branch $branch `
        -ExpectedHeadOid $validatedHead -ExpectedBaseOid $pinnedMain
    if ((Get-SiCompletionRemoteHead -Root $root -Branch $branch) -ne
        $validatedHead) {
        throw 'Remote SI proposal head changed before provider merge.'
    }
    if ((Get-SiCompletionRemoteHead -Root $root -Branch 'main') -ne $pinnedMain) {
        throw 'Remote main changed before provider merge.'
    }
    try {
        $merge = Invoke-SiExpectedHeadMerge -PullRequest $pullRequest `
            -ExpectedHeadOid $validatedHead
    }
    catch {
        $reconciled = Get-SiPullRequest -Owner $parts[0] -Name $parts[1] `
            -Number $PullRequestNumber
        if (-not [bool]$reconciled.merged -or
            [string]$reconciled.state -ne 'MERGED' -or
            [string]$reconciled.baseRefName -ne 'main' -or
            [string]$reconciled.headRefName -ne $branch -or
            [string]$reconciled.headRefOid -ne $validatedHead -or
            [string]$reconciled.headRepository.nameWithOwner -ne $repositoryName -or
            [string]::IsNullOrWhiteSpace([string]$reconciled.mergedAt)) {
            throw
        }
        $pullRequest = $reconciled
        $merge = $reconciled
    }
}
catch {
    $operationError = $_
}
finally {
    if (Test-Path -LiteralPath $worktree) {
        $cleanup = Invoke-SiCompletionGit -Root $root -Argument @(
            'worktree', 'remove', '--force', $worktree
        ) -AllowFailure
        if ($cleanup.ExitCode -ne 0 -or (Test-Path -LiteralPath $worktree)) {
            $cleanupError = "Disposable SI completion worktree cleanup failed for '$worktree'."
        }
    }
}
if ($cleanupError) {
    if ($operationError) {
        throw "$($operationError.Exception.Message) $cleanupError"
    }
    throw $cleanupError
}
if ($operationError) { throw $operationError }

return [pscustomobject][ordered]@{
    Status = 'complete'
    PullRequestNumber = $PullRequestNumber
    PullRequestUrl = [string]$pullRequest.url
    BranchName = $branch
    PinnedMainOid = $pinnedMain
    ExpectedHeadOid = $validatedHead
    StateCommitted = $stateCommitted
    MergedAt = [string]$merge.mergedAt
}
