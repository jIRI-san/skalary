#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][string]$PlanReference,
    [Parameter(Mandatory)]
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$PinnedBaseOid,
    [switch]$IssueReceipt,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$DueId,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$RunId,
    [string]$CandidateJson = '[]'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SiResolverReceipt.psm1') -Force

$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$root = (Resolve-Path -LiteralPath ([System.IO.Path]::GetFullPath($RepoRoot))).Path
$relativePath = 'docs/feedback/recent-learning.md'
$learningPath = Join-Path $root ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$inventory = @(Get-PlanInventory -RepoRoot $root)
$plan = Resolve-Plan -Reference $PlanReference -RepoRoot $root -Inventory $inventory
$planId = [string]$plan.Id
$planPath = [System.IO.Path]::GetRelativePath($root, [string]$plan.Path).Replace('\', '/')

function Get-ContentDigest {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function New-UntrustedLearningBlock {
    param([Parameter(Mandatory)][string]$Text)
    do {
        $token = 'UNTRUSTED_INPUT_' + [guid]::NewGuid().ToString('N')
    } while ($Text.Contains($token, [System.StringComparison]::Ordinal))
    "<$token>`n$Text`n</$token>"
}

function Invoke-GitText {
    param([Parameter(Mandatory)][string[]]$Argument)
    $output = @(& git -C $root @Argument 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
}

$object = Invoke-GitText -Argument @('cat-file', '-e', "${PinnedBaseOid}:${relativePath}")
if ($object.ExitCode -ne 0) {
    $status = if (Test-Path -LiteralPath $learningPath -PathType Leaf) { 'stale' } else { 'missing' }
    return [pscustomobject][ordered]@{
        Status = $status
        PlanId = $planId
        PinnedBaseOid = $PinnedBaseOid
        Items = @()
        ResolverReceipt = $null
    }
}

$size = Invoke-GitText -Argument @('cat-file', '-s', "${PinnedBaseOid}:${relativePath}")
$byteCount = 0L
if ($size.ExitCode -ne 0 -or
    -not [long]::TryParse($size.Text.Trim(), [ref]$byteCount) -or
    $byteCount -gt 16KB) {
    throw 'Recent-learning input exceeds 16 KiB or has unreadable Git metadata.'
}
$blob = Invoke-GitText -Argument @('show', "${PinnedBaseOid}:${relativePath}")
if ($blob.ExitCode -ne 0) {
    throw 'Unable to read recent-learning input from the pinned commit.'
}
$content = $utf8.GetString([System.Text.Encoding]::UTF8.GetBytes($blob.Text))
$sourcePlan = [regex]::Match($content, '(?im)^\s*Source plan:\s*`?(?<id>[0-9a-f]{6})`?\s*$')
$sourceCommit = [regex]::Match(
    $content,
    '(?im)^\s*Source commit:\s*`?(?<oid>[0-9a-f]{40}|[0-9a-f]{64})`?\s*$'
)
$items = [regex]::Match($content, '(?ims)^##\s+Items\s*$\s*(?<body>.*)$')
$stale = -not $sourcePlan.Success -or $sourcePlan.Groups['id'].Value -cne $planId -or
    -not $sourceCommit.Success -or -not $items.Success
if (-not $stale) {
    & git -C $root merge-base --is-ancestor $sourceCommit.Groups['oid'].Value $PinnedBaseOid 2>$null
    $stale = $LASTEXITCODE -ne 0
}
if ($stale) {
    return [pscustomobject][ordered]@{
        Status = 'stale'
        PlanId = $planId
        PinnedBaseOid = $PinnedBaseOid
        Items = @()
        ResolverReceipt = $null
    }
}

$body = $items.Groups['body'].Value.Trim()
$explicitEmpty = [string]::IsNullOrWhiteSpace($body) -or $body -match '^(?i:none\.?|no items\.?)$'
$sourceDigest = Get-ContentDigest -Text $content
$selectedDigest = Get-ContentDigest -Text $(if ($explicitEmpty) { '' } else { $body })
$selectedRecords = @(
    if (-not $explicitEmpty) {
        [pscustomobject][ordered]@{
            id = $sourceDigest
            source = $relativePath
            content = $content
        }
    }
)
$sourceRows = @(
    [pscustomobject][ordered]@{
        path = $relativePath
        sha256 = $sourceDigest
        bytes = $byteCount
    }
)
$index = [pscustomobject][ordered]@{
    schemaVersion = 1
    protocol = 'si-harvest-index-v1'
    planId = $planId
    planPath = $planPath
    pinnedBaseOid = $PinnedBaseOid
    snapshotDigest = $sourceDigest
    selectedDigest = $selectedDigest
    fileCount = 1
    scannedByteCount = $byteCount
    sourceCount = 1
    recordCount = $selectedRecords.Count
    selectedByteCount = if ($explicitEmpty) { 0 } else { $utf8.GetByteCount($body) }
    sources = $sourceRows
    selectedRecords = $selectedRecords
}
$stateContract = Get-SiStateContract
$indexPath = Resolve-SiStatePath -RepoRoot $root -Segments @(
    [string]$stateContract.Topology.HarvestIndexName
)
$indexJson = ($index | ConvertTo-Json -Depth 20 -Compress) + "`n"
$indexWrite = Invoke-AtomicStoreUpdate -Path $indexPath -Transform { $indexJson }
if ($indexWrite.Status -ne 'complete') {
    throw "SI recent-learning index write failed with status '$($indexWrite.Status)'."
}

$issuedReceipt = $null
if ($IssueReceipt) {
    if (-not $DueId -or -not $RunId) {
        throw 'Resolver receipt issuance requires -DueId and -RunId.'
    }
    if ($utf8.GetByteCount($CandidateJson) -gt 1MB) {
        throw 'Resolver candidate JSON exceeds 1 MiB.'
    }
    try {
        $candidateInput = @($CandidateJson | ConvertFrom-Json -Depth 20)
    }
    catch {
        throw "Resolver candidate JSON is malformed: $($_.Exception.Message)"
    }
    $ranked = New-SiRankedCandidates -Candidate $candidateInput
    $payload = [pscustomobject][ordered]@{
        protocol = 'si-resolver-receipt-v1'
        dueId = $DueId
        runId = $RunId
        pinnedBaseOid = $PinnedBaseOid
        snapshotDigest = $sourceDigest
        selectedDigest = $selectedDigest
        rankedSetDigest = $ranked.RankedSetDigest
        candidates = $ranked.CandidateIds
    }
    $receiptId = Get-SiResolverReceiptId -Payload $payload
    $receipt = [pscustomobject][ordered]@{ receiptId = $receiptId; payload = $payload }
    $receiptJson = ($receipt | ConvertTo-Json -Depth 20 -Compress) + "`n"
    $receiptPath = Resolve-SiStatePath -RepoRoot $root -Segments (
        @($stateContract.Topology.ResolverReceiptSegments) + "$receiptId.json"
    )
    $write = Invoke-AtomicStoreUpdate -Path $receiptPath -Transform { $receiptJson }
    if ($write.Status -ne 'complete') {
        throw "Resolver receipt write failed with status '$($write.Status)'."
    }
    $issuedReceipt = [pscustomobject]@{
        ReceiptId = $receiptId
        Path = $receiptPath
        RankedSetDigest = $ranked.RankedSetDigest
        Candidates = $ranked.Candidates
    }
}

return [pscustomobject][ordered]@{
    Status = if ($explicitEmpty) { 'empty' } else { 'valid' }
    PlanId = $planId
    PinnedBaseOid = $PinnedBaseOid
    SnapshotDigest = $sourceDigest
    SelectedDigest = $selectedDigest
    FileCount = 1
    ScannedByteCount = $byteCount
    SourceCount = 1
    RecordCount = $selectedRecords.Count
    SelectedCount = $selectedRecords.Count
    SelectedByteCount = $index.selectedByteCount
    InjectionCount = 0
    IndexPath = $indexPath
    ResolverReceipt = $issuedReceipt
    Items = @(
        if (-not $explicitEmpty) {
            [pscustomobject][ordered]@{
                id = $sourceDigest
                source = $relativePath
                wrappedContent = New-UntrustedLearningBlock -Text $content
            }
        }
    )
    NextCursor = $null
}
