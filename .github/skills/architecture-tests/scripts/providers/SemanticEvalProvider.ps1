#requires -Version 7.0
<#
.SYNOPSIS
Semantic-eval provider seam (STUB) for advisory LLM architecture checks.

.DESCRIPTION
Defines the provider contract the runner talks to for semantic (LLM) architecture checks. It is a
loosely-coupled seam so the backend can be the repo's custom eval harness today and, for example, a
waza-driven provider later, without changing the runner. Phase 5.3 fleshes out real providers; at 4.1
this is a shape-only stub that always reports 'skip-absent-toolchain' (advisory, never a false-green).

The provider returns a strict object; arch-note text is treated as UNTRUSTED input and is never executed.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SemanticEvalProvider {
    <#
    .SYNOPSIS
    Runs a semantic-eval provider against a contract + target root.

    .OUTPUTS
    [pscustomobject] with:
      status    : one of pass / fail / skip-absent-toolchain / error (taxonomy-aligned)
      findings  : array of structured advisory findings (empty at 4.1)
      artifacts : array of raw output paths (empty at 4.1)
    #>
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$ContractPath,
        [Parameter(Mandatory)][string]$TargetRoot,
        [string]$ConfigPath
    )

    # Seam only: no provider backend is wired at Phase 4.1. Report absent toolchain honestly.
    return [pscustomobject]@{
        status    = 'skip-absent-toolchain'
        provider  = $ProviderName
        findings  = @()
        artifacts = @()
    }
}
