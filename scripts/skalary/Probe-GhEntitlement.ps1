#requires -Version 7.0
<#
.SYNOPSIS
    Live entitlement probe for the gh -> Copilot token path (plan 0f666f, gate 1.4).
.DESCRIPTION
    Confirms — on a machine where a human can auth interactively — that a `gh auth token`
    OAuth token actually CARRIES the Copilot entitlement waza's embedded copilot-sdk
    accepts. This is the one gate step that cannot run unattended (browser OAuth), so it
    ships as a repeatable script run once per machine:

      * personal dev box: promote `gh` from "installed" to the proven seamless token source.
      * corp work box (later): re-run under corp SSO to record which orgs are entitled.

    Flow (mirrors Invoke-WazaEvals so the probe proves the REAL path):
      1. Ensure-EvalTools -> prepend resolved tool dirs to PATH. Also locate a gh installed
         but not yet on PATH (common on Windows: winget installs to Program Files without
         adding it to the current session PATH), otherwise Resolve-EvalToken's `Get-Command
         gh` can never see it.
      2. `gh auth login` if gh is present but unauthenticated (interactive; skipped with
         -NonInteractive).
      3. Resolve-EvalToken -> assert the resolved Source is `gh` (the whole point; a
         credmanager/ambient fallback would NOT prove the gh path).
      4. `waza models` -> a valid, entitled token lists >0 models. This is the cheap,
         decisive entitlement signal (no agent execution, ~0 premium requests).
      5. (default) run ONE real cr task (`flag-planted-bug`, --trials 1) end-to-end to prove
         the token drives an actual agent+judge run. Skip with -SkipTask for a models-only
         check.

    The token is sourced into process env by Resolve-EvalToken and is NEVER printed or
    written to the result file.

    Dot-sourceable: the pure decision/format helpers have no side effects so tests exercise
    them offline; the live orchestrator runs only when invoked as a script.
.PARAMETER RepoRoot
    Repository root. Defaults to two levels up from this script.
.PARAMETER SkipTask
    Skip the live cr task; confirm entitlement via `waza models` only (near-zero cost).
.PARAMETER NonInteractive
    Never launch `gh auth login`; fail the probe if gh is not already authenticated. For
    unattended re-verification once a machine is already logged in.
.PARAMETER Approve
    Non-interactive approval for any tool installs Ensure-EvalTools needs.
.OUTPUTS
    [pscustomobject] with Entitled, Source, ModelCount, Account, Host, TaskResult, Reason,
    and ResultPath.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [switch]$SkipTask,
    [switch]$NonInteractive,
    [switch]$Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-GhExecutable {
    [CmdletBinding()]
    param(
        [string[]]$CandidateDir = @()
    )

    # Already on PATH — nothing to do.
    $onPath = Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($onPath) {
        return $onPath.Source
    }

    # Common Windows install locations winget/MSI use without touching the session PATH.
    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $CandidateDir) { if (-not [string]::IsNullOrWhiteSpace($d)) { $dirs.Add($d) } }
    foreach ($d in @(
            (Join-Path $env:ProgramFiles 'GitHub CLI'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI'),
            (Join-Path $env:LOCALAPPDATA 'Programs/GitHub CLI'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($d)) { $dirs.Add($d) }
    }

    $exe = if ($IsWindows) { 'gh.exe' } else { 'gh' }
    foreach ($dir in $dirs) {
        $candidate = Join-Path $dir $exe
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Find-WazaExecutable {
    [CmdletBinding()]
    param(
        [string[]]$CandidateDir = @()
    )

    $onPath = Get-Command -Name waza -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($onPath) {
        return $onPath.Source
    }

    # The manifest's InstallDir tokens (tools/eval-tools.psd1): Windows -> LOCALAPPDATA,
    # Linux/macOS -> HOME/.local/share. Locate a waza already provisioned there but not on PATH.
    $home2 = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { $env:USERPROFILE }
    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $CandidateDir) { if (-not [string]::IsNullOrWhiteSpace($d)) { $dirs.Add($d) } }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $dirs.Add((Join-Path $env:LOCALAPPDATA 'Microsoft/Waza')) }
    if (-not [string]::IsNullOrWhiteSpace($home2)) { $dirs.Add((Join-Path $home2 '.local/share/waza/bin')) }

    $exe = if ($IsWindows) { 'waza.exe' } else { 'waza' }
    foreach ($dir in $dirs) {
        $candidate = Join-Path $dir $exe
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Get-GhEntitlementOutcome {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Source,

        [int]$ModelCount = 0,

        # $null when the live task was skipped; otherwise the waza run exit code.
        [AllowNull()]
        [Nullable[int]]$TaskExit = $null,

        [bool]$RequireGh = $true
    )

    if ($RequireGh -and ($Source -ne 'gh')) {
        $got = if ([string]::IsNullOrWhiteSpace($Source)) { '(none)' } else { $Source }
        return [pscustomobject]@{
            Entitled = $false
            Reason = "resolved token source is '$got', not 'gh' — the gh OAuth path is unproven. Run 'gh auth login' first (or pass -RequireGh:`$false to accept a fallback source)."
        }
    }

    if ($ModelCount -le 0) {
        return [pscustomobject]@{
            Entitled = $false
            Reason = "'waza models' returned no models — the token does not carry a Copilot entitlement copilot-sdk accepts (account/org grant or SSO missing)."
        }
    }

    if ($null -ne $TaskExit -and $TaskExit -ne 0) {
        return [pscustomobject]@{
            Entitled = $false
            Reason = "entitlement present ($ModelCount model(s)) but the live cr task exited $TaskExit — end-to-end run failed."
        }
    }

    $taskNote = if ($null -eq $TaskExit) { 'models-only (task skipped)' } else { 'cr flag-planted-bug passed' }
    return [pscustomobject]@{
        Entitled = $true
        Reason = "gh OAuth token carries Copilot entitlement: $ModelCount model(s) listed; $taskNote."
    }
}

function Format-GhEntitlementTableRow {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Account = '',
        [AllowEmptyString()][string]$GhHost = '',
        [AllowEmptyString()][string]$Source = '',
        [int]$ModelCount = 0,
        [AllowNull()][Nullable[int]]$TaskExit = $null,
        [bool]$Entitled = $false
    )

    $acct = if ([string]::IsNullOrWhiteSpace($Account)) { '(unknown)' } else { $Account }
    $h = if ([string]::IsNullOrWhiteSpace($GhHost)) { 'github.com' } else { $GhHost }
    $task = if ($null -eq $TaskExit) { 'skipped' } elseif ($TaskExit -eq 0) { 'PASS' } else { "FAIL($TaskExit)" }
    $verdict = if ($Entitled) { 'ENTITLED' } else { 'NOT ENTITLED' }
    return "| $acct @ $h | $Source | $ModelCount | $task | $verdict |"
}

function Get-WazaModelCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$JsonText
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) { return 0 }
    try {
        $parsed = $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return 0
    }
    if ($null -eq $parsed) { return 0 }
    # `waza models --json` emits EITHER a bare array OR an object wrapping a `models` array.
    # Anything else (an error/status object like {"error":...}, a scalar, or {}) is NOT a model
    # list and must count as 0 — a fail-CLOSED fallback. A permissive `@($parsed).Count` would
    # score a bogus error object as "1 model", which in -SkipTask mode (no live-task backstop)
    # would falsely report a non-entitled token as ENTITLED.
    if ($parsed -is [System.Array]) { return @($parsed).Count }
    # StrictMode-safe member probe: indexer returns $null when absent, and a scalar
    # (string/number/bool from ConvertFrom-Json) is not a PSCustomObject so it can't wrap models.
    if ($parsed -is [System.Management.Automation.PSCustomObject]) {
        $modelsProp = $parsed.PSObject.Properties['models']
        if ($null -ne $modelsProp) { return @($modelsProp.Value).Count }
    }
    return 0
}

function Invoke-GhEntitlementProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [switch]$SkipTask,

        [switch]$NonInteractive,

        [switch]$Approve
    )

    . (Join-Path $PSScriptRoot 'Ensure-EvalTools.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-EvalToken.ps1')

    # Pre-seed PATH with an already-installed gh / waza that just isn't on the session PATH
    # (common on Windows: winget installs gh to Program Files, the first eval run drops waza
    # under LOCALAPPDATA — neither touches PATH). Doing this BEFORE Ensure-EvalTools means it
    # sees both as present ('ok') instead of prompting to reinstall them.
    $ghExe = Find-GhExecutable
    if ($null -eq $ghExe) {
        throw "gh CLI not found. Install it (winget install --exact --id GitHub.cli) then re-run; the gh token path cannot be probed without it."
    }
    $ghDir = Split-Path -Parent $ghExe
    if (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $ghDir) {
        $env:PATH = $ghDir + [System.IO.Path]::PathSeparator + $env:PATH
    }
    Write-Host "gh: $ghExe"

    $wazaExe = Find-WazaExecutable
    if ($null -ne $wazaExe) {
        $wazaDir = Split-Path -Parent $wazaExe
        if (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $wazaDir) {
            $env:PATH = $wazaDir + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }

    # 1. Provision/verify the toolchain and prepend any additionally resolved tool dirs.
    $tools = Invoke-EnsureEvalTools -RepoRoot $RepoRoot -Approve:$Approve
    foreach ($dir in @($tools.ResolvedPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $dir) {
            $env:PATH = $dir + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }

    # 2. Authenticate interactively if needed.
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if ($NonInteractive) {
            throw "gh is not authenticated and -NonInteractive was set. Run 'gh auth login' first."
        }
        Write-Host 'gh is not authenticated. Launching `gh auth login` (browser OAuth)...' -ForegroundColor Cyan
        & gh auth login
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "gh authentication did not complete. Re-run after 'gh auth login' succeeds."
        }
    }

    # Best-effort account + host for the entitlement record (never the token).
    $account = (& gh api user --jq .login 2>$null | Out-String).Trim()
    $ghHost = 'github.com'
    $statusText = (& gh auth status 2>&1 | Out-String)
    $hostMatch = [regex]::Match($statusText, '(?im)^\s*(?:Logged in to|.*account.*of)\s+(?<h>[^\s]+)')
    if ($hostMatch.Success) { $ghHost = $hostMatch.Groups['h'].Value }

    # 3. Resolve the token and assert it came from gh.
    $resolved = Resolve-EvalToken -RepoRoot $RepoRoot
    $source = [string]$resolved.Source
    Write-Host "resolved token source: $source"

    # 4. Entitlement signal: list models (no agent execution).
    $modelCount = 0
    $sampleModels = @()
    if ($source -eq 'gh') {
        $modelsJson = (& waza models --json --no-update-check 2>$null | Out-String)
        $modelCount = Get-WazaModelCount -JsonText $modelsJson
        if ($modelCount -gt 0) {
            try {
                $parsed = $modelsJson | ConvertFrom-Json
                $arr = if ($parsed -is [System.Array]) { $parsed } elseif ($parsed.PSObject.Properties.Name -contains 'models') { $parsed.models } else { @($parsed) }
                $sampleModels = @($arr | ForEach-Object {
                        if ($_ -is [string]) { $_ }
                        elseif ($_.PSObject.Properties.Name -contains 'id') { $_.id }
                        elseif ($_.PSObject.Properties.Name -contains 'name') { $_.name }
                        else { "$_" }
                    } | Select-Object -First 5)
            }
            catch { $sampleModels = @() }
        }
        Write-Host "waza models: $modelCount available"
    }
    else {
        Write-Host "skipping 'waza models' — token source is '$source', not gh." -ForegroundColor Yellow
    }

    # 5. Optional end-to-end: one real cr task.
    $taskExit = $null
    if (-not $SkipTask -and $source -eq 'gh' -and $modelCount -gt 0) {
        $spec = Join-Path $RepoRoot 'plugins/code-review/evals/waza/eval.yaml'
        $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
        $taskOut = Join-Path $RepoRoot (Join-Path 'tests/evals/output' "gh-probe-$stamp")
        [void](New-Item -ItemType Directory -Path $taskOut -Force)
        Write-Host "running live cr task 'flag-planted-bug' (--trials 1)..." -ForegroundColor Cyan
        $prevNativePref = if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference } else { $null }
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            & waza run $spec --output-dir $taskOut --task flag-planted-bug --trials 1 --no-update-check 2>&1 | Out-Host
            $taskExit = $LASTEXITCODE
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $prevNativePref
        }
    }

    $outcome = Get-GhEntitlementOutcome -Source $source -ModelCount $modelCount -TaskExit $taskExit -RequireGh $true
    $row = Format-GhEntitlementTableRow -Account $account -GhHost $ghHost -Source $source -ModelCount $modelCount -TaskExit $taskExit -Entitled $outcome.Entitled

    $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $resultDir = Join-Path $RepoRoot 'tests/evals/output'
    [void](New-Item -ItemType Directory -Path $resultDir -Force)
    $resultPath = Join-Path $resultDir "gh-entitlement-probe-$stamp.json"
    $result = [pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        entitled = $outcome.Entitled
        source = $source
        account = $account
        host = $ghHost
        modelCount = $modelCount
        sampleModels = $sampleModels
        taskExit = $taskExit
        reason = $outcome.Reason
        tableRow = $row
    }
    # Token never appears in $result — only source name, counts, account.
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM

    Write-Host ''
    Write-Host 'gh -> Copilot entitlement probe:' -ForegroundColor Cyan
    Write-Host ("  entitled:  {0}" -f $outcome.Entitled) -ForegroundColor ($(if ($outcome.Entitled) { 'Green' } else { 'Red' }))
    Write-Host ("  source:    {0}" -f $source)
    Write-Host ("  account:   {0} @ {1}" -f $account, $ghHost)
    Write-Host ("  models:    {0}" -f $modelCount)
    Write-Host ("  task exit: {0}" -f $(if ($null -eq $taskExit) { 'skipped' } else { $taskExit }))
    Write-Host ("  reason:    {0}" -f $outcome.Reason)
    Write-Host ("  result:    {0}" -f $resultPath)
    Write-Host ''
    Write-Host 'Design-note table row (account @ host | source | models | task | verdict):'
    Write-Host "  $row"

    return [pscustomobject]@{
        Entitled = $outcome.Entitled
        Source = $source
        ModelCount = $modelCount
        Account = $account
        Host = $ghHost
        TaskResult = $taskExit
        Reason = $outcome.Reason
        ResultPath = $resultPath
    }
}

# Execute only when run as a script (not when dot-sourced for testing).
if ($MyInvocation.InvocationName -ne '.') {
    $probe = Invoke-GhEntitlementProbe -RepoRoot $RepoRoot -SkipTask:$SkipTask -NonInteractive:$NonInteractive -Approve:$Approve
    if (-not $probe.Entitled) {
        exit 1
    }
    exit 0
}
