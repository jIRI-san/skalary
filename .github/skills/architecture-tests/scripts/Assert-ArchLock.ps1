#requires -Version 7.0
<#
.SYNOPSIS
Canonical authority for architecture-contract lock state: body hashing, human-only transitions, and the
before-execution lock gate (REQ-18, RISK-5).

.DESCRIPTION
Single source of truth for everything that decides whether contract-derived framework test code may run.
Bundled into the architecture-tests plugin. It never executes test code itself; it only decides.

Trust rules enforced here:
  * Contract-derived test bodies are NEVER executed until the contract is human-reviewed and 'locked'.
  * lockedBodySha256 is computed here (compute), and re-verified here immediately before execution by
    RECOMPUTE (not hex-presence). A locked contract whose recomputed body hash does not match its
    recorded lockedBodySha256 enters an explicit 'lock-invalidated' state that blocks (never greens) and
    that review flags as drift.
  * Every maturity transition touching 'locked' (draft->locked promotion, locked->draft demotion) is
    human-only. Autonomy is detected by a CONCRETE signal (env var / explicit flag), never agent
    self-assessment. An autonomous run may only record a promotion proposal; it may not mutate lock state.

The trust anchor remains the human-authored, reviewed git commit; these checks are the machine enforcement
that keeps an autonomous agent from self-promoting past that human gate.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArchLockTruthy = @('1', 'true', 'yes', 'on')
# Documented, concrete autonomous-context signals. Presence of any truthy value means "autonomous run".
$script:ArchLockAutonomousEnvVars = @('SKALARY_ARCH_AUTONOMOUS', 'SKALARY_AUTOPILOT', 'COPILOT_AUTOPILOT')

function Get-ArchLockedBodyHash {
    <#
    .SYNOPSIS
    THE canonical body hash: lower-hex SHA-256 over the reviewed executable test body file set.

    .DESCRIPTION
    Order- and encoding-stable, add/edit/delete-sensitive. Each resolved file is addressed by its
    case-preserving relative path (forward slashes) relative to RepoRoot; content is BOM-stripped and
    CRLF/CR normalized to LF; records feed as UTF8(relPath)+NUL+UTF8(content)+NUL in ordinal-sorted
    relative-path order. This is the sole computation of lockedBodySha256 — both lock-time compute and
    pre-execution recompute-verify call it, so they can never diverge over an algorithm difference.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $records = Resolve-ArchLockedBodyFile -Paths $Paths -RepoRoot $RepoRoot

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = [System.IO.MemoryStream]::new()
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($r in $records) {
            $raw = [System.IO.File]::ReadAllText($r.FullName)
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

    return (-join ($hashBytes | ForEach-Object { $_.ToString('x2') }))
}

function Resolve-ArchLockedBodyFile {
    <#
    .SYNOPSIS
    Resolves the body path set to a deduped, ordinal-sorted list of { Rel; FullName } records. Shared by the
    hash (so the hash is add/edit/delete-sensitive) and the execution gate (so it can detect an empty body set).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $rootFull = (Resolve-Path -LiteralPath $RepoRoot).Path
    $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()

    foreach ($p in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $rootFull $p }

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

        foreach ($f in $resolved) {
            $fp = $f.FullName
            if (-not $seen.Add($fp)) { continue }
            $rel = $fp
            if ($fp.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rel = $fp.Substring($rootPrefix.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            }
            $rel = $rel.Replace('\', '/')
            $records.Add([pscustomobject]@{ Rel = $rel; FullName = $fp })
        }
    }

    $records.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Rel, $b.Rel) })
    return , $records
}

function Test-ArchAutonomousContext {
    <#
    .SYNOPSIS
    Detects an autonomous run via a CONCRETE signal (explicit flag or documented env var), never agent
    self-assessment. Returns $true when the run is autonomous (and therefore forbidden from mutating lock
    state).

    .DESCRIPTION
    Fail-safe against suppression: an explicit $true forces autonomous ON, but an explicit $false can NOT clear
    an environment-detected autonomous signal (otherwise an agent could pass -Autonomous:$false to self-promote
    a lock). Autonomy is true when EITHER the explicit flag is $true OR any documented env var is truthy.
    #>
    param(
        # Explicit signal. $true forces autonomous; $false does NOT override an env-detected autonomous context.
        [Nullable[bool]]$Explicit
    )

    if ($Explicit -eq $true) { return $true }

    foreach ($name in $script:ArchLockAutonomousEnvVars) {
        $val = [System.Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($val) -and ($script:ArchLockTruthy -contains $val.Trim().ToLowerInvariant())) {
            return $true
        }
    }
    return $false
}

function Test-ArchLockWriteAllowed {
    <#
    .SYNOPSIS
    The write-gate predicate: may a contract be written/kept at maturity 'locked' in this context?

    .DESCRIPTION
    Refuses a 'locked' write that lacks a verified human signal (i.e. is running autonomously). Non-locked
    writes are always allowed. Returns $true/$false; the write-gate script turns $false into a hard refusal.
    #>
    param(
        [Parameter(Mandatory)][string]$Maturity,
        [Nullable[bool]]$Autonomous
    )

    if ($Maturity -ne 'locked') { return $true }
    $isAutonomous = Test-ArchAutonomousContext -Explicit $Autonomous
    return (-not $isAutonomous)
}

function New-ArchPromotionProposal {
    <#
    .SYNOPSIS
    Records a promotion/demotion PROPOSAL (the only lock-related artifact an autonomous run may emit).

    .DESCRIPTION
    Writes a deterministic JSON proposal to <ProposalDir>/<ContractId>.promotion-proposal.json. A human
    later reviews it and, from a human-authored commit, performs the real transition. Returns the path.
    #>
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$ContractId,
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$FromMaturity,
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$ToMaturity,
        [Parameter(Mandatory)][string]$ProposalDir,
        [string]$ComputedBodyHash,
        [string]$GeneratedAt
    )

    $stamp = if ([string]::IsNullOrWhiteSpace($GeneratedAt)) {
        (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    else { $GeneratedAt }

    $proposal = [ordered]@{
        schemaVersion    = '1'
        kind             = 'arch-promotion-proposal'
        contractId       = $ContractId
        fromMaturity     = $FromMaturity
        toMaturity       = $ToMaturity
        computedBodyHash = if ([string]::IsNullOrWhiteSpace($ComputedBodyHash)) { $null } else { $ComputedBodyHash }
        note             = 'Autonomous run may not mutate lock state. A human must apply this transition from a reviewed commit.'
        generatedAt      = $stamp
    }

    [void](New-Item -ItemType Directory -Path $ProposalDir -Force)
    $path = Join-Path $ProposalDir ("$ContractId.promotion-proposal.json")
    $json = ($proposal | ConvertTo-Json -Depth 8)
    $json = ($json -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Assert-ArchLockTransition {
    <#
    .SYNOPSIS
    Human-only guard for maturity transitions that touch 'locked'.

    .DESCRIPTION
    draft->locked (promotion) and locked->draft (demotion) are honored only from a human context. In an
    autonomous context this refuses the transition; if -ProposalDir is given it records a promotion
    proposal instead. Transitions not involving 'locked' are permitted. Returns an outcome object
    { Allowed; Autonomous; ProposalPath }; throws when the transition is refused and no proposal sink is
    provided (so a caller can't silently proceed).
    #>
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$ContractId,
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$FromMaturity,
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$ToMaturity,
        [Nullable[bool]]$Autonomous,
        [string]$ProposalDir,
        [string]$ComputedBodyHash
    )

    $touchesLocked = ($FromMaturity -eq 'locked') -or ($ToMaturity -eq 'locked')
    if (-not $touchesLocked) {
        return [pscustomobject]@{ Allowed = $true; Autonomous = $false; ProposalPath = $null }
    }

    $isAutonomous = Test-ArchAutonomousContext -Explicit $Autonomous
    if (-not $isAutonomous) {
        return [pscustomobject]@{ Allowed = $true; Autonomous = $false; ProposalPath = $null }
    }

    $proposalPath = $null
    if (-not [string]::IsNullOrWhiteSpace($ProposalDir)) {
        $proposalPath = New-ArchPromotionProposal -ContractId $ContractId -FromMaturity $FromMaturity `
            -ToMaturity $ToMaturity -ProposalDir $ProposalDir -ComputedBodyHash $ComputedBodyHash
        return [pscustomobject]@{ Allowed = $false; Autonomous = $true; ProposalPath = $proposalPath }
    }

    throw "Refusing autonomous maturity transition $FromMaturity->$ToMaturity for '$ContractId': locked transitions are human-only. Record a promotion proposal and have a human apply it."
}

function Get-ArchLockExecutionDecision {
    <#
    .SYNOPSIS
    The pre-execution lock gate: decides whether a contract's derived test body may run NOW.

    .DESCRIPTION
    Recomputes the body hash (not hex-presence) and compares to the contract's recorded lockedBodySha256.
    Returns { Decision; Reason; ComputedHash; RecordedHash } where Decision is:
      * 'execute'         — contract is locked and the recomputed body hash matches (only case that runs).
      * 'skip-not-locked' — contract is draft/provisional: body is not executed (untrusted until locked).
      * 'lock-invalidated'— contract is locked but the body hash does not match (or no recorded hash):
                            blocks, never greens, and review flags it as drift.
    #>
    param(
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BodyPaths,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $maturity = if (($Contract.PSObject.Properties.Name -contains 'maturity') -and $Contract.maturity) { [string]$Contract.maturity } else { 'draft' }
    if ($maturity -ne 'locked') {
        return [pscustomobject]@{ Decision = 'skip-not-locked'; Reason = "maturity=$maturity (only locked bodies execute)"; ComputedHash = $null; RecordedHash = $null }
    }

    $recorded = if (($Contract.PSObject.Properties.Name -contains 'lockedBodySha256') -and $Contract.lockedBodySha256) { [string]$Contract.lockedBodySha256 } else { '' }

    # A locked contract whose body set resolves to zero files must never reach 'execute': the constant
    # empty-input hash could otherwise be recorded as a "verified" body with no reviewed code present.
    $bodyFiles = Resolve-ArchLockedBodyFile -Paths $BodyPaths -RepoRoot $RepoRoot
    if (@($bodyFiles).Count -eq 0) {
        return [pscustomobject]@{ Decision = 'lock-invalidated'; Reason = 'locked contract body resolves to zero files'; ComputedHash = $null; RecordedHash = $recorded }
    }

    $computed = Get-ArchLockedBodyHash -Paths $BodyPaths -RepoRoot $RepoRoot

    if ([string]::IsNullOrWhiteSpace($recorded)) {
        return [pscustomobject]@{ Decision = 'lock-invalidated'; Reason = 'locked contract has no recorded lockedBodySha256'; ComputedHash = $computed; RecordedHash = $null }
    }
    if ($recorded -ne $computed) {
        return [pscustomobject]@{ Decision = 'lock-invalidated'; Reason = 'recomputed body hash does not match recorded lockedBodySha256'; ComputedHash = $computed; RecordedHash = $recorded }
    }
    return [pscustomobject]@{ Decision = 'execute'; Reason = 'locked and body hash verified'; ComputedHash = $computed; RecordedHash = $recorded }
}
