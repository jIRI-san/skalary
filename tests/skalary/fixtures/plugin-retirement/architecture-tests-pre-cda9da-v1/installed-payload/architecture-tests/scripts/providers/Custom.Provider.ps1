#requires -Version 7.0
<#
.SYNOPSIS
Default `custom` semantic-eval provider (REQ-10) — copilot-CLI LLM-as-judge over an architecture contract.

.DESCRIPTION
Reads the human-owned contract prose (UNTRUSTED), wraps it in a per-invocation GUID-suffixed boundary
fence with boundary-token neutralization, asks a copilot judge for a STRICT-JSON verdict, and maps it onto
the strict provider contract { status; findings[]; artifacts[] }. Advisory always: it never blocks the gate.

Skip-not-error is the theme: an absent dedicated credential, an absent copilot CLI, or an unreadable
contract all report `skip-absent-toolchain` (or `error` only on a genuine failure) — never a false pass.
The contract text is data, never executed; the judge is instructed to treat it as untrusted.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source the seam for its shared hardening + credential helpers when invoked standalone.
if (-not (Get-Command New-SemanticFence -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'SemanticEvalProvider.ps1')
}

function Protect-SemanticSecret {
    <#
    .SYNOPSIS
    Redacts a known token and common GitHub token shapes out of diagnostic text before it reaches findings.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowNull()][AllowEmptyString()][string]$Token
    )
    $t = $Text
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $t = $t.Replace($Token, '[REDACTED]') }
    return [regex]::Replace($t, '(gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+)', '[REDACTED]')
}

function Invoke-SemanticCopilotJudge {
    <#
    .SYNOPSIS
    Runs the copilot CLI judge on a prepared prompt and strict-parses its verdict. Skip when copilot absent.

    .DESCRIPTION
    Isolated so the network/LLM call is the only non-deterministic surface; callers and tests can exercise
    prompt construction + verdict parsing without a live model.

    Deny-by-default: the judge is a pure text-in / JSON-out reviewer, so it runs WITHOUT `--allow-all`. With
    `--no-ask-user` and no pre-approval, any tool call the model attempts under attacker-influenced prose is
    denied rather than auto-executed — the untrusted contract can never drive host tool/shell/file execution.
    NB: this containment is an explicit contract with the copilot CLI's deny-by-default behavior; a future CLI
    that auto-approves tools without `--allow-all` would weaken it. Pin/verify a trusted CLI version, and run a
    restricted/sandboxed judge, before treating this as containment for a hostile repo.

    The dedicated credential token (if any) is injected into the CHILD process environment only (never the
    parent env, never findings/receipts). The call is bounded by TimeoutSeconds via a real child process; a
    hang is killed and mapped to advisory `error`. A missing copilot CLI is `skip-absent-toolchain`; a
    non-zero exit or unparseable/out-of-taxonomy output is `error` (advisory), never a pass.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [AllowNull()][AllowEmptyString()][string]$Token,
        [int]$TimeoutSeconds = 120
    )

    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ status = 'skip-absent-toolchain'; findings = @([pscustomobject]@{ severity = 'info'; message = 'semantic-eval skipped: copilot CLI not present.' }) }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'copilot'
    # NB: no --allow-all (deny-by-default tool policy); --no-ask-user avoids interactive prompts.
    foreach ($a in @('-p', $Prompt, '--no-ask-user', '--silent')) { [void]$psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        # Child-only credential scope: the dedicated token authenticates this process, then dies with it.
        $psi.Environment['COPILOT_GITHUB_TOKEN'] = $Token
        $psi.Environment['GH_TOKEN'] = $Token
    }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $stdout = ''
    $stderr = ''
    $exit = 0
    try {
        [void]$proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill($true) } catch { }
            return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval judge timed out after ${TimeoutSeconds}s (killed)." }) }
        }
        $proc.WaitForExit()
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        $exit = $proc.ExitCode
    }
    catch {
        return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval judge invocation failed: $($_.Exception.Message)" }) }
    }
    finally {
        $proc.Dispose()
    }

    if ($exit -ne 0) {
        $tail = Protect-SemanticSecret -Text ([string]$stderr) -Token $Token
        if ($tail.Length -gt 500) { $tail = $tail.Substring($tail.Length - 500) }
        return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval judge exited ${exit}: $($tail.Trim())" }) }
    }

    try {
        $verdict = ConvertFrom-SemanticVerdict -Json $stdout
        return [pscustomobject]@{ status = $verdict.status; findings = @($verdict.findings) }
    }
    catch {
        return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval verdict rejected (strict-JSON gate): $($_.Exception.Message)" }) }
    }
}

function Invoke-CustomProvider {
    <#
    .SYNOPSIS
    The `custom` provider entrypoint. Returns { status; findings[]; artifacts[] } (advisory).
    #>
    param(
        [Parameter(Mandatory)][string]$ContractPath,
        [Parameter(Mandatory)][string]$TargetRoot,
        [string]$ConfigPath,
        [string]$CredentialTarget,
        [int]$TimeoutSeconds = 120
    )

    if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
        return [pscustomobject]@{ status = 'error'; findings = @([pscustomobject]@{ severity = 'error'; message = "semantic-eval: contract not found at '$ContractPath'." }); artifacts = @() }
    }

    # Dedicated credential target — skip (never error) when unconfigured/missing.
    $cred = Resolve-SemanticCredential -Target $CredentialTarget
    if ($cred.skip) {
        return [pscustomobject]@{ status = 'skip-absent-toolchain'; findings = @([pscustomobject]@{ severity = 'info'; message = $cred.reason }); artifacts = @() }
    }

    $contractText = Get-Content -LiteralPath $ContractPath -Raw
    $targetSummary = "Target root: $TargetRoot"
    $fence = New-SemanticFence
    $prompt = Format-SemanticContractPrompt -ContractText $contractText -TargetSummary $targetSummary -Fence $fence

    # Guard the CLI arg-length limit (~32k chars on Windows): an oversized prompt would throw a Win32Exception,
    # so skip with an actionable note rather than crash the advisory call.
    if ($prompt.Length -gt 28000) {
        return [pscustomobject]@{ status = 'skip-absent-toolchain'; findings = @([pscustomobject]@{ severity = 'info'; message = "semantic-eval skipped: contract prompt ($($prompt.Length) chars) exceeds the judge input ceiling (28000)." }); artifacts = @() }
    }

    $judged = Invoke-SemanticCopilotJudge -Prompt $prompt -Token $cred.token -TimeoutSeconds $TimeoutSeconds
    return [pscustomobject]@{ status = $judged.status; findings = @($judged.findings); artifacts = @() }
}
