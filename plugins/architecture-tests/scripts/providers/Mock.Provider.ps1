#requires -Version 7.0
<#
.SYNOPSIS
Trivial `mock`/`null` semantic-eval provider (REQ-10) — a deterministic second implementation.

.DESCRIPTION
Proves the provider seam is genuinely swappable with a second implementation that shares NO backend with
the `custom` provider: it uses no credential and calls no LLM. It reads the contract prose (UNTRUSTED),
neutralizes any boundary sentinel through the shared hardening helper (so even the mock cannot be used to
smuggle a fence breakout), and returns a fixed advisory `pass`. Deterministic and side-effect-free, so it
is safe to run in the always-on structural evals.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source the seam for its shared hardening helpers when invoked standalone.
if (-not (Get-Command New-SemanticFence -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'SemanticEvalProvider.ps1')
}

function Invoke-MockProvider {
    <#
    .SYNOPSIS
    The `mock`/`null` provider entrypoint. Returns a deterministic advisory { status; findings[]; artifacts[] }.
    #>
    param(
        [Parameter(Mandatory)][string]$ContractPath,
        [Parameter(Mandatory)][string]$TargetRoot,
        [string]$ConfigPath,
        [string]$CredentialTarget
    )

    if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
        return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval (mock): contract not found at '$ContractPath'." }); artifacts = @() }
    }

    # Even the mock routes untrusted prose through the boundary-token neutralizer before echoing it.
    $fence = New-SemanticFence
    $contractText = Get-Content -LiteralPath $ContractPath -Raw
    $safe = Protect-SemanticBoundaryToken -Text $contractText -Fence $fence
    $preview = if ($safe.Length -gt 80) { $safe.Substring(0, 80) } else { $safe }

    return [pscustomobject]@{
        status    = 'pass'
        findings  = @([pscustomobject]@{ severity = 'info'; message = "mock semantic-eval provider (deterministic; no credential, no LLM). Contract preview: $preview" })
        artifacts = @()
    }
}
