#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The arch: marker recomputes the canonical sources hash, reads the receipt, and maps the taxonomy verdict
# through the same gate matrix the runner uses — all from a shared module so producer and verifier never drift.
Import-Module (Join-Path $PSScriptRoot 'ArchReceipt.psm1') -Force -DisableNameChecking

function Resolve-PlanEvidencePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Evidence path is empty.'
    }

    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        throw "Evidence path '$RelativePath' must be relative."
    }

    if ($RelativePath -match '^[A-Za-z]:') {
        throw "Evidence path '$RelativePath' cannot be absolute."
    }

    if ($RelativePath -match '\\\\') {
        throw "Evidence path '$RelativePath' cannot be UNC."
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $repoRootFullPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFullPath ($RelativePath -replace '/', $separator)))
    $repoRootPrefix = $repoRootFullPath.TrimEnd($separator) + $separator
    if (-not $candidatePath.StartsWith($repoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Evidence path '$RelativePath' resolves outside repository root."
    }

    if (Test-Path -LiteralPath $candidatePath) {
        $resolved = (Resolve-Path -LiteralPath $candidatePath -Force).Path
        if (-not $resolved.StartsWith($repoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Evidence path '$RelativePath' escapes repository root via symlink."
        }
        return $resolved
    }

    return $candidatePath
}

function Parse-PlanFileEvidenceMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Marker
    )

    if ($Marker -notmatch '^file:(?<path>[^#]+)#(?<assertion>.+)$') {
        throw "Invalid file evidence marker '$Marker'. Expected file:<path>#<assertion>."
    }

    $relativePath = $Matches.path.Trim()
    $assertion = $Matches.assertion.Trim()
    if ($assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'exists'
            Threshold = $null
            Regex = $null
        }
    }

    if ($assertion -like 'contains:*') {
        $pattern = $assertion.Substring('contains:'.Length)
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid contains assertion in '$Marker'."
        }
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'contains'
            Threshold = $null
            Regex = $pattern
        }
    }

    if ($assertion -match '^count>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'count'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    if ($assertion -match '^dircount>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'dircount'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    throw "Invalid file evidence assertion '$assertion' in '$Marker'. Allowed: exists, contains:, count>=N, dircount>=N."
}

function Get-PathWithinRootPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    return [System.IO.Path]::GetFullPath($Root).TrimEnd($separator) + $separator
}

function Get-FileRegexMatchCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [int]$PerMatchTimeoutMs = 100,

        [int]$PerFileBudgetMs = 750
    )

    $content = Get-Content -LiteralPath $Path -Raw -Force
    $remaining = [TimeSpan]::FromMilliseconds($PerFileBudgetMs)
    $start = [DateTimeOffset]::UtcNow
    $matchCount = 0
    $offset = 0
    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::None,
        [TimeSpan]::FromMilliseconds($PerMatchTimeoutMs)
    )
    while ($offset -le $content.Length) {
        if ($remaining.TotalMilliseconds -le 0) {
            throw "Regex budget exhausted while scanning '$Path'."
        }

        $match = $regex.Match($content, $offset)
        if (-not $match.Success) {
            break
        }

        $matchCount++
        $offset = if ($match.Length -gt 0) { $match.Index + $match.Length } else { $match.Index + 1 }
        $elapsed = [DateTimeOffset]::UtcNow - $start
        $remaining = [TimeSpan]::FromMilliseconds($PerFileBudgetMs) - $elapsed
    }

    return $matchCount
}

function Invoke-PlanFileEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Marker,

        [ValidateSet('Draft', 'PhaseCrosscheck', 'PlanCrosscheck')]
        [string]$Stage = 'Draft',

        [long]$MaxFileBytes = 1048576,

        [int]$PerMatchTimeoutMs = 100,

        [int]$PerFileRegexBudgetMs = 750
    )

    $parsed = Parse-PlanFileEvidenceMarker -Marker $Marker
    $resolvedPath = Resolve-PlanEvidencePath -RepoRoot $RepoRoot -RelativePath $parsed.RelativePath
    $isBlockingStage = $Stage -ne 'Draft'
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Missing target '$($parsed.RelativePath)'."
        }
    }

    if ($parsed.Assertion -eq 'dircount') {
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
            return [pscustomobject]@{
                Marker = $Marker
                Success = $false
                Blocking = $isBlockingStage
                Message = "Target '$($parsed.RelativePath)' is not a directory."
            }
        }

        $rootPrefix = Get-PathWithinRootPrefix -Root $RepoRoot
        $seenDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($resolvedPath)
        $count = 0
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $items = Get-ChildItem -LiteralPath $current -Force
            foreach ($item in $items) {
                if ($item.LinkType) {
                    continue
                }

                if ($item.PSIsContainer) {
                    $childPath = [System.IO.Path]::GetFullPath($item.FullName)
                    if (-not $childPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Directory walk escaped repository root through '$childPath'."
                    }
                    if ($seenDirectories.Add($childPath)) {
                        $queue.Enqueue($childPath)
                        $count++
                    }
                    continue
                }

                $count++
            }
        }

        return [pscustomobject]@{
            Marker = $Marker
            Success = $count -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "Counted $count item(s), required >= $($parsed.Threshold)."
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Target '$($parsed.RelativePath)' is not a file."
        }
    }

    $length = (Get-Item -LiteralPath $resolvedPath -Force).Length
    if ($length -gt $MaxFileBytes) {
        throw "File '$($parsed.RelativePath)' exceeds max size (${MaxFileBytes} bytes)."
    }

    if ($parsed.Assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $true
            Blocking = $isBlockingStage
            Message = "File '$($parsed.RelativePath)' exists."
        }
    }

    if ($parsed.Assertion -eq 'count') {
        $lineCount = @((Get-Content -LiteralPath $resolvedPath -Force)).Count
        return [pscustomobject]@{
            Marker = $Marker
            Success = $lineCount -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "File has $lineCount line(s), required >= $($parsed.Threshold)."
        }
    }

    $matchCount = Get-FileRegexMatchCount -Path $resolvedPath -Pattern $parsed.Regex -PerMatchTimeoutMs $PerMatchTimeoutMs -PerFileBudgetMs $PerFileRegexBudgetMs
    return [pscustomobject]@{
        Marker = $Marker
        Success = $matchCount -gt 0
        Blocking = $isBlockingStage
        Message = if ($matchCount -gt 0) { 'Regex matched.' } else { 'Regex did not match.' }
    }
}

function Find-ArchCheckForContract {
    <#
    .SYNOPSIS
    Loads the arch-test config and returns the check binding for a contract id (or $null when absent).

    .DESCRIPTION
    The freshness recompute needs the check's binding (contractPath + targets + adapter/spec/testProject).
    The config is discovered at a convention (repo-root arch-test-config.json, then the arch-notes tier) or
    an explicit path. Pure JSON parse; no execution.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ContractId,
        [string]$ConfigPath
    )

    $candidates = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        @($ConfigPath)
    }
    else {
        @(
            (Join-Path $RepoRoot 'arch-test-config.json'),
            (Join-Path $RepoRoot 'docs/architecture-notes/arch-test-config.json')
        )
    }

    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $config = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json -Depth 20
        if (-not ($config.PSObject.Properties.Name -contains 'checks')) { continue }
        foreach ($check in @($config.checks)) {
            if (($check.PSObject.Properties.Name -contains 'contractId') -and ([string]$check.contractId -eq $ContractId)) {
                $found.Add([pscustomobject]@{ Config = $candidate; Check = $check })
            }
        }
    }

    if ($found.Count -eq 0) { return $null }
    # Deterministic: refuse to guess when more than one config declares the same contract (a root config must
    # not silently shadow the arch-notes one and change which paths/binding are hashed).
    if ($found.Count -gt 1) {
        $where = ($found | ForEach-Object { $_.Config }) -join ', '
        throw "Ambiguous arch-test config for contract '$ContractId': found in multiple configs ($where). Consolidate to one."
    }
    return $found[0].Check
}

function Invoke-PlanArchEvidence {
    <#
    .SYNOPSIS
    Verifies an `arch:<ContractId>` marker by PURE-PARSING its integrity/freshness receipt (no execution).

    .DESCRIPTION
    Never shells a toolchain and never executes plan/contract text. It:
      1. locates the receipt (docs/architecture-notes/receipts/<ContractId>.arch-receipt.json);
      2. reads + schema-validates it (malformed/mismatched => fail loud);
      3. rejects a STALE receipt by recomputing the canonical sources hash (from the committed config binding
         + contract/target sources) and comparing it to the recorded sourcesHash — freshness binds to the
         tree/content hash, not raw HEAD equality, so committing the receipt does not self-invalidate it;
      4. maps the recorded verdict through the shared taxonomy x maturity gate (locked: only a real pass
         greens; fail/error/skip block; draft/provisional warn; semantic-eval advisory-always).
    Returns { Marker; Success; Blocking; Message }. Blocking is honoured only at a crosscheck Stage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Marker,
        [ValidateSet('Draft', 'PhaseCrosscheck', 'PlanCrosscheck')]
        [string]$Stage = 'Draft',
        [string]$ConfigPath,
        [string]$ReceiptDir
    )

    if ($Marker -notmatch '^arch:(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)$') {
        throw "Invalid arch evidence marker '$Marker'. Expected arch:<ContractId>."
    }
    $contractId = $Matches.id
    $isBlockingStage = $Stage -ne 'Draft'
    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)

    $receiptPath = Get-ArchReceiptPath -RepoRoot $repoRootFull -ContractId $contractId -ReceiptDir $ReceiptDir
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "No arch-test receipt for contract '$contractId' (unrun). Run the arch-tests runner in /ci and commit the receipt."
        }
    }

    # Malformed/mismatched receipt fails loud (Read-ArchReceipt throws; convert to a blocking failure).
    try {
        $receipt = Read-ArchReceipt -Path $receiptPath
    }
    catch {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Malformed arch-test receipt for '$contractId': $($_.Exception.Message)"
        }
    }

    if ($receipt.ContractId -ne $contractId) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Receipt contractId '$($receipt.ContractId)' does not match marker '$contractId'."
        }
    }

    # Freshness: recompute the canonical sources hash from the committed binding and compare. A missing config
    # binding means freshness cannot be confirmed, so fail loud (never a false-green on an unverifiable receipt).
    $check = Find-ArchCheckForContract -RepoRoot $repoRootFull -ContractId $contractId -ConfigPath $ConfigPath
    if ($null -eq $check) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Cannot verify freshness for '$contractId': no arch-test-config.json check found to recompute its sources hash."
        }
    }

    # Derive the AUTHORITATIVE adapter + maturity from the trusted config/contract, NEVER the receipt's own
    # copies (which steer the gate). A receipt whose adapter/maturity disagrees is a tamper/staleness signal ->
    # fail loud, closing the advisory-downgrade (forge adapter=semantic-eval) and maturity-downgrade false-greens.
    # verdict/ran are the run OUTPUT and exist only in the receipt: per the trust anchor (git history + human
    # commit, not crypto) they are reviewer-enforced, so this marker rejects stale/malformed, not a receipt
    # forged by a party with commit access (the human reviewing the committed receipt + contract is the anchor).
    $configAdapter = if (($check.PSObject.Properties.Name -contains 'adapter') -and $check.adapter) { [string]$check.adapter } else { $null }
    $effectiveMaturity = Resolve-ArchEffectiveMaturity -Check $check -RepoRoot $repoRootFull

    if ($configAdapter -and ($receipt.Adapter -ne $configAdapter)) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Receipt adapter '$($receipt.Adapter)' does not match the config adapter '$configAdapter' for '$contractId' (possible tamper or stale receipt)."
        }
    }
    if ($receipt.Maturity -ne $effectiveMaturity) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Receipt maturity '$($receipt.Maturity)' does not match the contract-derived maturity '$effectiveMaturity' for '$contractId' (possible tamper or stale receipt)."
        }
    }

    $currentHash = Get-ArchTestCheckSourcesHash -Check $check -Maturity $effectiveMaturity -RepoRoot $repoRootFull
    if ($currentHash -ne $receipt.SourcesHash) {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $false
            Blocking = $isBlockingStage
            Message = "Stale arch-test receipt for '$contractId': recorded sourcesHash no longer matches the current contract/target sources. Re-run the arch-tests runner."
        }
    }

    # Gate on the TRUSTED config adapter + contract-derived maturity; only verdict/ran come from the receipt.
    $outcome = Get-ArchGateOutcome -Maturity $effectiveMaturity -Verdict $receipt.Verdict -Ran $receipt.Ran -Adapter $configAdapter
    if ($outcome -eq 'pass') {
        return [pscustomobject]@{
            Marker = $Marker
            Success = $true
            Blocking = $isBlockingStage
            Message = "arch receipt for '$contractId' is fresh and passing ($($receipt.Adapter)/$effectiveMaturity)."
        }
    }

    # 'warn' is advisory (draft/provisional or semantic-eval) -> non-blocking; 'block' is unrun-required for a
    # locked contract -> blocking at a crosscheck stage.
    $blocking = ($outcome -eq 'block') -and $isBlockingStage
    return [pscustomobject]@{
        Marker = $Marker
        Success = $false
        Blocking = $blocking
        Message = "arch receipt for '$contractId': verdict '$($receipt.Verdict)' maps to '$outcome' under maturity '$effectiveMaturity'."
    }
}

Export-ModuleMember -Function Parse-PlanFileEvidenceMarker, Invoke-PlanFileEvidence, Invoke-PlanArchEvidence, Find-ArchCheckForContract
