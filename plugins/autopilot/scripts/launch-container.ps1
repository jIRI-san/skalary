<#
.SYNOPSIS
    Container-mode orchestrator for autonomous plan execution.
.DESCRIPTION
    Builds the Docker image, runs the blocking container process, and extracts
    transcripts on completion.
.PARAMETER PlanSlug
    The plan folder name (e.g. '002-persistent-storage-for-job-data').
.PARAMETER Mode
    Execution scope: 'whole-plan' or 'next-phase'.
.PARAMETER Config
    Parsed .autopilot.json object.
.PARAMETER Token
    GitHub token for Copilot CLI.
.PARAMETER AdoToken
    Optional ADO access token.
.PARAMETER StartBranch
    Validated branch from which a new target branch is created.
#>
param(
    [Parameter(Mandatory)]
    [string]$PlanSlug,

    [Parameter(Mandatory)]
    [ValidateSet('whole-plan', 'next-phase')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [PSCustomObject]$Config,

    [Parameter(Mandatory)]
    [string]$Token,

    [string]$AdoToken,

    [string]$Branch = "feature/$PlanSlug",

    [string]$StartBranch = (git branch --show-current),

    [string]$ExpectedStartCommit,

    [string]$Run,

    [switch]$TrustedInternalRetry,

    # When set, mount this host package-feed read-only at /feed and run the
    # container fully offline (see prepare-packages.ps1).
    [string]$FeedPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'autopilot-dispatch.ps1')

$RepoRoot = git rev-parse --show-toplevel
$ImageName = "autopilot-$(Split-Path $RepoRoot -Leaf)".ToLower()
$ContainerName = Get-AutopilotContainerName -Run $Run
$PlanFolder = Join-Path $RepoRoot "docs/implementation-plans/$PlanSlug"
$TranscriptsDir = Join-Path $PlanFolder 'transcripts'
$EnvFilePath = $null
# Default to failure so any early throw or unread exit code surfaces as non-zero.
$exitCode = 1

try {
    # --- Build image ---
    Write-Host "Building Docker image: $ImageName"
    $bundleRoot = Join-Path $PSScriptRoot '..'
    $dockerfilePath = Join-Path $bundleRoot 'devcontainer/Dockerfile'

    # Handle dockerfileExtensions - generate extended Dockerfile if needed
    $buildContext = $bundleRoot
    $actualDockerfile = $dockerfilePath

    if ($Config.PSObject.Properties.Name -contains 'dockerfileExtensions' -and $Config.dockerfileExtensions -and $Config.dockerfileExtensions.Count -gt 0) {
        Write-Host "Appending dockerfileExtensions to Dockerfile..."
        $tempDockerfile = Join-Path $env:TEMP "autopilot-Dockerfile-extended"
        $baseContent = Get-Content $dockerfilePath -Raw
        $extensions = ($Config.dockerfileExtensions | ForEach-Object { "RUN $_" }) -join "`n"
        # Insert extensions before the USER directive
        $extendedContent = $baseContent -replace '(# Non-root user)', "$extensions`n`n`$1"
        Set-Content -Path $tempDockerfile -Value $extendedContent -Encoding UTF8
        $actualDockerfile = $tempDockerfile
    }

    # Resolve the latest published Copilot CLI version so each build picks up new
    # releases automatically. Passed as a build-arg; Docker only busts the npm
    # install layer when the version actually changes. Falls back to the
    # Dockerfile's pinned default if the npm registry is unreachable.
    # npm writes notices to stderr, which would abort under $ErrorActionPreference
    # 'Stop'; run the probe with a local 'Continue' preference and stderr muted.
    $buildArgs = @()
    $latestCli = $null
    try {
        $latestCli = & {
            $ErrorActionPreference = 'Continue'
            npm view '@github/copilot' version 2>$null
        }
    }
    catch {
        $latestCli = $null
    }
    if ($LASTEXITCODE -eq 0 -and $latestCli) {
        $latestCli = ($latestCli | Select-Object -Last 1).Trim()
        Write-Host "Latest Copilot CLI version: $latestCli"
        $buildArgs += @('--build-arg', "COPILOT_CLI_VERSION=$latestCli")
    }
    else {
        Write-Warning "Could not resolve latest Copilot CLI version from npm; using Dockerfile default."
    }

    docker build @buildArgs -t $ImageName -f $actualDockerfile $buildContext
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed." }

    # --- Prepare env file ---
    Write-Host "Preparing environment file..."
    $envParams = @{ Config = $Config; Token = $Token; AdoToken = $AdoToken; Branch = $StartBranch }
    if ($ExpectedStartCommit) {
        $envParams.ExpectedStartCommit = $ExpectedStartCommit
    }
    if ($TrustedInternalRetry) {
        $envParams.TrustedInternalRetry = $true
    }
    if ($FeedPath) { $envParams.Offline = $true }
    $EnvFilePath = & (Join-Path $PSScriptRoot 'prepare-env-file.ps1') @envParams

    # --- Run container ---
    Write-Host "Starting container: $ContainerName"
    $dockerArgs = @(
        'run', '-t'
        '--name', $ContainerName
        '--env-file', $EnvFilePath
    )
    if ($FeedPath) {
        # Read-only mount: the entrypoint copies /feed to a writable cache, so the
        # mounted feed itself is never mutated by the disposable runtime.
        $dockerArgs += @('-v', "${FeedPath}:/feed:ro")
    }
    $dockerArgs += @(
        $ImageName
        '/usr/local/bin/container-entrypoint.sh', $PlanSlug, $Mode
    )

    # The container call is the synchronous host/operator interruption boundary.
    $dockerProcess = Start-Process -FilePath 'docker' -ArgumentList $dockerArgs -NoNewWindow -PassThru
    # Cache the native process handle now so $dockerProcess.ExitCode remains
    # readable after the process exits. Without this, Start-Process -PassThru
    # returns $null for ExitCode once the process has terminated.
    $null = $dockerProcess.Handle

    $dockerProcess.WaitForExit()
    $exitCode = $dockerProcess.ExitCode
    if ($null -eq $exitCode) {
        Write-Warning "Could not read container exit code; treating as failure."
        $exitCode = 1
    }
    Write-Host "Container exited with code: $exitCode"

    # --- Extract transcripts ---
    if (-not (Test-Path $TranscriptsDir)) {
        New-Item -ItemType Directory -Path $TranscriptsDir -Force | Out-Null
    }

    Write-Host "Extracting transcripts..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Copy all transcript files (ignore errors for missing files)
    for ($i = 1; $i -le 10; $i++) {
        docker cp "${ContainerName}:/work/session-transcript-phase${i}.md" $TranscriptsDir 2>$null
        docker cp "${ContainerName}:/work/session-transcript-phase${i}-completion.md" $TranscriptsDir 2>$null
    }
    docker cp "${ContainerName}:/work/session-transcript-completion.md" $TranscriptsDir 2>$null
    $ErrorActionPreference = $prevEAP

    # --- Cleanup container ---
    $preservationMarker = Join-Path ([System.IO.Path]::GetTempPath()) (
        'autopilot-preservation-' + [guid]::NewGuid().ToString('N')
    )
    $ErrorActionPreference = 'Continue'
    docker cp "${ContainerName}:/tmp/autopilot-preservation-failed" $preservationMarker 2>$null
    $preservationFailed = Test-Path -LiteralPath $preservationMarker -PathType Leaf
    Remove-Item -LiteralPath $preservationMarker -Force -ErrorAction SilentlyContinue
    if ($preservationFailed) {
        Write-Warning "Retaining container '$ContainerName' because work preservation failed."
    }
    else {
        Write-Host "Removing container: $ContainerName"
        docker rm $ContainerName 2>$null
    }
    $ErrorActionPreference = $prevEAP

    Write-Host ""
    Write-Host "=== Container-mode execution complete ==="
    Write-Host "Exit code: $exitCode"
    Write-Host "Transcripts: $TranscriptsDir"

    if ($exitCode -ne 0) {
        Write-Warning "Container execution ended with non-zero exit code."
    }
}
finally {
    # Always clean up env file (contains tokens)
    if ($EnvFilePath -and (Test-Path $EnvFilePath)) {
        $envDir = Split-Path $EnvFilePath -Parent
        Remove-Item $EnvFilePath -Force -ErrorAction SilentlyContinue
        Remove-Item $envDir -Force -ErrorAction SilentlyContinue
        Write-Host "Env file cleaned up."
    }
}

# Propagate the container exit code to the caller (launch.ps1).
exit $exitCode
