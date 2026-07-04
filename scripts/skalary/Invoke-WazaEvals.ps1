#requires -Version 7.0
<#
.SYNOPSIS
    Opt-in Tier-2 LLM eval runner (plan 0f666f): provisions tooling, resolves a token,
    discovers waza specs, runs them, and aggregates results. Never wired into the
    always-on build/test/eval gates.
.DESCRIPTION
    Orchestration order:
      1. Ensure-EvalTools — provision/verify the pinned toolchain; prepend resolved dirs to PATH.
      2. Resolve-EvalToken — source a Copilot token into the process env for the waza child.
      3. Discover plugins/<name>/evals/waza/eval.yaml (optionally filtered by -Plugin /
         -ChangedOnly). For each spec, run every applicable MODE: a functional `waza run`
         when the spec declares `tasks:`, AND a safety `waza adversarial --spec ... --skill
         <name> --model <model> --on-unsafe-outcome fail` when it declares an `adversarial:`
         block. A spec with both runs BOTH (they are separate signals and must not share a
         results column).
      4. Aggregate exit codes and print a summary + rough token/wall-clock estimate.

    Durable-token exclusion (REQ-22): the ADVERSARIAL mode runs only with a provably short-lived
    token (the `gh` OAuth source). Any other source — an ambient env PAT or a durable
    Credential-Manager PAT — is never exposed to an adversarial/injection run; that mode is
    skipped with a clear message, while the spec's functional mode still runs normally.

    Executed-count invariant (REQ-18): a requested run that executed ZERO evals (everything
    skipped or empty discovery) is a distinct non-green outcome (exit 3), never a green exit 0.

    Dot-sourceable: the discovery / decision / argument-building helpers are pure and
    side-effect-free so tests exercise them offline. The live orchestrator runs only when
    invoked as a script.
.PARAMETER RepoRoot
    Repository root. Defaults to two levels up from this script.
.PARAMETER Plugin
    Only run specs for this plugin (directory name under plugins/).
.PARAMETER Case
    Only run this task/case id within each spec (passed to `waza run --task`).
.PARAMETER ChangedOnly
    Only run specs for plugins with changes vs the git working tree / index.
.PARAMETER Quick
    Force a single trial per task (`--trials 1`) for fast iteration.
.PARAMETER Approve
    Non-interactive approval for any tool installs Ensure-EvalTools needs.
.OUTPUTS
    [pscustomobject] with Executed, Failed, Skipped, Outcome, ExitCode, and RunDir.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$Plugin,
    [string]$Case,
    [switch]$ChangedOnly,
    [switch]$Quick,
    [switch]$Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WazaEvalSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginsRoot,

        [string]$Plugin
    )

    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        return @()
    }

    $specs = Get-ChildItem -LiteralPath $PluginsRoot -Recurse -File -Filter 'eval.yaml' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Replace('\', '/') -match '/plugins/(?<plugin>[^/]+)/evals/waza/eval\.yaml$' } |
        Sort-Object FullName

    if (-not [string]::IsNullOrWhiteSpace($Plugin)) {
        $specs = $specs | Where-Object {
            $_.FullName.Replace('\', '/') -match "/plugins/$([regex]::Escape($Plugin))/evals/waza/eval\.yaml$"
        }
    }

    return @($specs | ForEach-Object { $_.FullName })
}

function Get-PluginFromSpecPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path.Replace('\', '/') -match '/plugins/(?<plugin>[^/]+)/evals/waza/eval\.yaml$') {
        return [string]$Matches.plugin
    }
    return 'unknown'
}

function Test-WazaSpecIsAdversarial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    # A top-level `adversarial:` key (not indented, not commented) marks an adversarial spec.
    $lines = Get-Content -LiteralPath $Path
    foreach ($line in $lines) {
        if ($line -match '^adversarial:\s*($|\S)') {
            return $true
        }
    }
    return $false
}

function Test-WazaSpecHasTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    # A top-level `tasks:` (inline list or block) or `tasks_from:` marks functional tasks.
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^tasks:\s*($|\S|\[)') {
            return $true
        }
        if ($line -match '^tasks_from:\s*\S') {
            return $true
        }
    }
    return $false
}

function Get-WazaSpecExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$HasTasks,

        [Parameter(Mandatory)]
        [bool]$HasAdversarial
    )

    # Functional and adversarial are distinct signals; a spec declaring both runs both.
    $modes = [System.Collections.Generic.List[string]]::new()
    if ($HasTasks) { $modes.Add('run') }
    if ($HasAdversarial) { $modes.Add('adversarial') }
    return @($modes)
}

function Get-WazaSpecSkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    # Top-level `skill: <name>` — needed because `waza adversarial --spec` does NOT inherit
    # the spec's skill (it defaults to the `adversarial-target` stub) and must be told `--skill`.
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^skill:\s*(?<v>\S.*?)\s*$') {
            return [string]$Matches.v.Trim().Trim('"', "'")
        }
    }
    return $null
}

function Get-WazaSpecModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    # `config.model` — `waza adversarial --spec` does NOT inherit it (defaults to its own
    # pinned model), so the runner forwards it via `--model` to keep the adversarial run on
    # the same pinned model as the functional run. `judge_model:` is deliberately not matched.
    $inConfig = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^config:\s*$') { $inConfig = $true; continue }
        if ($inConfig -and $line -match '^\S') { $inConfig = $false }
        if ($inConfig -and $line -match '^\s+model:\s*(?<v>\S.*?)\s*$') {
            return [string]$Matches.v.Trim().Trim('"', "'")
        }
    }
    return $null
}

function Resolve-SpecTokenSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$IsAdversarial,

        [AllowEmptyString()]
        [AllowNull()]
        [string]$BaseSource = '',

        [AllowEmptyString()]
        [AllowNull()]
        [string]$BaseToken = ''
    )

    if ([string]::IsNullOrWhiteSpace($BaseToken)) {
        return [pscustomobject]@{ Source = $BaseSource; Token = $null; ShouldSkip = $true; Reason = 'no token resolved' }
    }

    # REQ-22: adversarial/injection runs must only ever use a provably short-lived token.
    # `gh` (OAuth, auto-refresh) is the only source we can prove is short-lived. `ambient`
    # ($env:COPILOT_GITHUB_TOKEN / $env:GH_TOKEN) is commonly a durable PAT, and `credmanager*`
    # is always a durable PAT — so this is an ALLOW-LIST (gh only), not a credmanager deny-list.
    if ($IsAdversarial -and ($BaseSource -ne 'gh')) {
        $reason = "adversarial spec excluded: token source '$BaseSource' is not a provably " +
        "short-lived 'gh' token; supply one via 'gh auth login' (REQ-22)."
        return [pscustomobject]@{ Source = $BaseSource; Token = $null; ShouldSkip = $true; Reason = $reason }
    }

    return [pscustomobject]@{ Source = $BaseSource; Token = $BaseToken; ShouldSkip = $false; Reason = $null }
}

function Get-ExecutedOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Executed,

        [Parameter(Mandatory)]
        [int]$Failed,

        [int]$Skipped = 0
    )

    # Executed-count invariant: zero executed evals is a distinct non-green outcome.
    if ($Executed -le 0) {
        $reason = if ($Skipped -gt 0) {
            "no evals executed ($Skipped skipped); nothing ran."
        }
        else {
            'no evals executed; discovery matched nothing.'
        }
        return [pscustomobject]@{ Outcome = 'red'; ExitCode = 3; Reason = $reason }
    }

    if ($Failed -gt 0) {
        return [pscustomobject]@{ Outcome = 'red'; ExitCode = 1; Reason = "$Failed of $Executed executed eval(s) failed." }
    }

    return [pscustomobject]@{ Outcome = 'green'; ExitCode = 0; Reason = "$Executed eval(s) passed." }
}

function New-WazaRunArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SpecPath,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [switch]$IsAdversarial,

        [switch]$Quick,

        [string]$Case,

        [string]$Skill,

        [string]$Model
    )

    if ($IsAdversarial) {
        # `waza adversarial --spec` reads packs + on_unsafe_outcome from the spec but does NOT
        # inherit its skill or model, so forward them explicitly. Output is a single JSON file
        # (no --output-dir on adversarial). --trials/--task do not apply.
        $advArgs = [System.Collections.Generic.List[string]]::new()
        $advArgs.Add('adversarial')
        $advArgs.Add('--spec')
        $advArgs.Add($SpecPath)
        if (-not [string]::IsNullOrWhiteSpace($Skill)) {
            $advArgs.Add('--skill')
            $advArgs.Add($Skill)
        }
        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            $advArgs.Add('--model')
            $advArgs.Add($Model)
        }
        $advArgs.Add('--on-unsafe-outcome')
        $advArgs.Add('fail')
        $advArgs.Add('--output')
        $advArgs.Add((Join-Path $OutputDir 'adversarial.json'))
        return $advArgs.ToArray()
    }

    $runArgs = [System.Collections.Generic.List[string]]::new()
    $runArgs.Add('run')
    $runArgs.Add($SpecPath)
    $runArgs.Add('--output-dir')
    $runArgs.Add($OutputDir)
    if ($Quick) {
        $runArgs.Add('--trials')
        $runArgs.Add('1')
    }
    if (-not [string]::IsNullOrWhiteSpace($Case)) {
        $runArgs.Add('--task')
        $runArgs.Add($Case)
    }
    return $runArgs.ToArray()
}

function Select-ChangedPlugin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChangedPaths
    )

    $plugins = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $ChangedPaths) {
        if ($path.Replace('\', '/') -match '(^|/)plugins/(?<plugin>[^/]+)/') {
            $name = [string]$Matches.plugin
            if (-not $plugins.Contains($name)) {
                $plugins.Add($name)
            }
        }
    }
    return @($plugins)
}

function Get-ChangedPluginName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    Push-Location $RepoRoot
    try {
        $changed = @(& git diff --name-only 2>$null) +
        @(& git diff --name-only --cached 2>$null) +
        @(& git ls-files --others --exclude-standard 2>$null)
    }
    finally {
        Pop-Location
    }
    return Select-ChangedPlugin -ChangedPaths @($changed)
}

function Get-WazaCostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SpecCount
    )

    # Rough signal only (PoC measured ~3 premium requests + ~40s per task/judge pair).
    $requests = $SpecCount * 3
    $minutes = [math]::Ceiling(($SpecCount * 45) / 60.0)
    return "~$requests premium request(s), ~$minutes min (rough; actual depends on tasks/trials)."
}

function Invoke-WazaEvals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$Plugin,

        [string]$Case,

        [switch]$ChangedOnly,

        [switch]$Quick,

        [switch]$Approve
    )

    . (Join-Path $PSScriptRoot 'Ensure-EvalTools.ps1')
    . (Join-Path $PSScriptRoot 'Resolve-EvalToken.ps1')

    $tools = Invoke-EnsureEvalTools -RepoRoot $RepoRoot -Approve:$Approve
    foreach ($dir in @($tools.ResolvedPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $dir) {
            $env:PATH = $dir + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }

    $baseToken = Resolve-EvalToken -RepoRoot $RepoRoot

    $pluginsRoot = Join-Path $RepoRoot 'plugins'
    $specs = Get-WazaEvalSpec -PluginsRoot $pluginsRoot -Plugin $Plugin

    if ($ChangedOnly) {
        $changedPlugins = Get-ChangedPluginName -RepoRoot $RepoRoot
        $specs = @($specs | Where-Object { $changedPlugins -contains (Get-PluginFromSpecPath -Path $_) })
    }

    $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $runDir = Join-Path $RepoRoot (Join-Path 'tests/evals/output' $stamp)
    [void](New-Item -ItemType Directory -Path $runDir -Force)

    Write-Host ("Discovered {0} waza spec(s). Estimate: {1}" -f @($specs).Count, (Get-WazaCostEstimate -SpecCount @($specs).Count))

    $executed = 0
    $failed = 0
    $skipped = 0

    foreach ($spec in $specs) {
        $pluginName = Get-PluginFromSpecPath -Path $spec
        $hasTasks = Test-WazaSpecHasTasks -Path $spec
        $hasAdversarial = Test-WazaSpecIsAdversarial -Path $spec
        $modes = Get-WazaSpecExecutionPlan -HasTasks $hasTasks -HasAdversarial $hasAdversarial

        if (@($modes).Count -eq 0) {
            $skipped++
            Write-Host ("  SKIP {0}: spec declares neither tasks nor an adversarial block." -f $pluginName) -ForegroundColor Yellow
            continue
        }

        $specSkill = Get-WazaSpecSkill -Path $spec
        $specModel = Get-WazaSpecModel -Path $spec

        foreach ($mode in $modes) {
            $isAdversarial = ($mode -eq 'adversarial')
            $tokenChoice = Resolve-SpecTokenSource -IsAdversarial $isAdversarial -BaseSource ([string]$baseToken.Source) -BaseToken ([string]$baseToken.Token)

            if ($tokenChoice.ShouldSkip) {
                $skipped++
                Write-Host ("  SKIP {0} ({1}): {2}" -f $pluginName, $mode, $tokenChoice.Reason) -ForegroundColor Yellow
                continue
            }

            # Segregated child-process token for this run only.
            $env:COPILOT_GITHUB_TOKEN = $tokenChoice.Token
            $env:GH_TOKEN = $tokenChoice.Token

            $specOut = Join-Path $runDir (Join-Path $pluginName $mode)
            [void](New-Item -ItemType Directory -Path $specOut -Force)
            $wazaArgs = New-WazaRunArgument -SpecPath $spec -OutputDir $specOut -IsAdversarial:$isAdversarial -Quick:$Quick -Case $Case -Skill $specSkill -Model $specModel

            Write-Host ("  RUN  {0} ({1})" -f $pluginName, $mode)
            # A non-zero waza exit is an expected outcome (failing evals, adversarial --on-unsafe-outcome fail).
            # Guard against $PSNativeCommandUseErrorActionPreference turning that into a terminating error
            # under $ErrorActionPreference='Stop', which would abort the REQ-18 aggregation loop.
            $prevNativePref = if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference } else { $null }
            $PSNativeCommandUseErrorActionPreference = $false
            try {
                # Merge waza's streams to the host so its console output does NOT leak into
                # this function's output stream (which would make the returned object an array
                # and break `$result.ExitCode` at the call site).
                & waza @wazaArgs 2>&1 | Out-Host
                $exit = $LASTEXITCODE
            }
            finally {
                $PSNativeCommandUseErrorActionPreference = $prevNativePref
            }
            $executed++
            if ($exit -ne 0) {
                $failed++
                Write-Host ("  FAIL {0} ({1}): waza exit {2}" -f $pluginName, $mode, $exit) -ForegroundColor Red
            }
        }
    }

    $outcome = Get-ExecutedOutcome -Executed $executed -Failed $failed -Skipped $skipped

    Write-Host ''
    Write-Host 'Waza eval summary:' -ForegroundColor Cyan
    Write-Host "  executed: $executed"
    Write-Host "  failed:   $failed" -ForegroundColor Red
    Write-Host "  skipped:  $skipped" -ForegroundColor Yellow
    Write-Host "  outcome:  $($outcome.Outcome) ($($outcome.Reason))"
    Write-Host "  run dir:  $runDir"

    return [pscustomobject]@{
        Executed = $executed
        Failed = $failed
        Skipped = $skipped
        Outcome = $outcome.Outcome
        ExitCode = $outcome.ExitCode
        RunDir = $runDir
    }
}

# Execute only when run as a script (not when dot-sourced for testing).
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-WazaEvals -RepoRoot $RepoRoot -Plugin $Plugin -Case $Case -ChangedOnly:$ChangedOnly -Quick:$Quick -Approve:$Approve
    exit $result.ExitCode
}
