#requires -Version 7.0
<#
.SYNOPSIS
Shared architecture-receipt substrate: the single source of truth for the canonical sources hash, the
check binding, the taxonomy x maturity gate mapping, and pure-parse receipt reading.

.DESCRIPTION
Both producers and verifiers of arch-test receipts depend on this module so they can never drift:
  * Invoke-ArchTests.ps1 (the runner) computes sourcesHash + binding and mints receipts.
  * Get-ArchReviewReport.ps1 recomputes sourcesHash to reject STALE receipts and maps the recorded
    verdict through the same gate matrix — WITHOUT executing any toolchain.

The hash is a pure content hash over source files (+ synthetic binding records); reading a receipt is a
pure JSON parse with schema-shape validation. Nothing here shells a toolchain or executes plan/contract text.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArchReceiptAdapters = @('netarchtest', 'ts-arch', 'dependency-cruiser', 'semantic-eval')
$script:ArchReceiptVerdicts = @('pass', 'fail', 'skip-absent-toolchain', 'error')
$script:ArchReceiptMaturities = @('locked', 'draft', 'provisional')
$script:ArchReceiptIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
# git OID: SHA-1 (40 hex) or SHA-256 (64 hex).
$script:ArchReceiptCommitPattern = '^[a-f0-9]{40}([a-f0-9]{24})?$'
$script:ArchReceiptSourcesHashPattern = '^[0-9a-f]{64}$'

function Get-ArchTestSourcesHash {
    <#
    .SYNOPSIS
    Canonical tree/content hash of a contract's source paths plus optional synthetic binding records.

    .DESCRIPTION
    Order- and encoding-stable, add/edit/delete-sensitive. Each resolved file is addressed by its
    case-preserving relative path (forward slashes) relative to RepoRoot; content is BOM-stripped and
    CRLF/CR normalized to LF; records are fed as UTF8(relPath)+NUL+UTF8(content)+NUL in ordinal-sorted
    relative-path order. -ExtraContent injects synthetic records (e.g. the check's binding fields) keyed
    by a NUL-prefixed name that can never collide with a real relative path, so changing an adapter/spec
    /testProject/provider invalidates the digest even when no file content changed.

    Editing, adding, or deleting any resolved source (or any binding field) changes the digest;
    reordering the filesystem does not. Returns the lower-hex SHA-256, the ordered real-file paths, and
    the resolved real-file count (excluding synthetic records).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory)][string]$RepoRoot,
        [hashtable]$ExtraContent,
        [long]$MaxFileBytes = 5242880
    )

    $rootFull = (Resolve-Path -LiteralPath $RepoRoot).Path
    $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $confinePrefix = $rootPrefix + [System.IO.Path]::DirectorySeparatorChar

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()
    $fileCount = 0

    foreach ($p in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $rootFull $p }
        # Confine the declared path to the repo root so a rooted / '..'-escaping / device target cannot make the
        # verifier expand or read arbitrary host content into the digest (the file: evaluator enforces the same).
        $fullNorm = [System.IO.Path]::GetFullPath($full)
        if ($fullNorm -ne $rootPrefix -and -not ($fullNorm + [System.IO.Path]::DirectorySeparatorChar).StartsWith($confinePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        # Expand directories and globs to a stable file set. Literal existing paths are read as-is;
        # only genuinely non-existent paths fall through to wildcard resolution.
        $resolved = @()
        if (Test-Path -LiteralPath $full -PathType Container) {
            $resolved = @(Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue)
        }
        elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            $resolved = @(Get-Item -LiteralPath $full -ErrorAction SilentlyContinue)
        }
        elseif ($full -match '[\*\?\[\]]') {
            $resolved = @(Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue)
        }
        else {
            # A declared literal target that does not exist: leave $resolved empty so its absence is
            # add/delete-sensitive (deleting a listed file changes the digest by removing its record).
            $resolved = @()
        }

        foreach ($f in $resolved) {
            $fp = $f.FullName
            # Never follow a symlink out of the tree, never read an oversized file (DoS), and re-confine each
            # resolved file to the repo root (a recursive dir expansion could otherwise surface an escaping link).
            if (($f.PSObject.Properties.Name -contains 'LinkType') -and $f.LinkType) { continue }
            if ($f.Length -gt $MaxFileBytes) { continue }
            $fpNorm = [System.IO.Path]::GetFullPath($fp)
            if (-not $fpNorm.StartsWith($confinePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not $seen.Add($fp)) { continue }
            $rel = $fp
            if ($fp.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rel = $fp.Substring($rootPrefix.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            }
            # Case-preserving so a case-only rename is visible and two case-distinct files on a
            # case-sensitive filesystem never collapse to one record (which would make the sort unstable).
            $rel = $rel.Replace('\', '/')
            $records.Add([pscustomobject]@{ Rel = $rel; FullName = $fp; Synthetic = $false })
            $fileCount++
        }
    }

    if ($ExtraContent) {
        foreach ($key in $ExtraContent.Keys) {
            $records.Add([pscustomobject]@{ Rel = [string]$key; Content = [string]$ExtraContent[$key]; Synthetic = $true })
        }
    }

    # Ordinal sort so the canonical record order is identical across OSes/ICU versions.
    $records.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Rel, $b.Rel) })

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = [System.IO.MemoryStream]::new()
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($r in $records) {
            $raw = if ($r.Synthetic) { [string]$r.Content } else { [System.IO.File]::ReadAllText($r.FullName) }
            $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
            $relBytes = $utf8.GetBytes($r.Rel)
            $contentBytes = $utf8.GetBytes($raw)
            $buffer.Write($relBytes, 0, $relBytes.Length)
            $buffer.WriteByte(0)
            $buffer.Write($contentBytes, 0, $contentBytes.Length)
            $buffer.WriteByte(0)
        }
        $buffer.Position = 0
        $hashBytes = $sha.ComputeHash($buffer)
        $buffer.Dispose()
    }
    finally {
        $sha.Dispose()
    }

    $hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return [pscustomobject]@{
        Digest = $hex
        Files  = @($records | Where-Object { -not $_.Synthetic } | ForEach-Object { $_.Rel })
        Count  = $fileCount
    }
}

function Get-ArchTestCheckBinding {
    <#
    .SYNOPSIS
    Canonical, order-stable JSON of a check's identity/binding fields for the freshness digest.

    .DESCRIPTION
    Folds the fields that change WHAT a contract enforces (adapter, spec, testProject, provider,
    maturity, contractId, contractPath, sorted targets) into the hash so repointing any of them
    invalidates prior receipts even when no target file content changed.
    #>
    param(
        [Parameter(Mandatory)]$Check,
        [Parameter(Mandatory)][string]$Maturity
    )

    $get = {
        param($name)
        if (($Check.PSObject.Properties.Name -contains $name) -and $null -ne $Check.$name) { [string]$Check.$name } else { '' }
    }
    $targets = @()
    if (($Check.PSObject.Properties.Name -contains 'targets') -and $Check.targets) {
        $targets = @($Check.targets | ForEach-Object { [string]$_ } | Sort-Object -Culture ([System.Globalization.CultureInfo]::InvariantCulture))
    }

    $binding = [ordered]@{
        adapter      = (& $get 'adapter')
        contractId   = (& $get 'contractId')
        contractPath = (& $get 'contractPath')
        maturity     = $Maturity
        provider     = (& $get 'provider')
        spec         = (& $get 'spec')
        targets      = $targets
        testProject  = (& $get 'testProject')
    }
    return ($binding | ConvertTo-Json -Compress -Depth 6)
}

function Get-ArchTestCheckSourcesHash {
    <#
    .SYNOPSIS
    Recomputes the canonical sourcesHash for one config check exactly as the runner minted it.

    .DESCRIPTION
    Mirrors the runner's per-check hashing: hash paths = contractPath + targets, plus the check binding as a
    synthetic record keyed by a NUL-prefixed name (so repointing an adapter/spec/testProject/provider
    invalidates the digest). Pure content hashing — no toolchain execution. Returns the lower-hex digest.
    #>
    param(
        [Parameter(Mandatory)]$Check,
        [Parameter(Mandatory)][string]$Maturity,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $hashPaths = [System.Collections.Generic.List[string]]::new()
    if (($Check.PSObject.Properties.Name -contains 'contractPath') -and $Check.contractPath) {
        $hashPaths.Add([string]$Check.contractPath)
    }
    if (($Check.PSObject.Properties.Name -contains 'targets') -and $Check.targets) {
        foreach ($t in @($Check.targets)) { $hashPaths.Add([string]$t) }
    }

    $binding = Get-ArchTestCheckBinding -Check $Check -Maturity $Maturity
    $extra = @{ ("$([char]0)binding") = $binding }
    $hash = Get-ArchTestSourcesHash -Paths @($hashPaths) -RepoRoot $RepoRoot -ExtraContent $extra
    return $hash.Digest
}

function Resolve-ArchEffectiveMaturity {
    <#
    .SYNOPSIS
    Derives the AUTHORITATIVE effective maturity for a check from the human-owned contract, then config.

    .DESCRIPTION
    Mirrors the runner: the contract file governs, the config check is a fallback, default is 'draft'. A config
    that disagrees with the contract is a hard error (the runner refuses it too). The verifier uses this instead
    of trusting the receipt's maturity copy, so a forged/downgraded receipt.maturity cannot steer the gate.
    #>
    param(
        [Parameter(Mandatory)]$Check,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $configMaturity = if (($Check.PSObject.Properties.Name -contains 'maturity') -and $Check.maturity) { [string]$Check.maturity } else { $null }
    $contractMaturity = $null
    if (($Check.PSObject.Properties.Name -contains 'contractPath') -and $Check.contractPath) {
        $cp = [string]$Check.contractPath
        $cpFull = if ([System.IO.Path]::IsPathRooted($cp)) { $cp } else { Join-Path $RepoRoot $cp }
        if (Test-Path -LiteralPath $cpFull -PathType Leaf) {
            try {
                $contract = Get-Content -LiteralPath $cpFull -Raw | ConvertFrom-Json
                if (($contract.PSObject.Properties.Name -contains 'maturity') -and $contract.maturity) {
                    $contractMaturity = [string]$contract.maturity
                }
            }
            catch { $contractMaturity = $null }
        }
    }

    if ($configMaturity -and $contractMaturity -and ($configMaturity -ne $contractMaturity)) {
        throw "Maturity mismatch for contract '$([string]$Check.contractId)': config '$configMaturity' vs contract '$contractMaturity' (contract governs)."
    }
    $maturity = if ($contractMaturity) { $contractMaturity } elseif ($configMaturity) { $configMaturity } else { 'draft' }
    if ($script:ArchReceiptMaturities -notcontains $maturity) {
        throw "Invalid maturity '$maturity' for contract '$([string]$Check.contractId)'."
    }
    return $maturity
}

function Get-ArchGateOutcome {
    <#
    .SYNOPSIS
    Maps a taxonomy verdict to a gate outcome honouring contract maturity.

    .DESCRIPTION
    A verdict is only treated as a pass when the adapter actually ran ('pass' with Ran=$true). Locked
    contracts hard-gate: ONLY a real pass greens; anything else (fail, error, skip-absent-toolchain, or a
    pass that did not run) blocks — skip is never a false-green. Draft/provisional contracts warn on any
    non-pass so evolving contracts inform without blocking. Returns 'pass', 'warn', or 'block'.

    The `semantic-eval` (LLM) adapter is ADVISORY IN THE GATE ALWAYS (REQ-10/REQ-16): its verdict never
    blocks regardless of maturity — a non-pass warns, so a hijacked or flaky LLM cannot fail CI. Only the
    deterministic adapters honour the locked hard-gate.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$Maturity,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'skip-absent-toolchain', 'error')][string]$Verdict,
        [Parameter(Mandatory)][bool]$Ran,
        [ValidateSet('netarchtest', 'ts-arch', 'dependency-cruiser', 'semantic-eval')][string]$Adapter
    )

    if ($Adapter -eq 'semantic-eval') {
        # LLM verdicts are advisory only: a real pass greens the row, anything else warns; never block.
        if ($Verdict -eq 'pass' -and $Ran) { return 'pass' }
        return 'warn'
    }

    if ($Verdict -eq 'pass' -and $Ran) { return 'pass' }
    if ($Maturity -eq 'locked') { return 'block' }
    return 'warn'
}

function Read-ArchReceipt {
    <#
    .SYNOPSIS
    Pure-parses an arch-test receipt file and validates its schema shape. Throws on malformed input.

    .DESCRIPTION
    Reads and JSON-parses a receipt, then asserts the required fields and their formats (schemaVersion '1',
    path-safe contractId, taxonomy verdict, maturity/adapter enums, 40/64-hex parentCommit, 64-hex
    sourcesHash, boolean ran, and the pass=>ran invariant). No toolchain execution, no plan/contract-text
    execution. Returns a normalized [pscustomobject] the marker maps through the gate matrix.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Receipt not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $obj = $raw | ConvertFrom-Json -Depth 20
    }
    catch {
        throw "Receipt is not valid JSON ($Path): $($_.Exception.Message)"
    }

    foreach ($field in @('schemaVersion', 'contractId', 'maturity', 'adapter', 'verdict', 'ran', 'parentCommit', 'sourcesHash')) {
        if (-not ($obj.PSObject.Properties.Name -contains $field)) {
            throw "Receipt is missing required field '$field' ($Path)."
        }
    }

    if ([string]$obj.schemaVersion -ne '1') { throw "Receipt schemaVersion must be '1' ($Path)." }
    if ([string]$obj.contractId -notmatch $script:ArchReceiptIdPattern) { throw "Receipt contractId is malformed ($Path)." }
    if ($script:ArchReceiptMaturities -notcontains [string]$obj.maturity) { throw "Receipt maturity '$($obj.maturity)' is out of range ($Path)." }
    if ($script:ArchReceiptAdapters -notcontains [string]$obj.adapter) { throw "Receipt adapter '$($obj.adapter)' is out of range ($Path)." }
    if ($script:ArchReceiptVerdicts -notcontains [string]$obj.verdict) { throw "Receipt verdict '$($obj.verdict)' is out of taxonomy ($Path)." }
    if ($obj.ran -isnot [bool]) { throw "Receipt 'ran' must be a boolean ($Path)." }
    if ([string]$obj.parentCommit -notmatch $script:ArchReceiptCommitPattern) { throw "Receipt parentCommit is not a 40/64-hex SHA ($Path)." }
    if ([string]$obj.sourcesHash -notmatch $script:ArchReceiptSourcesHashPattern) { throw "Receipt sourcesHash is not a 64-hex SHA-256 ($Path)." }
    if ([string]$obj.verdict -eq 'pass' -and -not [bool]$obj.ran) { throw "Receipt claims verdict=pass with ran=false (false-green) ($Path)." }

    return [pscustomobject]@{
        SchemaVersion = [string]$obj.schemaVersion
        ContractId    = [string]$obj.contractId
        Maturity      = [string]$obj.maturity
        Adapter       = [string]$obj.adapter
        Verdict       = [string]$obj.verdict
        Ran           = [bool]$obj.ran
        ParentCommit  = [string]$obj.parentCommit
        SourcesHash   = [string]$obj.sourcesHash
        LockDecision  = if ($obj.PSObject.Properties.Name -contains 'lockDecision') { [string]$obj.lockDecision } else { $null }
    }
}

function Get-ArchReceiptPath {
    <#
    .SYNOPSIS
    Resolves the canonical receipt path for a contract id under a repo root.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ContractId,
        [string]$ReceiptDir
    )
    if ([string]$ContractId -notmatch $script:ArchReceiptIdPattern) {
        throw "Invalid contractId '$ContractId'; refusing to derive a receipt path from it."
    }
    $dir = if (-not [string]::IsNullOrWhiteSpace($ReceiptDir)) { $ReceiptDir } else { Join-Path $RepoRoot 'docs/architecture-notes/receipts' }
    return Join-Path $dir ("$ContractId.arch-receipt.json")
}

Export-ModuleMember -Function Get-ArchTestSourcesHash, Get-ArchTestCheckBinding, Get-ArchTestCheckSourcesHash, Resolve-ArchEffectiveMaturity, Get-ArchGateOutcome, Read-ArchReceipt, Get-ArchReceiptPath
