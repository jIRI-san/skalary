#requires -Version 7.0
<#
.SYNOPSIS
    Opt-in Tier-2 LLM eval runner: provisions tooling, resolves a token, discovers one
    explicitly selected plugin's waza spec, runs it, and aggregates results. Skill execution
    uses the generated primary-model-low binding; only subjective tasks use the primary-model-mid prompt grader. Focused validation,
    package scripts, and ordinary workflows never invoke this premium path.
.DESCRIPTION
    Orchestration order:
      1. Validate one explicit -Plugin and any exact -Case selector without side effects.
      2. Ensure-EvalTools — provision/verify the pinned toolchain; prepend resolved dirs to PATH.
      3. Resolve-EvalToken — source a Copilot token into the process env for the waza child.
      4. Discover its evals/waza/eval.yaml. For each
         spec, run every applicable MODE: a functional `waza run`
         when the spec declares `tasks:`, AND a safety `waza adversarial --spec ... --skill
         <name> --model <model> --on-unsafe-outcome fail` when it declares an `adversarial:`
         block. A spec with both runs BOTH (they are separate signals and must not share a
         results column) unless one exact functional `-Case` was selected.
      5. Aggregate exit codes and print a summary + rough token/wall-clock estimate.

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
    Exact declared task id. Rejects missing or ambiguous ids before provisioning, authentication,
    or output creation; selecting a case runs only its functional spec mode.
.PARAMETER Quick
    Force a single trial per task (`--trials 1`). With -Case, runs exactly one functional case and one trial.
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

function Assert-WazaFocusedScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Plugin,
        [switch]$ChangedOnly
    )

    if ($ChangedOnly) {
        throw 'Waza requires one explicit -Plugin; -ChangedOnly is not a valid premium scope.'
    }
    if ([string]::IsNullOrWhiteSpace($Plugin) -or $Plugin -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
        throw 'Waza requires one explicit lowercase -Plugin directory name.'
    }
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Repository root does not exist: '$root'."
    }
    $pluginRoot = [System.IO.Path]::GetFullPath((Join-Path $root (Join-Path 'plugins' $Plugin)))
    $relative = [System.IO.Path]::GetRelativePath($root, $pluginRoot)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::Ordinal) -or
        -not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
        throw "Selected plugin does not exist inside the repository: '$Plugin'."
    }
    $spec = Join-Path $pluginRoot 'evals/waza/eval.yaml'
    $cursor = $root
    $specRelative = [System.IO.Path]::GetRelativePath($root, $spec)
    foreach ($segment in $specRelative.Split(
            [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
            [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { break }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Selected plugin must not traverse a link or reparse point: '$cursor'."
        }
    }
    if (-not (Test-Path -LiteralPath $spec -PathType Leaf)) {
        throw "Selected plugin has no Waza spec: '$Plugin'."
    }
    $outputCursor = $root
    foreach ($segment in @('tests', 'evals', 'output')) {
        $outputCursor = Join-Path $outputCursor $segment
        $item = Get-Item -LiteralPath $outputCursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { break }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Waza output must not traverse a link or reparse point: '$outputCursor'."
        }
    }
    return $pluginRoot
}

function Get-WazaEvalSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginsRoot,

        [Parameter(Mandatory)]
        [string]$Plugin
    )

    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        return @()
    }

    $spec = Join-Path $PluginsRoot (Join-Path $Plugin 'evals/waza/eval.yaml')
    if (-not (Test-Path -LiteralPath $spec -PathType Leaf)) { return @() }
    return @((Get-Item -LiteralPath $spec).FullName)
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

function Get-WazaTaskPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SpecPath
    )

    if (-not (Test-Path -LiteralPath $SpecPath -PathType Leaf)) {
        throw "Selected Waza spec does not exist: '$SpecPath'."
    }

    $taskPatterns = [System.Collections.Generic.List[string]]::new()
    $inTasks = $false
    $foundTasks = $false
    foreach ($line in Get-Content -LiteralPath $SpecPath) {
        if ($line -match '^tasks_from:') {
            throw "Exact -Case selection requires explicit task-file paths in '$SpecPath'; tasks_from is unsupported."
        }
        if ($line -match '^tasks:\s*(?<inline>.*)$') {
            if ($foundTasks) {
                throw "Selected Waza spec declares tasks more than once: '$SpecPath'."
            }
            $foundTasks = $true
            $inline = [string]$Matches.inline
            if (-not [string]::IsNullOrWhiteSpace($inline)) {
                if ($inline.Trim() -eq '[]') { return @() }
                throw "Exact -Case selection requires a block of explicit task-file paths in '$SpecPath'."
            }
            $inTasks = $true
            continue
        }
        if (-not $inTasks) { continue }
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') { continue }
        if ($line -match '^\S') {
            $inTasks = $false
            continue
        }
        if ($line -notmatch '^\s+-\s*(?<path>[^#]+?)\s*(?:#.*)?$') {
            throw "Exact -Case selection found an unsupported task declaration in '$SpecPath'."
        }
        $taskPatterns.Add([string]$Matches.path.Trim().Trim('"', "'"))
    }

    if (-not $foundTasks) {
        throw "Exact -Case selection requires an explicit tasks block in '$SpecPath'."
    }

    $specDirectory = [System.IO.Path]::GetFullPath((Split-Path -Parent $SpecPath))
    $pathComparer = if ($IsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $resolvedPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($pattern in $taskPatterns) {
        if ([string]::IsNullOrWhiteSpace($pattern) -or [System.IO.Path]::IsPathRooted($pattern)) {
            throw "Waza task path must be relative to its spec: '$pattern'."
        }
        $segments = @($pattern.Replace('\', '/').Split(
            [char[]]@('/'),
            [System.StringSplitOptions]::RemoveEmptyEntries
        ))
        if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '..' }).Count -gt 0) {
            throw "Waza task path must stay inside its spec directory: '$pattern'."
        }
        $directorySegments = @($segments | Select-Object -SkipLast 1)
        $filePattern = [string]$segments[-1]
        if (@($directorySegments | Where-Object { $_ -match '[*?\[]' }).Count -gt 0) {
            throw "Waza task wildcards are only supported in the file name: '$pattern'."
        }

        $taskDirectory = $specDirectory
        foreach ($segment in $directorySegments) {
            $taskDirectory = Join-Path $taskDirectory $segment
            $directory = Get-Item -LiteralPath $taskDirectory -Force -ErrorAction SilentlyContinue
            if ($null -eq $directory -or $directory -isnot [System.IO.DirectoryInfo]) {
                throw "Waza task directory does not exist: '$taskDirectory'."
            }
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Waza task path must not traverse a link or reparse point: '$taskDirectory'."
            }
        }

        $wildcard = [System.Management.Automation.WildcardPattern]::new(
            $filePattern, [System.Management.Automation.WildcardOptions]::CultureInvariant
        )
        $matches = @(Get-ChildItem -LiteralPath $taskDirectory -File -Force |
            Where-Object { $wildcard.IsMatch($_.Name) })
        foreach ($file in $matches) {
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Waza task file must not be a link or reparse point: '$($file.FullName)'."
            }
            [void]$resolvedPaths.Add([System.IO.Path]::GetFullPath($file.FullName))
        }
    }
    return @($resolvedPaths | Sort-Object -Culture ([cultureinfo]::InvariantCulture))
}

function Get-WazaTaskId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskPath
    )

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $TaskPath) {
        if ($line -match '^id:\s*(?<id>[^#]+?)\s*(?:#.*)?$') {
            $ids.Add([string]$Matches.id.Trim().Trim('"', "'"))
        }
    }
    if ($ids.Count -ne 1 -or $ids[0] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        throw "Waza task must declare exactly one valid top-level id: '$TaskPath'."
    }
    return $ids[0]
}

function Resolve-WazaTaskSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Plugin,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Case
    )

    if ($Case -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        throw 'Waza -Case must be one exact task id token.'
    }
    $specs = @(Get-WazaEvalSpec -PluginsRoot (Join-Path $RepoRoot 'plugins') -Plugin $Plugin)
    if ($specs.Count -ne 1) {
        throw "Exact -Case selection requires exactly one Waza spec for plugin '$Plugin'."
    }

    $taskFiles = @(Get-WazaTaskPaths -SpecPath $specs[0])
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($taskFile in $taskFiles) {
        $id = Get-WazaTaskId -TaskPath $taskFile
        if ($id -ceq $Case) {
            $matches.Add([pscustomobject]@{ Id = $id; Path = $taskFile })
        }
    }
    if ($matches.Count -ne 1) {
        throw "Waza -Case '$Case' must match exactly one declared task; found $($matches.Count)."
    }
    return $matches[0]
}

function Get-WazaSpecExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$HasTasks,

        [Parameter(Mandatory)]
        [bool]$HasAdversarial,

        [switch]$CaseSelected
    )

    if ($CaseSelected) {
        if (-not $HasTasks) {
            throw 'An exact -Case selector requires functional tasks; adversarial-only specs cannot satisfy it.'
        }
        return @('run')
    }

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

    $caseSelected = $PSBoundParameters.ContainsKey('Case')
    [void](Assert-WazaFocusedScope -RepoRoot $RepoRoot -Plugin $Plugin -ChangedOnly:$ChangedOnly)
    if ($caseSelected) {
        [void](Resolve-WazaTaskSelection -RepoRoot $RepoRoot -Plugin $Plugin -Case $Case)
    }

    $priorCopilotToken = [System.Environment]::GetEnvironmentVariable('COPILOT_GITHUB_TOKEN', 'Process')
    $priorGhToken = [System.Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
    try {
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
            $modes = Get-WazaSpecExecutionPlan -HasTasks $hasTasks `
                -HasAdversarial $hasAdversarial -CaseSelected:$caseSelected

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

                $env:COPILOT_GITHUB_TOKEN = $tokenChoice.Token
                $env:GH_TOKEN = $tokenChoice.Token

                $specOut = Join-Path $runDir (Join-Path $pluginName $mode)
                [void](New-Item -ItemType Directory -Path $specOut -Force)
                $wazaArgs = New-WazaRunArgument -SpecPath $spec -OutputDir $specOut -IsAdversarial:$isAdversarial -Quick:$Quick -Case $Case -Skill $specSkill -Model $specModel

                Write-Host ("  RUN  {0} ({1})" -f $pluginName, $mode)
                $prevNativePref = if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference } else { $null }
                $PSNativeCommandUseErrorActionPreference = $false
                try {
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
    finally {
        [System.Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', $priorCopilotToken, 'Process')
        [System.Environment]::SetEnvironmentVariable('GH_TOKEN', $priorGhToken, 'Process')
    }
}

# Execute only when run as a script (not when dot-sourced for testing).
if ($MyInvocation.InvocationName -ne '.') {
    try {
        [void](Assert-WazaFocusedScope -RepoRoot $RepoRoot -Plugin $Plugin -ChangedOnly:$ChangedOnly)
        if ($PSBoundParameters.ContainsKey('Case')) {
            [void](Resolve-WazaTaskSelection -RepoRoot $RepoRoot -Plugin $Plugin -Case $Case)
        }
    }
    catch {
        Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
        exit 12
    }
    $invokeParams = @{
        RepoRoot = $RepoRoot
        Plugin = $Plugin
        ChangedOnly = $ChangedOnly
        Quick = $Quick
        Approve = $Approve
    }
    if ($PSBoundParameters.ContainsKey('Case')) { $invokeParams.Case = $Case }
    $result = Invoke-WazaEvals @invokeParams
    exit $result.ExitCode
}
