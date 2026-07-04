#requires -Version 7.0
<#
.SYNOPSIS
Pluggable architecture-test adapter interface (REQ-9). Dispatches a check to a named deterministic adapter
behind the lock-before-execute gate, and normalizes every adapter's return into the strict result contract.

.DESCRIPTION
Bundled into the architecture-tests plugin. The dispatcher owns two invariants:

  1. LOCK GATE FIRST. Before an adapter is loaded or invoked, Get-ArchLockExecutionDecision (from
     Assert-ArchLock.ps1) decides whether the contract's derived body may run. Only a locked contract whose
     recomputed body hash matches its recorded lockedBodySha256 reaches the adapter. Draft/provisional
     bodies are NOT executed (skip). A locked-but-mutated body yields 'lock-invalidated' -> 'error' (blocks).

  2. STRICT RESULT CONTRACT. Every adapter returns { status; ran; findings[]; artifacts[] } where status is
     one of pass | fail | skip-absent-toolchain | error, and 'ran' is a real boolean. The dispatcher
     validates and re-shapes the adapter output so downstream gating never trusts an ad-hoc shape.

Adapters are plain scripts under an adapter root (default: this plugin's scripts/adapters/). An adapter file
is '<Name>.Adapter.ps1' exposing 'Invoke-<Name>Adapter -Context <hashtable>'. New adapters need no dispatcher
change — that is the pluggability contract.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# config adapter id -> adapter file/function base name
$script:ArchAdapterAliases = @{
    'netarchtest'         = 'NetArchTest'
    'ts-arch'             = 'TsArch'
    'dependency-cruiser'  = 'DependencyCruiser'
}

$script:ArchAdapterStatuses = @('pass', 'fail', 'skip-absent-toolchain', 'error')

function Resolve-ArchAdapterBase {
    param([Parameter(Mandatory)][string]$AdapterName)
    if ($script:ArchAdapterAliases.ContainsKey($AdapterName)) { return $script:ArchAdapterAliases[$AdapterName] }
    return $AdapterName
}

function Get-ArchAdapterScriptPath {
    <#
    .SYNOPSIS
    Resolves the adapter script file for a name under AdapterRoot. Returns $null when absent (pluggable:
    an unknown/uninstalled adapter is a skip, not a dispatcher error).
    #>
    param(
        [Parameter(Mandatory)][string]$AdapterName,
        [Parameter(Mandatory)][string]$AdapterRoot
    )
    $base = Resolve-ArchAdapterBase -AdapterName $AdapterName
    $candidate = Join-Path $AdapterRoot "$base.Adapter.ps1"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    return $null
}

function ConvertTo-ArchAdapterResult {
    <#
    .SYNOPSIS
    Normalizes/validates a raw adapter return into the strict result contract. Fails loud on an out-of-taxonomy
    status so a malformed adapter can never masquerade as a pass.
    #>
    param([Parameter(Mandatory)]$Raw)

    $rawProps = $Raw.PSObject.Properties.Name
    if ($rawProps -notcontains 'status') {
        throw "Adapter result is missing required 'status' (expected one of: $($script:ArchAdapterStatuses -join ', '))."
    }
    if ($rawProps -notcontains 'ran') {
        throw "Adapter result is missing required 'ran' (must be a boolean)."
    }

    $status = [string]$Raw.status
    if ($script:ArchAdapterStatuses -notcontains $status) {
        throw "Adapter returned out-of-taxonomy status '$status' (expected one of: $($script:ArchAdapterStatuses -join ', '))."
    }
    # Require a real boolean: [bool]'false' would coerce to $true and admit a false-green.
    if ($Raw.ran -isnot [bool]) {
        throw "Adapter returned a non-boolean 'ran' (got '$($Raw.ran)'); it must be an actual [bool]."
    }
    $ran = [bool]$Raw.ran
    if ($status -eq 'pass' -and -not $ran) {
        throw "Adapter returned status 'pass' with ran=false; a pass must have actually run."
    }

    $findings = @()
    if ($rawProps -contains 'findings' -and $null -ne $Raw.findings) { $findings = @($Raw.findings) }
    $artifacts = @()
    if ($rawProps -contains 'artifacts' -and $null -ne $Raw.artifacts) { $artifacts = @($Raw.artifacts) }

    return [pscustomobject]@{
        status    = $status
        ran       = $ran
        findings  = $findings
        artifacts = $artifacts
    }
}

function Invoke-ArchTestAdapter {
    <#
    .SYNOPSIS
    Dispatch a single check to its adapter, behind the lock-before-execute gate.

    .DESCRIPTION
    Order of operations:
      1. Lock gate (Get-ArchLockExecutionDecision) — decides execute / skip-not-locked / lock-invalidated.
      2. If not 'execute', return a synthetic result WITHOUT loading the adapter:
           skip-not-locked  -> status 'skip-absent-toolchain', ran=false (draft body not executed).
           lock-invalidated -> status 'error', ran=false (blocks; review flags drift).
      3. Resolve the adapter script; if absent -> 'skip-absent-toolchain', ran=false.
      4. Dot-source it and call Invoke-<Base>Adapter -Context @{...}; normalize the return.

    Returns { status; ran; findings[]; artifacts[]; decision } (decision echoes the lock gate outcome).
    #>
    param(
        [Parameter(Mandatory)][string]$AdapterName,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BodyPaths,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$TargetRoot,
        [string]$AdapterRoot
    )

    if (-not (Get-Command Get-ArchLockExecutionDecision -ErrorAction SilentlyContinue)) {
        throw "Assert-ArchLock.ps1 must be dot-sourced before Invoke-ArchTestAdapter (lock gate is mandatory)."
    }

    $decision = Get-ArchLockExecutionDecision -Contract $Contract -BodyPaths $BodyPaths -RepoRoot $RepoRoot

    if ($decision.Decision -eq 'skip-not-locked') {
        return [pscustomobject]@{
            status    = 'skip-absent-toolchain'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'info'; message = "not executed: $($decision.Reason)" })
            artifacts = @()
            decision  = $decision.Decision
        }
    }
    if ($decision.Decision -eq 'lock-invalidated') {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = "lock-invalidated: $($decision.Reason)" })
            artifacts = @()
            decision  = $decision.Decision
        }
    }

    if ([string]::IsNullOrWhiteSpace($AdapterRoot)) {
        # Default: an 'adapters' dir beside this dispatcher. In the installed plugin the dispatcher is bundled
        # to skills/architecture-tests/scripts/ and the adapters ship at skills/architecture-tests/scripts/adapters/.
        $AdapterRoot = Join-Path $PSScriptRoot 'adapters'
    }

    $scriptPath = Get-ArchAdapterScriptPath -AdapterName $AdapterName -AdapterRoot $AdapterRoot
    if (-not $scriptPath) {
        return [pscustomobject]@{
            status    = 'skip-absent-toolchain'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'info'; message = "adapter '$AdapterName' not installed under $AdapterRoot" })
            artifacts = @()
            decision  = $decision.Decision
        }
    }

    $base = Resolve-ArchAdapterBase -AdapterName $AdapterName
    $fn = "Invoke-$($base -replace '[^A-Za-z0-9]', '')Adapter"

    . $scriptPath
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        throw "Adapter script '$scriptPath' does not define expected entrypoint '$fn'."
    }

    $context = @{
        ContractId  = [string]$Contract.id
        TargetRoot  = $TargetRoot
        RepoRoot    = $RepoRoot
        BodyPaths   = @($BodyPaths)
    }

    $raw = & $fn -Context $context
    $result = ConvertTo-ArchAdapterResult -Raw $raw
    return [pscustomobject]@{
        status    = $result.status
        ran       = $result.ran
        findings  = $result.findings
        artifacts = $result.artifacts
        decision  = $decision.Decision
    }
}
