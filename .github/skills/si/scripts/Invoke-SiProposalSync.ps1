#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [ValidateSet('Sync', 'ValidatePaths')][string]$Operation = 'Sync',
    [string[]]$Path,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$DueId,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$RunId,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$Receipt,
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')][string]$LifecycleHeadOid,
    [ValidatePattern('^(?:absent|[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$ExpectedRemoteHead = 'absent'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TrustAnchorExact = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($entry in @(
        'plugins/self-improvement/plugin.json',
        'plugins/self-improvement/skills/si/SKILL.md',
        'plugins/self-improvement/skills/si/assets/harvest-guide.md',
        'plugins/self-improvement/skills/si/assets/propose-guide.md',
        'plugins/self-improvement/prompts/si.prompt.md',
        '.github/skills/si/SKILL.md',
        '.github/skills/si/assets/harvest-guide.md',
        '.github/skills/si/assets/propose-guide.md',
        '.github/prompts/si.prompt.md',
        'scripts/skalary/Test-SiWriteScope.ps1'
    )) {
    [void]$script:TrustAnchorExact.Add($entry)
}
$script:TrustAnchorPrefix = @(
    'plugins/self-improvement/scripts/',
    'plugins/self-improvement/schemas/',
    'plugins/self-improvement/skills/si/scripts/',
    'plugins/self-improvement/skills/si/schemas/',
    '.github/skills/si/scripts/',
    '.github/skills/si/schemas/'
)

function Test-SiTrustAnchorPath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    if ($script:TrustAnchorExact.Contains($normalized)) { return $true }
    foreach ($prefix in $script:TrustAnchorPrefix) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.Equals(
                $prefix.TrimEnd('/'),
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            return $true
        }
    }
    return $false
}

if ($Operation -eq 'ValidatePaths') {
    return @($Path | ForEach-Object {
            [pscustomobject][ordered]@{
                Path = $_
                Denied = Test-SiTrustAnchorPath -RelativePath $_
            }
        })
}

foreach ($required in @('DueId', 'RunId', 'Receipt', 'LifecycleHeadOid')) {
    if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $required -ValueOnly))) {
        throw "Sync requires -$required."
    }
}

function Invoke-SiProposalGit {
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

function Get-SiProposalOid {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Ref
    )

    $result = Invoke-SiProposalGit -Root $Root -Argument @(
        'rev-parse', '--verify', "$Ref^{commit}"
    )
    $oid = ([string]($result.Output | Select-Object -First 1)).Trim()
    if ($oid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw "Git ref '$Ref' did not resolve to a valid commit OID."
    }
    return $oid
}

function Get-SiRemoteHead {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Branch
    )

    $result = Invoke-SiProposalGit -Root $Root -Argument @(
        'ls-remote', '--heads', 'origin', "refs/heads/$Branch"
    )
    $lines = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) { return 'absent' }
    if ($lines.Count -ne 1 -or
        [string]$lines[0] -notmatch
        '^(?<oid>[0-9a-f]{40}|[0-9a-f]{64})\s+refs/heads/.+$') {
        throw "Remote branch '$Branch' returned an invalid head record."
    }
    return $Matches.oid
}

function Invoke-SiProposalProvider {
    param([Parameter(Mandatory)][string[]]$Argument)

    $output = @(& gh @Argument 2>&1)
    $code = $LASTEXITCODE
    $text = ($output -join "`n").Trim()
    $response = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        try {
            $response = $text | ConvertFrom-Json -Depth 100
        }
        catch {
            if ($code -eq 0) {
                throw 'GitHub ref transaction returned malformed JSON.'
            }
        }
    }
    $errors = @()
    if ($null -ne $response -and
        $response.PSObject.Properties.Name -contains 'errors') {
        $errors = @($response.errors | ForEach-Object { [string]$_.message })
    }
    if ($code -ne 0 -or $errors.Count -gt 0) {
        $detail = if ($errors.Count -gt 0) { $errors -join '; ' } else { $text }
        if ($detail.Length -gt 1024) { $detail = $detail.Substring(0, 1024) }
        throw "GitHub ref transaction failed: $detail"
    }
    if ($null -eq $response) {
        throw 'GitHub ref transaction returned no response.'
    }
    return $response
}

function Get-SiProposalRepositoryId {
    param([Parameter(Mandatory)][string]$Root)

    $remoteResult = Invoke-SiProposalGit -Root $Root -Argument @(
        'remote', 'get-url', 'origin'
    )
    $remote = ([string]($remoteResult.Output | Select-Object -First 1)).Trim()
    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw 'Git origin URL is absent.'
    }
    $result = @(& gh repo view $remote --json id --jq .id 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to resolve the GitHub repository identity.'
    }
    $repositoryId = ([string]($result | Select-Object -First 1)).Trim()
    if ([string]::IsNullOrWhiteSpace($repositoryId) -or $repositoryId.Length -gt 256) {
        throw 'GitHub repository identity is invalid.'
    }
    return $repositoryId
}

function Set-SiRemoteHeadCas {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ExpectedOid,
        [Parameter(Mandatory)][string]$NewOid,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $repositoryId = Get-SiProposalRepositoryId -Root $Root
    $refName = "refs/heads/$Branch"
    $stagingBranch = "si-staging/$CorrelationId/$([Guid]::NewGuid().ToString('N'))"
    $stagingAttempted = $false
    $operationError = $null
    $cleanupError = $null
    try {
        $stagingAttempted = $true
        [void](Invoke-SiProposalGit -Root $Root -Argument @(
                'push', '--quiet', 'origin',
                "$NewOid`:refs/heads/$stagingBranch"
            ))

        if ($ExpectedOid -eq 'absent') {
            $mutation = @'
mutation($repositoryId:ID!,$name:String!,$afterOid:GitObjectID!){
  createRef(input:{repositoryId:$repositoryId,name:$name,oid:$afterOid}){
    ref{name target{... on Commit{oid}}}
  }
}
'@
            $response = Invoke-SiProposalProvider -Argument @(
                'api', 'graphql', '-f', "query=$mutation",
                '-f', "repositoryId=$repositoryId", '-f', "name=$refName",
                '-f', "afterOid=$NewOid"
            )
            if ([string]$response.data.createRef.ref.name -ne $refName -or
                [string]$response.data.createRef.ref.target.oid -ne $NewOid) {
                throw 'GitHub createRef did not return the validated proposal ref.'
            }
        }
        else {
            $mutation = @'
mutation($repositoryId:ID!,$name:GitRefname!,$beforeOid:GitObjectID!,$afterOid:GitObjectID!){
  updateRefs(input:{repositoryId:$repositoryId,refUpdates:[{
    name:$name,beforeOid:$beforeOid,afterOid:$afterOid,force:false
  }]}){
    clientMutationId
  }
}
'@
            [void](Invoke-SiProposalProvider -Argument @(
                    'api', 'graphql', '-f', "query=$mutation",
                    '-f', "repositoryId=$repositoryId", '-f', "name=$refName",
                    '-f', "beforeOid=$ExpectedOid", '-f', "afterOid=$NewOid"
                ))
        }
        $confirmed = Get-SiRemoteHead -Root $Root -Branch $Branch
        if ($confirmed -ne $NewOid) {
            throw "Remote proposal head '$confirmed' does not equal validated OID '$NewOid'."
        }
    }
    catch {
        $operationError = $_
    }
    finally {
        if ($stagingAttempted) {
            try {
                $stagingHead = Get-SiRemoteHead -Root $Root -Branch $stagingBranch
                if ($stagingHead -ne 'absent') {
                    $cleanup = Invoke-SiProposalGit -Root $Root -Argument @(
                        'push', '--quiet', 'origin', '--delete', $stagingBranch
                    ) -AllowFailure
                    $remaining = Get-SiRemoteHead -Root $Root -Branch $stagingBranch
                    if ($cleanup.ExitCode -ne 0 -or $remaining -ne 'absent') {
                        $cleanupError =
                            "Remote SI staging ref '$stagingBranch' cleanup failed."
                    }
                }
            }
            catch {
                $cleanupError =
                    "Remote SI staging ref '$stagingBranch' cleanup failed: " +
                    $_.Exception.Message
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
    return $NewOid
}

function Get-SiDiffPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Range,
        [string]$Pathspec
    )

    $arguments = @('diff', '--name-only', '--no-renames', '-z', $Range)
    if ($Pathspec) { $arguments += @('--', $Pathspec) }
    $result = Invoke-SiProposalGit -Root $Root -Argument $arguments
    $text = $result.Output -join "`n"
    return @($text.Split([char]0, [char]10) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Read-SiProposalRun {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ExpectedRunId
    )

    $contract = Get-SiStateContract
    $runsRoot = Resolve-SiStatePath -RepoRoot $Root `
        -Segments @($contract.Topology.ActiveRunsSegments)
    $matches = @(Get-ChildItem -LiteralPath $runsRoot -Filter "$ExpectedRunId.json" `
            -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 2)
    if ($matches.Count -ne 1) {
        throw "Proposal requires exactly one active run '$ExpectedRunId'."
    }
    if ($matches[0].Length -gt (Get-SiStateContract).Limits.RunBytes) {
        throw "Proposal run '$ExpectedRunId' exceeds its byte limit."
    }
    try {
        $json = [System.Text.UTF8Encoding]::new($false, $true).GetString(
            [System.IO.File]::ReadAllBytes($matches[0].FullName)
        )
        $run = $json | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Proposal run '$ExpectedRunId' is not valid UTF-8 JSON."
    }
    $schemaPath = [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '../schemas/run.schema.json')
    )
    if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
        throw "Proposal run '$ExpectedRunId' failed closed-schema validation."
    }
    Assert-SiRunIntegrity -Run $run
    if ([string]$run.runId -ne $ExpectedRunId -or
        [string]$run.dueId -ne $DueId -or
        [string]$run.provenance.resolverReceiptId -ne $Receipt -or
        -not (Test-SiRunStatus -Status ([string]$run.status) -Set ProposalAdmitted)) {
        throw "Proposal run '$ExpectedRunId' is not an admitted lifecycle outcome."
    }
    return [pscustomobject]@{ Value = $run; Path = $matches[0].FullName }
}

function Invoke-TrustedScopeGuard {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseRef
    )

    $guard = Join-Path $PSScriptRoot 'Test-SiWriteScope.ps1'
    if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) {
        $guard = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '../skills/si/scripts/Test-SiWriteScope.ps1')
        )
    }
    if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) {
        throw 'Trusted SI write-scope guard is unavailable.'
    }
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

$root = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Repository root not found: $root"
}
$trustedScript = [System.IO.Path]::GetFullPath($PSCommandPath)
$rootPrefix = $root.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )) + [System.IO.Path]::DirectorySeparatorChar
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
if ($trustedScript.StartsWith($rootPrefix, $comparison)) {
    throw 'Invoke-SiProposalSync must run from a trusted checkout outside the proposal worktree.'
}

$branch = "si/$DueId"
$currentBranch = (Invoke-SiProposalGit -Root $root -Argument @(
        'symbolic-ref', '--quiet', '--short', 'HEAD'
    )).Output | Select-Object -First 1
if ([string]$currentBranch -ne $branch) {
    throw "Proposal worktree must have fixed branch '$branch' checked out."
}
$status = (Invoke-SiProposalGit -Root $root -Argument @(
        'status', '--porcelain=v1', '--untracked-files=all'
    )).Output
if (@($status).Count -gt 0) {
    throw 'Proposal worktree must be clean before trusted synchronization.'
}

[void](Invoke-SiProposalGit -Root $root -Argument @(
        'fetch', '--quiet', '--no-tags', 'origin',
        '+refs/heads/main:refs/remotes/origin/main'
    ))
$pinnedMain = Get-SiProposalOid -Root $root -Ref 'refs/remotes/origin/main'
$headBeforeMerge = Get-SiProposalOid -Root $root -Ref 'HEAD'
[void](Invoke-SiProposalGit -Root $root -Argument @(
        'merge-base', '--is-ancestor', $LifecycleHeadOid, $headBeforeMerge
    ))

$trustedRoot = [string](
    (Invoke-SiProposalGit -Root (Split-Path -Parent $trustedScript) -Argument @(
            'rev-parse', '--show-toplevel'
        )).Output | Select-Object -First 1
)
$trustedRoot = [System.IO.Path]::GetFullPath($trustedRoot.Trim())
$trustedRelative = [System.IO.Path]::GetRelativePath(
    $trustedRoot, $trustedScript
).Replace('\', '/')
if ($trustedRelative -ne '.github/skills/si/scripts/Invoke-SiProposalSync.ps1' -or
    (Get-SiProposalOid -Root $trustedRoot -Ref 'HEAD') -ne $pinnedMain) {
    throw 'Trusted SI checkout is not pinned to the fetched origin/main OID.'
}
$trustedStatus = (Invoke-SiProposalGit -Root $trustedRoot -Argument @(
        'status', '--porcelain=v1', '--untracked-files=all'
    )).Output
if (@($trustedStatus).Count -gt 0) {
    throw 'Trusted SI checkout must be clean.'
}
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force
$stateContract = Get-SiStateContract
$stateRootRelative = Get-SiStateRelativePath -Kind Root

$remoteHead = Get-SiRemoteHead -Root $root -Branch $branch
if ($remoteHead -ne $ExpectedRemoteHead) {
    throw "Remote head is stale: expected '$ExpectedRemoteHead', found '$remoteHead'."
}
if ($remoteHead -ne 'absent') {
    $remoteAncestor = Invoke-SiProposalGit -Root $root -Argument @(
        'merge-base', '--is-ancestor', $remoteHead, $headBeforeMerge
    ) -AllowFailure
    if ($remoteAncestor.ExitCode -ne 0) {
        throw "Local proposal does not descend from expected remote head '$remoteHead'."
    }
}

$stateEdits = @(Get-SiDiffPath -Root $root -Range "$LifecycleHeadOid..HEAD" `
        -Pathspec $stateRootRelative)
if ($stateEdits.Count -gt 0) {
    throw "Proposal hand-edited lifecycle state after '$LifecycleHeadOid'."
}
$proposalPaths = @(Get-SiDiffPath -Root $root -Range "$pinnedMain...HEAD")
$denied = @($proposalPaths | Where-Object { Test-SiTrustAnchorPath -RelativePath $_ })
if ($denied.Count -gt 0) {
    throw "Proposal touches protected SI trust anchor '$($denied[0])'."
}

$verifiedReceipt = & (Join-Path $PSScriptRoot 'Test-SiResolverReceipt.ps1') `
    -RepoRoot $root -Receipt $Receipt
$runRecord = Read-SiProposalRun -Root $root -ExpectedRunId $RunId
$run = $runRecord.Value
if ([string]$verifiedReceipt.Payload.dueId -ne $DueId -or
    [string]$verifiedReceipt.Payload.runId -ne $RunId -or
    [string]$verifiedReceipt.Payload.pinnedBaseOid -ne
    [string]$run.provenance.pinnedBaseOid) {
    throw 'Proposal receipt, run, and lifecycle identity do not match.'
}
$candidateIds = @($run.rankedSet.candidates | ForEach-Object { [string]$_.candidateId })
if (($candidateIds -join ',') -ne
    (@($verifiedReceipt.Payload.candidates) -join ',') -or
    [string]$run.rankedSet.digest -ne
    [string]$verifiedReceipt.Payload.rankedSetDigest) {
    throw 'Proposal run does not exactly match its resolver receipt.'
}
$manifestRelative = Get-SiStateRelativePath -Kind Manifest
$runRelative = [System.IO.Path]::GetRelativePath($root, $runRecord.Path).Replace('\', '/')
$receiptRelative = [System.IO.Path]::GetRelativePath(
    $root, [string]$verifiedReceipt.Path
).Replace('\', '/')
$allowedLifecyclePaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($allowedPath in @(
        $manifestRelative,
        $runRelative,
        $receiptRelative,
        (Get-SiStateRelativePath -Kind HarvestIndex)
    )) {
    [void]$allowedLifecyclePaths.Add($allowedPath)
}
$lifecyclePaths = @(
    Get-SiDiffPath -Root $root `
        -Range "$pinnedMain...$LifecycleHeadOid"
)
$invalidLifecyclePaths = @($lifecyclePaths | Where-Object {
        -not $allowedLifecyclePaths.Contains($_)
    })
if ($invalidLifecyclePaths.Count -gt 0) {
    throw "Lifecycle head contains unadmitted state edit '$($invalidLifecyclePaths[0])'."
}
$receiptJson = [System.IO.File]::ReadAllText([string]$verifiedReceipt.Path)

$syncRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'si-proposal-sync-' + [Guid]::NewGuid().ToString('N')
)
$confirmed = $null
$validatedOid = $null
$operationError = $null
$cleanupError = $null
try {
    [void](Invoke-SiProposalGit -Root $root -Argument @(
            'worktree', 'add', '--quiet', '--detach', $syncRoot, $headBeforeMerge
        ))
    $merge = Invoke-SiProposalGit -Root $syncRoot -Argument @(
        'merge', '--no-commit', '--no-ff', $pinnedMain
    ) -AllowFailure
    if ($merge.ExitCode -ne 0) {
        throw 'Current origin/main could not be merged cleanly into the proposal.'
    }

    [void](Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'rm', '-r', '--quiet', '--ignore-unmatch', '--', $stateRootRelative
        ))
    [void](Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'checkout', $pinnedMain, '--', $stateRootRelative
        ))
    $receiptPath = Resolve-SiStatePath -RepoRoot $syncRoot -Segments @(
        @($stateContract.Topology.ResolverReceiptSegments) + "$Receipt.json"
    )
    Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') `
        -Force -Prefix SiProposal
    $receiptWrite = Set-SiProposalAtomicStoreContent `
        -Path $receiptPath -Content $receiptJson
    if ($receiptWrite.Status -ne 'complete') {
        throw "Resolver receipt rebuild failed with status '$($receiptWrite.Status)'."
    }
    $writtenPath = Write-SiRun -RepoRoot $syncRoot -Run $run
    $rebase = Invoke-SiManifestUpdate -RepoRoot $syncRoot -Transform {
        param($manifest)

        $active = @(
            @($manifest.pending) + @($manifest.inFlight) |
                Where-Object { [string]$_.dueId -eq $DueId }
        )
        if ($active.Count -ne 1) {
            throw "Current origin/main does not contain exactly one active due '$DueId'."
        }
        $due = $active[0]
        if ([string]$due.status -eq 'in-flight' -and [string]$due.runId -ne $RunId) {
            throw "Current origin/main binds due '$DueId' to a different run."
        }
        $manifest.pending = @($manifest.pending |
                Where-Object { [string]$_.dueId -ne $DueId })
        $manifest.inFlight = @($manifest.inFlight |
                Where-Object { [string]$_.dueId -ne $DueId })
        if ([string]$run.status -eq 'no-candidates') {
            $relative = [System.IO.Path]::GetRelativePath(
                $syncRoot, $writtenPath
            ).Replace('\', '/')
            $reference = [pscustomobject][ordered]@{
                runId = $RunId
                dueId = $DueId
                status = 'no-candidates'
                path = $relative
                completedAtUtc = [string]$run.completedAtUtc
            }
            $manifest.recentRuns = @($reference) + @(
                $manifest.recentRuns |
                    Where-Object { [string]$_.dueId -ne $DueId } |
                    Select-Object -First (
                        $stateContract.Limits.RecentRunReferences - 1
                    )
            )
        }
        else {
            if (@($manifest.inFlight).Count -ge
                (Get-SiStateContract).Limits.ActiveInFlightRuns) {
                throw 'capacity-blocked: active in-flight run limit reached.'
            }
            $due.status = 'in-flight'
            $due.runId = $RunId
            $manifest.inFlight = @($manifest.inFlight) + $due
        }
        return [pscustomobject]@{ RunPath = $writtenPath }
    }
    if ($rebase.Status -ne 'complete') {
        throw "Proposal state re-derivation failed with status '$($rebase.Status)'."
    }

    [void](Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'add', '--', $stateRootRelative
        ))
    $staged = (Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'diff', '--cached', '--name-only'
        )).Output
    if (@($staged).Count -eq 0) {
        throw 'Trusted synchronization produced no commit to validate.'
    }
    [void](Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'commit', '--quiet', '-m',
            "chore(self-improvement): synchronize SI proposal $DueId"
        ))

    $validatedOid = Get-SiProposalOid -Root $syncRoot -Ref 'HEAD'
    $postPaths = @(
        Get-SiDiffPath -Root $syncRoot -Range "$pinnedMain...HEAD"
    )
    $postDenied = @($postPaths | Where-Object {
            Test-SiTrustAnchorPath -RelativePath $_
        })
    if ($postDenied.Count -gt 0) {
        throw "Synchronized proposal touches protected SI trust anchor '$($postDenied[0])'."
    }
    $stateDelta = @(Get-SiDiffPath -Root $syncRoot `
            -Range "$pinnedMain...HEAD" -Pathspec $stateRootRelative)
    $expectedStateDelta = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($expectedPath in @($manifestRelative, $runRelative, $receiptRelative)) {
        [void]$expectedStateDelta.Add($expectedPath)
    }
    $unexpectedState = @($stateDelta | Where-Object {
            -not $expectedStateDelta.Contains($_)
        })
    if ($unexpectedState.Count -gt 0) {
        throw "Synchronized proposal retained unadmitted state '$($unexpectedState[0])'."
    }
    Invoke-TrustedScopeGuard -Root $syncRoot -BaseRef $pinnedMain
    if ((Get-SiProposalOid -Root $syncRoot -Ref 'HEAD') -ne $validatedOid) {
        throw 'Proposal HEAD changed during trusted validation.'
    }
    $syncStatus = (Invoke-SiProposalGit -Root $syncRoot -Argument @(
            'status', '--porcelain=v1', '--untracked-files=all'
        )).Output
    if (@($syncStatus).Count -gt 0) {
        throw 'Proposal worktree changed during trusted validation.'
    }
    $confirmed = Set-SiRemoteHeadCas -Root $syncRoot -Branch $branch `
        -ExpectedOid $ExpectedRemoteHead -NewOid $validatedOid `
        -CorrelationId $DueId
}
catch {
    $operationError = $_
}
finally {
    if (Test-Path -LiteralPath $syncRoot) {
        $cleanup = Invoke-SiProposalGit -Root $root -Argument @(
                'worktree', 'remove', '--force', $syncRoot
            ) -AllowFailure
        if ($cleanup.ExitCode -ne 0 -or (Test-Path -LiteralPath $syncRoot)) {
            $cleanupError = "Disposable SI worktree cleanup failed for '$syncRoot'."
        }
    }
}
if ($cleanupError) {
    if ($operationError) {
        throw "$($operationError.Exception.Message) $cleanupError"
    }
    throw $cleanupError
}
if ($operationError) {
    throw $operationError
}

return [pscustomobject][ordered]@{
    Status = 'complete'
    DueId = $DueId
    RunId = $RunId
    BranchName = $branch
    PinnedMainOid = $pinnedMain
    ValidatedHeadOid = $validatedOid
    RemoteHeadOid = $confirmed
}
