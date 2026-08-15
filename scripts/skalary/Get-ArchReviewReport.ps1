#requires -Version 7.0
<#
.SYNOPSIS
Architecture-review report: surfaces the runner-receipt verdict per contract so a schema-only review can
never false-green a failing or absent LOCKED contract (REQ-16). Read-only, pure-parse — never executes a
toolchain or plan/contract text.

.DESCRIPTION
The architecture-tests skill calls this to fold receipts into its tier report. For every check in the
arch-test config it performs architecture-tests-local receipt verification: a LOCKED contract whose receipt is
missing / stale / malformed / non-pass surfaces as a BLOCKING finding, while `draft`/`provisional` and
`semantic-eval` are advisory only once a receipt exists and passes freshness. It also flags a
`lock-invalidated` receipt (a locked body whose recomputed hash no longer matches `lockedBodySha256`) as drift.

The trust anchor is unchanged: this report proves integrity/freshness, not anti-forgery — a human reviewing
the committed contract + receipt is the tamper-evidence, and locked promotions must land in a human-authored
commit (audited separately by the SKILL against the promoting commit's authorship, not the on-disk field).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ConfigPath,
    [string]$ReceiptDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ArchReceipt.psm1') -Force -DisableNameChecking

function Resolve-ArchReviewConfigPath {
    <#
    .SYNOPSIS
    Resolves the arch-test config path deterministically (explicit, then repo-root, then arch-notes tier).
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ConfigPath
    )
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Arch-test config not found: $ConfigPath" }
        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }

    $candidates = @(
        (Join-Path $RepoRoot 'arch-test-config.json'),
        (Join-Path $RepoRoot 'docs/architecture-notes/arch-test-config.json')
    )
    $found = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($found.Count -eq 0) { return $null }
    if ($found.Count -gt 1) { throw "Ambiguous arch-test config: $($found -join ', '). Consolidate to one." }
    return (Resolve-Path -LiteralPath $found[0]).Path
}

function Invoke-ArchReviewEvidence {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Check,
        [string]$ReceiptDir
    )

    $contractId = [string]$Check.contractId
    $receiptPath = Get-ArchReceiptPath -RepoRoot $RepoRoot -ContractId $contractId -ReceiptDir $ReceiptDir
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        return [pscustomobject]@{
            Success = $false
            Blocking = $true
            Message = "No arch-test receipt for contract '$contractId' (unrun)."
        }
    }

    try {
        $receipt = Read-ArchReceipt -Path $receiptPath
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Blocking = $true
            Message = "Malformed arch-test receipt for '$contractId': $($_.Exception.Message)"
        }
    }

    $adapter = if ($Check.PSObject.Properties.Name -contains 'adapter') { [string]$Check.adapter } else { $null }
    $maturity = Resolve-ArchEffectiveMaturity -Check $Check -RepoRoot $RepoRoot
    if ($receipt.ContractId -ne $contractId -or
        ($adapter -and $receipt.Adapter -ne $adapter) -or
        $receipt.Maturity -ne $maturity) {
        return [pscustomobject]@{
            Success = $false
            Blocking = $true
            Message = "Arch-test receipt identity does not match config/contract for '$contractId'."
        }
    }

    $currentHash = Get-ArchTestCheckSourcesHash -Check $Check -Maturity $maturity -RepoRoot $RepoRoot
    if ($currentHash -ne $receipt.SourcesHash) {
        return [pscustomobject]@{
            Success = $false
            Blocking = $true
            Message = "Stale arch-test receipt for '$contractId'."
        }
    }

    $outcome = Get-ArchGateOutcome -Maturity $maturity -Verdict $receipt.Verdict -Ran $receipt.Ran -Adapter $adapter
    return [pscustomobject]@{
        Success = $outcome -eq 'pass'
        Blocking = $outcome -eq 'block'
        Message = "Arch-test receipt for '$contractId' maps to '$outcome' under maturity '$maturity'."
    }
}

function Get-ArchReviewReport {
    <#
    .SYNOPSIS
    Builds the per-contract review report from the arch-test config + receipts. Returns a summary object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ConfigPath,
        [string]$ReceiptDir
    )

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $resolvedConfig = Resolve-ArchReviewConfigPath -RepoRoot $repoRootFull -ConfigPath $ConfigPath
    if ($null -eq $resolvedConfig) {
        return [pscustomobject]@{ Contracts = @(); Blocking = 0; LockedCount = 0; DraftCount = 0; Drift = 0; ConfigPath = $null }
    }

    $config = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json -Depth 20
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($config.PSObject.Properties.Name -contains 'checks') {
        foreach ($check in @($config.checks)) {
            if (-not ($check.PSObject.Properties.Name -contains 'contractId')) { continue }
            $cid = [string]$check.contractId

            $res = Invoke-ArchReviewEvidence -RepoRoot $repoRootFull -Check $check -ReceiptDir $ReceiptDir

            # Effective blocking: the marker's Blocking flag is "would block IF it failed" (stage-scoped, same as
            # the file: evaluator), so a real blocking finding is a NON-pass whose failure is blocking.
            $effectiveBlocking = [bool]$res.Blocking -and -not [bool]$res.Success

            $maturity = Resolve-ArchEffectiveMaturity -Check $check -RepoRoot $repoRootFull

            # Flag lock-invalidated drift (a locked body whose hash no longer matches lockedBodySha256).
            $lockInvalidated = $false
            $receiptPath = Get-ArchReceiptPath -RepoRoot $repoRootFull -ContractId $cid -ReceiptDir $ReceiptDir
            if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
                try {
                    $receipt = Read-ArchReceipt -Path $receiptPath
                    $lockInvalidated = ($receipt.LockDecision -eq 'lock-invalidated')
                }
                catch { $lockInvalidated = $false }
            }

            $rows.Add([pscustomobject]@{
                    ContractId      = $cid
                    Maturity        = $maturity
                    Success         = [bool]$res.Success
                    Blocking        = [bool]$effectiveBlocking
                    LockInvalidated = [bool]$lockInvalidated
                    Message         = [string]$res.Message
                })
        }
    }

    return [pscustomobject]@{
        Contracts   = @($rows)
        Blocking    = @($rows | Where-Object { $_.Blocking }).Count
        LockedCount = @($rows | Where-Object { $_.Maturity -eq 'locked' }).Count
        DraftCount  = @($rows | Where-Object { $_.Maturity -eq 'draft' -or $_.Maturity -eq 'provisional' }).Count
        Drift       = @($rows | Where-Object { $_.LockInvalidated }).Count
        ConfigPath  = $resolvedConfig
    }
}

# Run main only when invoked directly (not dot-sourced for its functions).
if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path }
    $report = Get-ArchReviewReport -RepoRoot $RepoRoot -ConfigPath $ConfigPath -ReceiptDir $ReceiptDir
    $report | ConvertTo-Json -Depth 8
    if ($report.Blocking -gt 0) { exit 1 }
    exit 0
}
