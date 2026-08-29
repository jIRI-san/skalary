<#
.SYNOPSIS
    Entry point for autonomous plan execution.
.DESCRIPTION
    Validates inputs, runs pre-flight checks, and dispatches to
    the host, container, or sandbox orchestrator.
.PARAMETER PlanSlug
    Plan folder name (e.g. '002-persistent-storage-for-job-data').
.PARAMETER Mode
    Execution scope: 'whole-plan' or 'next-phase'.
.PARAMETER Runtime
    Override runtime from config: 'host', 'container', or 'sandbox'. Uses config value if omitted.
#>
param(
    [Parameter(Mandatory)]
    [string]$PlanSlug,

    [Parameter(Mandatory)]
    [ValidateSet('whole-plan', 'next-phase')]
    [string]$Mode,

    [ValidateSet('host', 'container', 'sandbox')]
    [string]$Runtime,

    [string]$Branch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = git rev-parse --show-toplevel
$ScriptDir = $PSScriptRoot

# --- Validate slug ---
if ($PlanSlug -notmatch '^[a-z0-9-]+$') {
    Write-Error "Invalid plan slug '$PlanSlug'. Must match ^[a-z0-9-]+$."
    exit 1
}
if ($Branch -and (
        $Branch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or
        $Branch.Contains('..') -or $Branch.Contains('//') -or
        $Branch.EndsWith('/') -or $Branch.EndsWith('.') -or
        $Branch.EndsWith('.lock', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Branch.Contains('@{'))) {
    Write-Error "Invalid branch '$Branch'. Use a simple Git ref containing only letters, digits, '.', '_', '/', and '-'."
    exit 1
}

$PlanFolder = Join-Path $RepoRoot "docs/implementation-plans/$PlanSlug"
if (-not (Test-Path (Join-Path $PlanFolder 'plan.md'))) {
    Write-Error "Plan not found: $PlanFolder/plan.md"
    exit 1
}
$PlanPath = Join-Path $PlanFolder 'plan.md'

# --- Hard dependency start-gate (depends-on: 006) ---
$planContent = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8
$requires006DependencyGate = [regex]::IsMatch($planContent, '<!--\s*depends-on:\s*[^>]*\b006\b[^>]*-->', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if ($requires006DependencyGate) {
    $dependencyGateScript = Join-Path $RepoRoot '.github/skills/autopilot/scripts/Test-DependencyPlan006.ps1'
    if (-not (Test-Path -LiteralPath $dependencyGateScript -PathType Leaf)) {
        Write-Error "Missing dependency gate script: $dependencyGateScript"
        exit 1
    }

    Write-Host "Running plan dependency preflight..."
    & $dependencyGateScript -RepoRoot $RepoRoot -PlanPath $PlanPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Plan dependency preflight failed. Resolve 006 dependency contracts before launching autopilot."
        exit 1
    }
    Write-Host "Dependency preflight OK."
}

# --- Load and validate config ---
$ConfigPath = Join-Path $RepoRoot '.autopilot.json'
if (-not (Test-Path $ConfigPath)) {
    Write-Error ".autopilot.json not found - run '/ci' Autonomous to generate it, or create it from .autopilot.json.example."
    exit 1
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Validate required fields
$requiredFields = @('runtime', 'copilotAuth', 'gitProvider', 'gitAuth', 'model', 'context', 'reasoningEffort', 'git', 'timeout', 'maxIterationsPerStep', 'build', 'test')
foreach ($field in $requiredFields) {
    if (-not ($Config.PSObject.Properties.Name -contains $field)) {
        Write-Error "Missing required field '$field' in .autopilot.json"
        exit 1
    }
}

if ($Config.context -notin @('default', 'long_context')) {
    Write-Error "Invalid context '$($Config.context)' in .autopilot.json"
    exit 1
}
if ($Config.reasoningEffort -notin @('low', 'medium', 'high', 'xhigh', 'max')) {
    Write-Error "Invalid reasoningEffort '$($Config.reasoningEffort)' in .autopilot.json"
    exit 1
}

# planTimeout is the whole-run cap; timeout is per phase. A run cap below a single
# phase's budget would kill every run mid-phase, so reject that combination loudly.
$planTimeoutMinutes = 1440
if ($Config.PSObject.Properties.Name -contains 'planTimeout') {
    $planTimeoutMinutes = [int]$Config.planTimeout
    if ($planTimeoutMinutes -lt 1) {
        Write-Error "Invalid planTimeout '$($Config.planTimeout)' in .autopilot.json (must be >= 1)"
        exit 1
    }
    if ($planTimeoutMinutes -lt [int]$Config.timeout) {
        Write-Error "planTimeout ($planTimeoutMinutes m) is below the per-phase timeout ($($Config.timeout) m) in .autopilot.json"
        exit 1
    }
}

# --- Validate build/test commands against allowlist ---
$buildPrefixes = @('dotnet build', 'dotnet publish', 'npm run', 'yarn run', 'pnpm run', 'make', 'cargo build', 'gradle ', 'mvn ')
$testPrefixes = @('dotnet test', 'npm test', 'npm run test', 'yarn test', 'pnpm test', 'make test', 'cargo test', 'gradle test', 'mvn test')

$buildAllowed = $false
foreach ($prefix in $buildPrefixes) {
    if ($Config.build.StartsWith($prefix)) { $buildAllowed = $true; break }
}
if (-not $buildAllowed) {
    Write-Error "Build command '$($Config.build)' does not match allowed prefixes: $($buildPrefixes -join ', ')"
    exit 1
}

$testAllowed = $false
foreach ($prefix in $testPrefixes) {
    if ($Config.test.StartsWith($prefix)) { $testAllowed = $true; break }
}
if (-not $testAllowed) {
    Write-Error "Test command '$($Config.test)' does not match allowed prefixes: $($testPrefixes -join ', ')"
    exit 1
}

# --- Determine runtime ---
$effectiveRuntime = if ($Runtime) { $Runtime } else { $Config.runtime }
Write-Host "Runtime: $effectiveRuntime"

if ($effectiveRuntime -eq 'host' -and $env:AUTOPILOT_DISABLE_HOST -eq 'true') {
    Write-Error "Host runtime disabled via AUTOPILOT_DISABLE_HOST."
    exit 1
}

# --- Docker pre-flight (container mode) ---
if ($effectiveRuntime -eq 'container') {
    Write-Host "Checking Docker daemon..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker info > $null 2>&1
    $dockerExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($dockerExit -ne 0) {
        Write-Error "Docker daemon not available. Start Docker Desktop or switch to host mode."
        exit 1
    }
    Write-Host "Docker OK."
}

# --- Sandbox pre-flight ---
if ($effectiveRuntime -eq 'sandbox') {
    if (-not (Test-Path 'C:\Windows\System32\WindowsSandbox.exe')) {
        Write-Error "Windows Sandbox not available. Enable it: Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'"
        exit 1
    }
    Write-Host "Windows Sandbox OK."
}

# --- Detect partial state ---
$branchName = if ($Branch) { $Branch } else { "feature/$PlanSlug" }
if ($effectiveRuntime -eq 'host') {
    $worktreeRoot = Join-Path (Split-Path $RepoRoot -Parent) "$((Split-Path $RepoRoot -Leaf)).worktrees"
    $worktreePath = Join-Path $worktreeRoot $branchName.Replace('/', '-')
    if (Test-Path $worktreePath) {
        Write-Host ""
        Write-Host "NOTICE: Existing worktree detected at $worktreePath"
        Write-Host "This indicates a previous run. Will resume from current state."
        Write-Host ""
    }
}
else {
    # Check if remote branch exists (container/sandbox mode resume)
    $remoteBranch = git ls-remote --heads origin $branchName 2>$null
    if ($remoteBranch) {
        Write-Host ""
        Write-Host "NOTICE: Remote branch '$branchName' already exists."
        Write-Host "Container will resume from that branch state."
        Write-Host ""
    }
}

# --- Sweep stale env files ---
Write-Host "Sweeping stale env files..."
$envSessionDir = Join-Path $env:LOCALAPPDATA 'autopilot-sessions'
if (Test-Path $envSessionDir) {
    $staleThreshold = (Get-Date).AddHours(-24)
    Get-ChildItem $envSessionDir -Directory | Where-Object { $_.LastWriteTime -lt $staleThreshold } | ForEach-Object {
        Write-Host "  Removing stale session: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Get credentials ---
Write-Host "Fetching credentials..."
$credTarget = switch ($Config.copilotAuth) {
    'pat' { 'copilot-autopilot' }
    'oauth' { 'copilot-cli' }
}
$Token = & (Join-Path $ScriptDir 'get-credential.ps1') -Target $credTarget
if (-not $Token) {
    Write-Error "Failed to retrieve token for target '$credTarget'."
    exit 1
}

$AdoToken = $null
if ($Config.gitProvider -eq 'ado') {
    $AdoToken = & (Join-Path $ScriptDir 'get-credential.ps1') -Target 'ado'
    if (-not $AdoToken) {
        Write-Error "Failed to retrieve ADO token."
        exit 1
    }
}

# --- Validate authentication ---
Write-Host "Validating authentication..."
& (Join-Path $ScriptDir 'validate-auth.ps1') -Config $Config -Token $Token
if ($LASTEXITCODE -ne 0) {
    Write-Error "Authentication validation failed. Run validate-auth.ps1 manually for details."
    exit 1
}
Write-Host "Auth OK."

# --- Dispatch ---
Write-Host ""
Write-Host "=== Launching $effectiveRuntime mode ==="
Write-Host "Plan: $PlanSlug"
Write-Host "Mode: $Mode"
Write-Host "Timeout: $($Config.timeout) minutes/phase"
Write-Host ""

$dispatchParams = @{
    PlanSlug = $PlanSlug
    Mode = $Mode
    Config = $Config
    Token = $Token
    Branch = "feature/$PlanSlug"
    StartBranch = if ($Branch) { $Branch } else { git branch --show-current }
}
# Host mode runs locally and authenticates to git via ambient credentials, so it
# does not accept -AdoToken; only forward the token to container/sandbox runtimes.
if ($AdoToken -and $effectiveRuntime -ne 'host') { $dispatchParams.AdoToken = $AdoToken }

# --- Offline package bundling (container/sandbox only) ---
. (Join-Path $ScriptDir 'autopilot-dispatch.ps1')
$offline = Resolve-OfflinePackagesConfig -Config $Config
$offlineActive = $false
if ($offline.Enabled) {
    if ($effectiveRuntime -eq 'host') {
        Write-Warning "offlinePackages is enabled but runtime is 'host'; offline bundling applies only to container/sandbox. Ignoring."
    }
    else {
        $offlineActive = $true
        Write-Host "Offline package bundling enabled (maxRebundles=$($offline.MaxRebundles))."
    }
}

$orchestratorScript = switch ($effectiveRuntime) {
    'host' { 'launch-host.ps1' }
    'container' { 'launch-container.ps1' }
    'sandbox' { 'launch-sandbox.ps1' }
}
$WorkBranch = "feature/$PlanSlug"
$offlineEcosystems = $offline.Ecosystems

$Launch = {
    param([string]$FeedPath)
    $p = $dispatchParams.Clone()
    if ($FeedPath) { $p.FeedPath = $FeedPath }
    # Orchestrators report via Write-Host and signal via exit code; discard the
    # success stream so the dispatch loop receives only the integer exit code.
    & (Join-Path $ScriptDir $orchestratorScript) @p | Out-Null
    return $LASTEXITCODE
}
$PrepareFeed = {
    $prepArgs = @{ RepoRoot = $RepoRoot }
    if ($offlineEcosystems -and $offlineEcosystems.Count -gt 0) { $prepArgs.Ecosystems = $offlineEcosystems }
    $feed = & (Join-Path $ScriptDir 'prepare-packages.ps1') @prepArgs
    return ($feed | Select-Object -Last 1)
}
$Rebundle = {
    # Re-prep MUST regenerate + commit + push the lockfile before the relaunch
    # clones, so the resumed runtime gets a consistent manifest + lock pair.
    $prepArgs = @{ RepoRoot = $RepoRoot; Branch = $WorkBranch }
    if ($offlineEcosystems -and $offlineEcosystems.Count -gt 0) { $prepArgs.Ecosystems = $offlineEcosystems }
    $feed = & (Join-Path $ScriptDir 'prepare-packages.ps1') @prepArgs
    return ($feed | Select-Object -Last 1)
}

$exitCode = Invoke-AutopilotDispatch -Launch $Launch -PrepareFeed $PrepareFeed -Rebundle $Rebundle -MaxRebundles $offline.MaxRebundles -Offline:$offlineActive

Write-Host ""
Write-Host "=== Autopilot finished with exit code: $exitCode ==="
exit $exitCode
