#requires -Version 7.0
<#
.SYNOPSIS
Architecture-tests runner: computes freshness-bound receipts for architecture-contract checks.

.DESCRIPTION
Canonical source of the arch-tests runner. It is BUNDLED into the architecture-tests plugin via
Sync-PluginScripts (the plugin references .github/skills/architecture-tests/scripts/Invoke-ArchTests.ps1);
there is intentionally NO plugin-local authored copy so the drift gate keeps a single source of truth.

Responsibilities (Phase 4.1):
  * Read a runner config (arch-test-config.schema.json) that binds each contract to an adapter + sources.
  * Compute a canonical tree/content hash over each contract's definition, binding, and target sources
    (add/edit/delete-sensitive; repointing an adapter/spec/testProject also invalidates it).
  * Record the parent commit (HEAD SHA) at run time.
  * Emit one receipt per check (arch-test-receipt.schema.json) under docs/architecture-notes/receipts.
  * Map the failure-taxonomy verdict to a gate outcome honouring contract maturity.

Deterministic and semantic adapters land in Phase 4.2/5.3. Until an adapter is wired, a check that
cannot execute yields verdict 'skip-absent-toolchain' (ran=false) — which is NEVER a pass for a locked
contract. This script performs NO real toolchain execution and NEVER shells dotnet/npm/vitest; it is
safe to dot-source (functions only) and safe to run structurally.

The trust anchor is the human-authored git commit + review, NOT this receipt: the receipt attests that a
run happened at a recorded tree-state, and freshness compares sourcesHash (contract + binding + targets)
rather than raw HEAD equality, so committing the receipt does not self-invalidate it.
#>
[CmdletBinding()]
param(
    # Runner config validated against arch-test-config.schema.json.
    [string]$ConfigPath,
    # Repository root that source paths and receipt locations resolve against.
    [string]$RepoRoot,
    # Directory receipts are written to. Defaults to <RepoRoot>/docs/architecture-notes/receipts.
    [string]$ReceiptDir,
    # Directory the pluggable adapters live in. Defaults beside the adapter dispatcher (installed layout).
    [string]$AdapterRoot,
    # Directory the semantic-eval provider seam lives in. Defaults to <PSScriptRoot>/providers (installed layout).
    [string]$ProviderRoot,
    # Compute + report without writing receipt files.
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArchTestAdapters = @('netarchtest', 'ts-arch', 'dependency-cruiser', 'semantic-eval')
$script:ArchTestVerdicts = @('pass', 'fail', 'skip-absent-toolchain', 'error')
$script:ArchTestMaturities = @('locked', 'draft', 'provisional')
$script:ArchTestIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
# git OID: SHA-1 (40 hex) or SHA-256 (64 hex).
$script:ArchTestCommitPattern = '^[a-f0-9]{40}([a-f0-9]{24})?$'

# The lock authority (REQ-18) and the pluggable adapter interface (REQ-9) are bundled beside this runner
# (canonical: scripts/skalary/; installed: skills/architecture-tests/scripts/). Dot-source them so both a
# direct run and a dot-source of this file expose their functions.
. (Join-Path $PSScriptRoot 'Assert-ArchLock.ps1')
. (Join-Path $PSScriptRoot 'Invoke-ArchAdapter.ps1')

# The canonical sources-hash / check-binding / gate matrix / receipt reader live in a shared module so the
# runner (producer) and the arch: evidence marker (verifier) can never drift. Import beside this runner.
Import-Module (Join-Path $PSScriptRoot 'ArchReceipt.psm1') -Force -DisableNameChecking

function Resolve-ArchTestParentCommit {
    <#
    .SYNOPSIS
    Resolves the parent commit (HEAD SHA) recorded in a receipt.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $sha = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sha)) {
        throw "Unable to resolve parent commit (git rev-parse HEAD) under: $RepoRoot"
    }
    return ([string]$sha).Trim()
}

function New-ArchTestReceipt {
    <#
    .SYNOPSIS
    Builds a receipt object conforming to arch-test-receipt.schema.json.
    #>
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$ContractId,
        [Parameter(Mandatory)][ValidateSet('locked', 'draft', 'provisional')][string]$Maturity,
        [Parameter(Mandatory)][ValidateSet('netarchtest', 'ts-arch', 'dependency-cruiser', 'semantic-eval')][string]$Adapter,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'skip-absent-toolchain', 'error')][string]$Verdict,
        [Parameter(Mandatory)][bool]$Ran,
        [Parameter(Mandatory)][string]$ParentCommit,
        [Parameter(Mandatory)][string]$SourcesHash,
        [object[]]$Findings,
        [string[]]$Artifacts,
        [ValidateSet('execute', 'skip-not-locked', 'lock-invalidated')][string]$LockDecision,
        [string]$GeneratedAt
    )

    # A pass that never executed is a false-green: refuse to mint it at the source of truth.
    if ($Verdict -eq 'pass' -and -not $Ran) {
        throw "Refusing to emit a 'pass' receipt with ran=false for contract '$ContractId' (would be a false-green)."
    }
    if ($ParentCommit -notmatch $script:ArchTestCommitPattern) {
        throw "ParentCommit must be a 40- or 64-hex git SHA: $ParentCommit"
    }
    if ($SourcesHash -notmatch '^[0-9a-f]{64}$') {
        throw "SourcesHash must be a 64-hex SHA-256: $SourcesHash"
    }

    $stamp = if ([string]::IsNullOrWhiteSpace($GeneratedAt)) {
        (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    else { $GeneratedAt }

    $receipt = [ordered]@{
        schemaVersion = '1'
        contractId    = $ContractId
        maturity      = $Maturity
        adapter       = $Adapter
        verdict       = $Verdict
        ran           = [bool]$Ran
        parentCommit  = $ParentCommit
        sourcesHash   = $SourcesHash
        generatedAt   = $stamp
    }
    if ($PSBoundParameters.ContainsKey('Findings')) { $receipt.findings = @($Findings) }
    if ($PSBoundParameters.ContainsKey('Artifacts')) { $receipt.artifacts = @($Artifacts) }
    if ($PSBoundParameters.ContainsKey('LockDecision') -and $LockDecision) { $receipt.lockDecision = $LockDecision }

    return [pscustomobject]$receipt
}

function Write-ArchTestReceiptFile {
    <#
    .SYNOPSIS
    Writes a receipt to disk with reproducible bytes (BOM-free UTF-8, LF newlines, single trailing LF).
    #>
    param(
        [Parameter(Mandatory)]$Receipt,
        [Parameter(Mandatory)][string]$Path
    )

    $json = ($Receipt | ConvertTo-Json -Depth 12)
    $json = ($json -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n") + "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Resolve-ArchReceiptPath {
    <#
    .SYNOPSIS
    Canonicalize-then-confine helper for a receipt path derived from a contract id.
    .DESCRIPTION
    The contract id comes from the runner config, which is a repo file an operator (or a
    harvested proposal) authors. `docs/architecture-notes/receipts/<contractId>.arch-receipt.json`
    is a scaffolded path outside `.github/`, so the id is the one variable segment that decides
    where a write lands: it is pattern-checked, then the resolved path is confined under the
    receipt root, so an id that escapes the directory fails loud instead of writing outside it.
    #>
    param(
        [Parameter(Mandatory)][string]$ReceiptRoot,
        [Parameter(Mandatory)][string]$ContractId
    )

    if ($ContractId -notmatch $script:ArchTestIdPattern) {
        throw "Invalid contractId '$ContractId' (must match $($script:ArchTestIdPattern)); refusing to derive a receipt path from it."
    }

    $rootFull = [System.IO.Path]::GetFullPath($ReceiptRoot)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull "$ContractId.arch-receipt.json"))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $rootFull.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved receipt path '$candidate' escapes receipt root '$rootFull'."
    }

    return $candidate
}

function Invoke-ArchTests {
    <#
    .SYNOPSIS
    Runs each configured check and emits a receipt per contract.

    .DESCRIPTION
    Phase 4.1 behaviour: no adapter is wired, so every check resolves to 'skip-absent-toolchain'
    (ran=false). It still computes a real, binding-aware sources hash and parent commit so receipts are
    freshness-bound and the gate mapping is exercised. Returns a summary object; writes receipts unless
    -WhatIf.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ReceiptDir,
        [string]$AdapterRoot,
        [string]$ProviderRoot,
        [switch]$WhatIf
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config not found: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if (-not ($config.PSObject.Properties.Name -contains 'checks')) {
        throw "Config has no 'checks' array: $ConfigPath"
    }

    $rootFull = (Resolve-Path -LiteralPath $RepoRoot).Path
    $receiptRoot = if (-not [string]::IsNullOrWhiteSpace($ReceiptDir)) { $ReceiptDir }
    else { Join-Path $rootFull 'docs/architecture-notes/receipts' }

    $parentCommit = Resolve-ArchTestParentCommit -RepoRoot $rootFull

    if (-not $WhatIf) {
        [void](New-Item -ItemType Directory -Path $receiptRoot -Force)
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($check in @($config.checks)) {
        $contractId = [string]$check.contractId
        if ($contractId -notmatch $script:ArchTestIdPattern) {
            throw "Invalid contractId '$contractId' (must match $($script:ArchTestIdPattern)); refusing to derive a receipt path from it."
        }
        $adapter = [string]$check.adapter

        # Load the human-owned contract first: it is the AUTHORITATIVE source of maturity + lockedBodySha256.
        # The runner config only binds a contract to an adapter/targets; it must not be able to downgrade the
        # reviewed maturity, so a config maturity that disagrees with the contract is a hard error.
        $contractObj = $null
        if (($check.PSObject.Properties.Name -contains 'contractPath') -and $check.contractPath) {
            $cp = [string]$check.contractPath
            $cpFull = if ([System.IO.Path]::IsPathRooted($cp)) { $cp } else { Join-Path $rootFull $cp }
            if (Test-Path -LiteralPath $cpFull -PathType Leaf) {
                try { $contractObj = Get-Content -LiteralPath $cpFull -Raw | ConvertFrom-Json } catch { $contractObj = $null }
            }
        }

        $configMaturity = if (($check.PSObject.Properties.Name -contains 'maturity') -and $check.maturity) { [string]$check.maturity } else { $null }
        $contractMaturity = if ($contractObj -and ($contractObj.PSObject.Properties.Name -contains 'maturity') -and $contractObj.maturity) { [string]$contractObj.maturity } else { $null }
        if ($configMaturity -and $contractMaturity -and ($configMaturity -ne $contractMaturity)) {
            throw "Maturity mismatch for contract '$contractId': runner config says '$configMaturity' but the human-owned contract says '$contractMaturity'. The contract governs; refusing to run with a divergent config (it could silently downgrade enforcement)."
        }
        $maturity = if ($contractMaturity) { $contractMaturity } elseif ($configMaturity) { $configMaturity } else { 'draft' }
        if ($script:ArchTestMaturities -notcontains $maturity) {
            throw "Invalid maturity '$maturity' for contract '$contractId'."
        }
        if (-not $contractObj) {
            $contractObj = [pscustomobject]@{ id = $contractId; maturity = $maturity }
        }
        else {
            # The lock gate must see the same effective maturity the gate outcome uses (contract governs).
            $contractObj | Add-Member -NotePropertyName maturity -NotePropertyValue $maturity -Force
        }

        $hashPaths = [System.Collections.Generic.List[string]]::new()
        if (($check.PSObject.Properties.Name -contains 'contractPath') -and $check.contractPath) {
            $hashPaths.Add([string]$check.contractPath)
        }
        if (($check.PSObject.Properties.Name -contains 'targets') -and $check.targets) {
            foreach ($t in @($check.targets)) { $hashPaths.Add([string]$t) }
        }

        $binding = Get-ArchTestCheckBinding -Check $check -Maturity $maturity
        $extra = @{ ("$([char]0)binding") = $binding }
        $hash = Get-ArchTestSourcesHash -Paths @($hashPaths) -RepoRoot $rootFull -ExtraContent $extra

        if ($hashPaths.Count -gt 0 -and $hash.Count -eq 0) {
            Write-Warning "Contract '$contractId' declares sources but none resolved to files; freshness is bound to the binding only."
        }

        # Body paths the lock hash and adapter execute. A .csproj/.vbproj/.fsproj testProject compiles and runs
        # EVERY source file in its project directory, so the lock must hash that whole directory (not just the
        # project-file leaf) — otherwise an agent could rewrite the reviewed .cs assertions without invalidating
        # lockedBodySha256. A single spec file (ts-arch/dependency-cruiser) is hashed as a leaf.
        $bodyPaths = [System.Collections.Generic.List[string]]::new()
        if (($check.PSObject.Properties.Name -contains 'testProject') -and $check.testProject) {
            $tp = [string]$check.testProject
            if ($tp -match '\.(cs|vb|fs|es)proj$') {
                $tpDir = Split-Path -Parent $tp
                if ([string]::IsNullOrWhiteSpace($tpDir)) { $bodyPaths.Add($tp) } else { $bodyPaths.Add($tpDir) }
            }
            else {
                $bodyPaths.Add($tp)
            }
        }
        if (($check.PSObject.Properties.Name -contains 'spec') -and $check.spec) {
            $bodyPaths.Add([string]$check.spec)
        }

        # Dispatch behind the lock-before-execute gate. Only a locked contract whose body hash verifies runs;
        # draft bodies skip (never a false-green); a mutated locked body is lock-invalidated -> error (blocks).
        # The semantic-eval (LLM) adapter is a separate ADVISORY path: it reads UNTRUSTED contract prose (never
        # an executable body), so it bypasses the lock-body gate and its verdict never blocks (see the gate).
        if ($adapter -eq 'semantic-eval') {
            $providerName = [string]$check.provider
            $credentialTarget = if (($check.PSObject.Properties.Name -contains 'credentialTarget') -and $check.credentialTarget) { [string]$check.credentialTarget } else { $null }
            $contractForProvider = if (($check.PSObject.Properties.Name -contains 'contractPath') -and $check.contractPath) {
                $cp2 = [string]$check.contractPath
                if ([System.IO.Path]::IsPathRooted($cp2)) { $cp2 } else { Join-Path $rootFull $cp2 }
            }
            else { $null }

            if ([string]::IsNullOrWhiteSpace($contractForProvider)) {
                # No contract to evaluate: advisory error (never a false pass), no provider call.
                $verdict = 'error'
                $ran = $false
                $adapterResult = [pscustomobject]@{ status = 'error'; ran = $false; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval check '$contractId' declares no contractPath to evaluate." }); artifacts = @() }
            }
            else {
                # dr: confine contractPath to the repo. A rooted / '..'-escaping path would let a config point
                # the semantic-eval provider at a host-local secret and exfiltrate it to the LLM. Reject as
                # advisory error (never read) before any provider call.
                $resolvedContract = [System.IO.Path]::GetFullPath($contractForProvider)
                $repoPrefix = [System.IO.Path]::GetFullPath($rootFull)
                if (-not $repoPrefix.EndsWith([System.IO.Path]::DirectorySeparatorChar)) { $repoPrefix += [System.IO.Path]::DirectorySeparatorChar }
                if (-not ($resolvedContract + [System.IO.Path]::DirectorySeparatorChar).StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $verdict = 'error'
                    $ran = $false
                    $adapterResult = [pscustomobject]@{ status = 'error'; ran = $false; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval check '$contractId': contractPath escapes the repository root; refusing to read '$contractForProvider'." }); artifacts = @() }
                }
                else {
                    $seamRoot = if (-not [string]::IsNullOrWhiteSpace($ProviderRoot)) { $ProviderRoot } else { Join-Path $PSScriptRoot 'providers' }
                    $seamPath = Join-Path $seamRoot 'SemanticEvalProvider.ps1'
                    if (-not (Test-Path -LiteralPath $seamPath -PathType Leaf)) {
                        # Advisory-always: a missing seam degrades to skip (never a throw that would abort sibling
                        # checks), mirroring the deterministic dispatcher's missing-adapter handling.
                        $verdict = 'skip-absent-toolchain'
                        $ran = $false
                        $adapterResult = [pscustomobject]@{ status = 'skip-absent-toolchain'; ran = $false; findings = @([pscustomobject]@{ severity = 'info'; message = "semantic-eval provider seam not found: $seamPath" }); artifacts = @() }
                    }
                    else {
                        try {
                            # dr: a seam that fails to dot-source/run (parse error, bad provider load) must NOT
                            # abort sibling checks — convert any throw here into an advisory error row.
                            . $seamPath
                            $prov = Invoke-SemanticEvalProvider -ProviderName $providerName -ContractPath $contractForProvider `
                                -TargetRoot $rootFull -ConfigPath $ConfigPath -CredentialTarget $credentialTarget
                            $verdict = $prov.status
                            # A verdict only counts as "ran" when the LLM actually produced pass/fail; skip/error did not run.
                            $ran = ($verdict -eq 'pass' -or $verdict -eq 'fail')
                            $adapterResult = [pscustomobject]@{ status = $verdict; ran = $ran; findings = @($prov.findings); artifacts = @($prov.artifacts) }
                        }
                        catch {
                            $verdict = 'error'
                            $ran = $false
                            $adapterResult = [pscustomobject]@{ status = 'error'; ran = $false; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval seam failed to load/run: $($_.Exception.Message)" }); artifacts = @() }
                        }
                    }
                }
            }
            $lockDecision = $null
        }
        else {
            $adapterResult = Invoke-ArchTestAdapter -AdapterName $adapter -Contract $contractObj `
                -BodyPaths @($bodyPaths) -RepoRoot $rootFull -TargetRoot $rootFull -AdapterRoot $AdapterRoot
            $verdict = $adapterResult.status
            $ran = $adapterResult.ran
            $lockDecision = if ($adapterResult.PSObject.Properties.Name -contains 'decision') { [string]$adapterResult.decision } else { $null }
        }

        # Persist the adapter findings and lock-gate decision so review can flag lock-invalidated drift and
        # distinguish a deliberate draft skip from an absent toolchain.
        $receiptArgs = @{
            ContractId   = $contractId
            Maturity     = $maturity
            Adapter      = $adapter
            Verdict      = $verdict
            Ran          = $ran
            ParentCommit = $parentCommit
            SourcesHash  = $hash.Digest
        }
        $rFindings = @($adapterResult.findings)
        if ($rFindings.Count -gt 0) { $receiptArgs.Findings = $rFindings }
        $rArtifacts = @($adapterResult.artifacts)
        if ($rArtifacts.Count -gt 0) { $receiptArgs.Artifacts = $rArtifacts }
        if ($lockDecision) { $receiptArgs.LockDecision = $lockDecision }

        $receipt = New-ArchTestReceipt @receiptArgs
        $outcome = Get-ArchGateOutcome -Maturity $maturity -Verdict $verdict -Ran $ran -Adapter $adapter

        $receiptPath = Resolve-ArchReceiptPath -ReceiptRoot $receiptRoot -ContractId $contractId
        if (-not $WhatIf) {
            Write-ArchTestReceiptFile -Receipt $receipt -Path $receiptPath
        }

        $results.Add([pscustomobject]@{
                ContractId  = $contractId
                Adapter     = $adapter
                Maturity    = $maturity
                Verdict     = $verdict
                Outcome     = $outcome
                SourcesHash = $hash.Digest
                ReceiptPath = $receiptPath
                Wrote       = (-not $WhatIf)
            })
    }

    return [pscustomobject]@{
        ParentCommit = $parentCommit
        ReceiptDir   = $receiptRoot
        Checks       = @($results)
        Blocked      = @($results | Where-Object { $_.Outcome -eq 'block' }).Count
        Warned       = @($results | Where-Object { $_.Outcome -eq 'warn' }).Count
        Passed       = @($results | Where-Object { $_.Outcome -eq 'pass' }).Count
    }
}

# Run main only when invoked directly (not dot-sourced for its functions). When a script is dot-sourced
# ('. script.ps1') PowerShell sets InvocationName to '.', which reliably distinguishes it from -File/&.
if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { throw 'ConfigPath is required when running this script directly.' }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path }
    $summary = Invoke-ArchTests -ConfigPath $ConfigPath -RepoRoot $RepoRoot -ReceiptDir $ReceiptDir -AdapterRoot $AdapterRoot -ProviderRoot $ProviderRoot -WhatIf:$WhatIf
    $summary | ConvertTo-Json -Depth 12
    if ($summary.Blocked -gt 0) { exit 1 }
    exit 0
}
