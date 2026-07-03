#requires -Version 7.0
<#
.SYNOPSIS
    Resolves a Copilot token for waza Tier-2 LLM eval runs (plan 0f666f) and exports it
    to the current process env for the waza child process.
.DESCRIPTION
    waza's embedded copilot-sdk authenticates from COPILOT_GITHUB_TOKEN / GH_TOKEN. This
    resolver SOURCES that token, in precedence order:

      1. gh CLI `gh auth token` (PRIMARY) — seamless OAuth, auto-refresh, no weekly PAT
         regen. Used only when gh is installed AND `gh auth status` reports authenticated.
      2. Ambient COPILOT_GITHUB_TOKEN / GH_TOKEN — CI / explicit-override escape hatch.
      3. Windows Credential Manager targets from .eval.config.json (default copilot-eval
         then copilot-autopilot) — fallback that reuses the token autopilot maintains.
         Windows-only source; skipped elsewhere.
      4. None resolvable → actionable SKIP pointing at `gh auth login` (never a hard fail).

    On success the token is written to $env:COPILOT_GITHUB_TOKEN + $env:GH_TOKEN in THIS
    process only (never persisted to user/machine scope); child processes inherit it.

    Dot-sourceable: defines pure decision + source helpers with no side effects (except the
    orchestrator's env export) so tests can exercise every precedence branch offline.
.PARAMETER RepoRoot
    Repository root. Defaults to two levels up from this script.
.PARAMETER ConfigPath
    Path to .eval.config.json. Defaults to <RepoRoot>/.eval.config.json.
.PARAMETER Interactive
    Allow interactive prompts (e.g. run `gh auth login` when gh is installed but unauthed).
.OUTPUTS
    [pscustomobject] with Source (gh|ambient|credmanager:<target>|$null), Token, ShouldSkip,
    and Reason (set when ShouldSkip).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$ConfigPath,
    [switch]$Interactive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-EvalTokenSource {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$GhToken = '',

        [AllowEmptyString()]
        [string]$AmbientToken = '',

        [AllowEmptyString()]
        [string]$StoreToken = '',

        [AllowEmptyString()]
        [string]$StoreTarget = ''
    )

    # Pure precedence: gh -> ambient -> credential manager -> skip.
    if (-not [string]::IsNullOrWhiteSpace($GhToken)) {
        return [pscustomobject]@{ Source = 'gh'; Token = $GhToken.Trim(); ShouldSkip = $false; Reason = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($AmbientToken)) {
        return [pscustomobject]@{ Source = 'ambient'; Token = $AmbientToken.Trim(); ShouldSkip = $false; Reason = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($StoreToken)) {
        $source = if ([string]::IsNullOrWhiteSpace($StoreTarget)) { 'credmanager' } else { "credmanager:$StoreTarget" }
        return [pscustomobject]@{ Source = $source; Token = $StoreToken.Trim(); ShouldSkip = $false; Reason = $null }
    }

    $reason = "No Copilot token resolved. Run 'gh auth login' (preferred), or set " +
    "COPILOT_GITHUB_TOKEN / GH_TOKEN, or store a PAT in Windows Credential Manager " +
    "(targets: copilot-eval, copilot-autopilot)."
    return [pscustomobject]@{ Source = $null; Token = $null; ShouldSkip = $true; Reason = $reason }
}

function Get-EvalAmbientToken {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_GITHUB_TOKEN)) {
        return $env:COPILOT_GITHUB_TOKEN
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        return $env:GH_TOKEN
    }
    return ''
}

function Get-EvalTokenTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $default = @('copilot-eval', 'copilot-autopilot')
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $default
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 20
    $names = $config.PSObject.Properties.Name

    if ($names -contains 'credentialTargets' -and $config.credentialTargets) {
        $list = @($config.credentialTargets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($list.Count -gt 0) {
            return $list
        }
    }

    if ($names -contains 'credentialTarget' -and -not [string]::IsNullOrWhiteSpace([string]$config.credentialTarget)) {
        return @([string]$config.credentialTarget)
    }

    return $default
}

function Get-EvalGhToken {
    [CmdletBinding()]
    param(
        [switch]$Interactive
    )

    if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) {
        return ''
    }

    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (-not $Interactive) {
            return ''
        }
        Write-Host 'gh is installed but not authenticated. Launching `gh auth login`...'
        & gh auth login
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return ''
        }
    }

    $token = (& gh auth token 2>$null | Out-String).Trim()
    return $token
}

function Get-EvalCredManagerToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets
    )

    $empty = [pscustomobject]@{ Token = ''; Target = $null }

    # Credential Manager is a Windows-only source; skip cleanly elsewhere.
    if (-not $IsWindows) {
        return $empty
    }
    if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
        return $empty
    }

    Import-Module CredentialManager -ErrorAction Stop
    foreach ($target in $Targets) {
        $cred = Get-StoredCredential -Target $target -ErrorAction SilentlyContinue
        if ($cred) {
            $token = $cred.GetNetworkCredential().Password
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                return [pscustomobject]@{ Token = $token; Target = $target }
            }
        }
    }

    return $empty
}

function Resolve-EvalToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ConfigPath,

        [switch]$Interactive
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $RepoRoot '.eval.config.json'
    }

    $ghToken = Get-EvalGhToken -Interactive:$Interactive
    $ambient = Get-EvalAmbientToken
    $targets = Get-EvalTokenTargets -ConfigPath $ConfigPath
    $cred = Get-EvalCredManagerToken -Targets $targets

    $decision = Resolve-EvalTokenSource -GhToken $ghToken -AmbientToken $ambient -StoreToken $cred.Token -StoreTarget ([string]$cred.Target)

    if (-not $decision.ShouldSkip) {
        # Process scope only — never persisted; the waza child inherits it.
        $env:COPILOT_GITHUB_TOKEN = $decision.Token
        $env:GH_TOKEN = $decision.Token
    }

    return $decision
}

# Execute only when run as a script (not when dot-sourced for testing).
if ($MyInvocation.InvocationName -ne '.') {
    $result = Resolve-EvalToken -RepoRoot $RepoRoot -ConfigPath $ConfigPath -Interactive:$Interactive
    if ($result.ShouldSkip) {
        Write-Host $result.Reason -ForegroundColor Yellow
    }
    else {
        Write-Host ("Resolved Copilot token from: {0}" -f $result.Source)
    }
    $result
}
