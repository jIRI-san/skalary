#requires -Version 7.0
<#
.SYNOPSIS
    The ONLY provisioner for the waza Tier-2 LLM-eval toolchain (plan 0f666f).
.DESCRIPTION
    Reads tools/eval-tools.psd1 (the single source of truth) and, per tool, RESOLVES
    the installed version, then decides one of: ok (== pin) / run-as-is (older, never
    auto-changed) / install (missing or below floor) / newer (surface only via
    -CheckUpdates). Missing or declined installs end in an actionable SKIP, never a
    hard failure — except a checksum mismatch or an unverified schemaVersion, which
    fail loudly.

    Installs require EXPLICIT approval: interactive y/N, -Approve, or
    WAZA_EVAL_APPROVE_INSTALL=1. Downloaded binaries are byte-verified against the
    committed Sha256 constants in the manifest (same check for online and OfflinePath).
    The stock waza install.ps1/install.sh (which pull *latest*) are never used.

    Cross-platform: Windows + Linux/macOS (autopilot containers). Where a platform's
    provisioning path is unavailable (e.g. winget only on Windows), the tool is SKIPPED
    with a clear message rather than failing the whole run.

    This file is dot-sourceable: it defines Invoke-EnsureEvalTools and helpers with no
    side effects so tests can exercise the decision logic offline. It executes only
    when run as a script.
.PARAMETER RepoRoot
    Repository root. Defaults to two levels up from this script.
.PARAMETER ManifestPath
    Path to the tool manifest. Defaults to <RepoRoot>/tools/eval-tools.psd1.
.PARAMETER Approve
    Non-interactive approval for installs (equivalent to WAZA_EVAL_APPROVE_INSTALL=1).
.PARAMETER CheckUpdates
    Surface (print) when an installed tool is newer than the pin. Opt-in; without it a
    newer-than-pin tool simply runs as-is. Bumping the manifest pin remains a separate,
    reviewable change (never automated here) so upgrades stay an auditable diff.
.OUTPUTS
    [pscustomobject] with Tools (per-tool decisions), ResolvedPaths (dirs to prepend to
    PATH), and Skipped (tools that could not be provisioned).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string]$ManifestPath,
    [switch]$Approve,
    [switch]$CheckUpdates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-EvalPlatformKey {
    [CmdletBinding()]
    param(
        [string]$OsOverride,
        [string]$ArchOverride
    )

    if ($OsOverride) {
        $os = $OsOverride
    }
    elseif ($IsWindows) {
        $os = 'windows'
    }
    elseif ($IsLinux) {
        $os = 'linux'
    }
    elseif ($IsMacOS) {
        $os = 'darwin'
    }
    else {
        throw 'Unsupported operating system for eval tooling.'
    }

    if ($ArchOverride) {
        $arch = $ArchOverride
    }
    else {
        $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        switch ($osArch) {
            'X64' { $arch = 'amd64' }
            'Arm64' { $arch = 'arm64' }
            default { throw "Unsupported processor architecture: $osArch." }
        }
    }

    if ($os -notin @('windows', 'linux', 'darwin')) {
        throw "Unsupported operating system for eval tooling: $os."
    }
    if ($arch -notin @('amd64', 'arm64')) {
        throw "Unsupported processor architecture: $arch."
    }

    return "$os-$arch"
}

function Get-EvalPlatformOs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlatformKey
    )

    return $PlatformKey.Split('-', 2)[0]
}

function Expand-InstallDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $homeDir = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($homeDir)) {
        throw 'Cannot resolve a home directory (neither HOME nor USERPROFILE is set).'
    }

    $localAppData = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $env:LOCALAPPDATA
    }
    else {
        Join-Path $homeDir '.local/share'
    }

    $expanded = $Token.Replace('%LOCALAPPDATA%', $localAppData).Replace('%HOME%', $homeDir)
    return [System.IO.Path]::GetFullPath(($expanded -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Import-EvalToolManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Tool manifest not found: $Path"
    }

    $manifest = Import-PowerShellDataFile -LiteralPath $Path
    foreach ($key in 'SpecSchemaVersion', 'Tools') {
        if (-not $manifest.ContainsKey($key)) {
            throw "Tool manifest is missing required key '$key': $Path"
        }
    }

    return $manifest
}

function ConvertFrom-ToolVersionOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, '(?<v>\d+\.\d+\.\d+)')
    if ($match.Success) {
        return $match.Groups['v'].Value
    }

    return $null
}

function Get-InstalledToolVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$VersionArgs = @('--version'),

        # Known install locations to probe when the command is not on PATH
        # (design §4: resolve via PATH / known install dir / offlinePath). The
        # first existing candidate is used so repeat runs skip re-provisioning.
        [string[]]$CandidatePath = @()
    )

    $source = $null
    $resolved = Get-Command -Name $Command -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $resolved) {
        $source = $resolved.Source
    }
    else {
        foreach ($candidate in $CandidatePath) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $source = $candidate
                break
            }
        }
    }

    if ($null -eq $source) {
        return $null
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & $source @VersionArgs 2>&1 | Out-String
    }
    catch {
        $raw = ''
    }
    finally {
        $ErrorActionPreference = $previous
    }

    return [pscustomobject]@{
        Path = $source
        Version = ConvertFrom-ToolVersionOutput -Text $raw
    }
}

function Get-ToolCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [Parameter(Mandatory)]
        [string]$PlatformKey
    )

    $name = [string]$Tool.Name
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($name -eq 'waza') {
        $asset = $Tool.Assets[$PlatformKey]
        if ($null -ne $asset) {
            $dir = Expand-InstallDir -Token ([string]$asset.InstallDir)
            $candidates.Add((Join-Path $dir ([string]$asset.BinaryName)))
        }
    }
    elseif ($name -eq 'gh') {
        if ($IsWindows) {
            foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
                if (-not [string]::IsNullOrWhiteSpace($root)) {
                    $candidates.Add((Join-Path $root 'GitHub CLI\gh.exe'))
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
                $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\gh.exe'))
            }
        }
        else {
            foreach ($p in @('/opt/homebrew/bin/gh', '/usr/local/bin/gh', '/usr/bin/gh')) {
                $candidates.Add($p)
            }
        }
    }

    return $candidates.ToArray()
}

function Resolve-EvalToolDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$InstalledVersion
    )

    $policy = if ($Tool.ContainsKey('VersionPolicy')) { [string]$Tool.VersionPolicy } else { 'exact' }
    $pinned = [string]$Tool.Version

    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
        return [pscustomobject]@{
            Tool = [string]$Tool.Name
            Action = 'install'
            Reason = "not present; pinned $pinned"
            Version = $pinned
        }
    }

    if ($policy -eq 'floor') {
        $floor = if ($Tool.ContainsKey('MinVersion')) { [string]$Tool.MinVersion } else { $pinned }
        if ((Compare-SemVer -Left $InstalledVersion -Right $floor) -ge 0) {
            return [pscustomobject]@{
                Tool = [string]$Tool.Name
                Action = 'ok'
                Reason = "present $InstalledVersion >= floor $floor"
                Version = $InstalledVersion
            }
        }

        return [pscustomobject]@{
            Tool = [string]$Tool.Name
            Action = 'install'
            Reason = "present $InstalledVersion below floor $floor"
            Version = $pinned
        }
    }

    $comparison = Compare-SemVer -Left $InstalledVersion -Right $pinned
    if ($comparison -eq 0) {
        return [pscustomobject]@{
            Tool = [string]$Tool.Name
            Action = 'ok'
            Reason = "present == pinned $pinned"
            Version = $InstalledVersion
        }
    }

    if ($comparison -lt 0) {
        return [pscustomobject]@{
            Tool = [string]$Tool.Name
            Action = 'run-as-is'
            Reason = "present $InstalledVersion older than pinned $pinned; running as-is (never auto-changed)"
            Version = $InstalledVersion
        }
    }

    return [pscustomobject]@{
        Tool = [string]$Tool.Name
        Action = 'newer'
        Reason = "present $InstalledVersion newer than pinned $pinned; surface with -CheckUpdates"
        Version = $InstalledVersion
    }
}

function Get-ApprovalDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$Version,

        [switch]$Approve,

        [switch]$Interactive
    )

    if ($Approve) {
        return $true
    }

    $envFlag = $env:WAZA_EVAL_APPROVE_INSTALL
    if ($envFlag -eq '1' -or $envFlag -eq 'true') {
        return $true
    }

    if ($Interactive) {
        $prompt = 'Install {0} {1}? [y/N]' -f $ToolName, $Version
        $answer = Read-Host $prompt
        return ($answer -match '^(?i:y|yes)$')
    }

    return $false
}

function Assert-Sha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Expected
    )

    $actual = Get-FileSha256 -Path $Path
    $expectedNormalized = $Expected.Trim().ToLowerInvariant()
    if ($actual -ne $expectedNormalized) {
        throw "Checksum mismatch for '$Path': expected $expectedNormalized, got $actual."
    }

    return $true
}

function Test-SchemaCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$MigrateOutput,

        [Parameter(Mandatory)]
        [string]$TargetSchema,

        [int]$ExitCode = 0
    )

    # Interprets the output of `waza migrate <spec>` where <spec> declares TargetSchema:
    #   exit 0 + "compatible with schemaVersion X" / "migrated" => the binary supports it
    #   nonzero, or an "unknown/unsupported schema" message      => not supported
    if ($ExitCode -ne 0) {
        return $false
    }

    if ($MigrateOutput -match '(?i:unknown|unsupported)\s+schema') {
        return $false
    }

    if ($MigrateOutput -match [regex]::Escape($TargetSchema)) {
        return $true
    }

    if ($MigrateOutput -match '(?i:no migration needed|migrated)') {
        return $true
    }

    return $false
}

function Assert-WazaSchemaSupport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WazaPath,

        [Parameter(Mandatory)]
        [string]$TargetSchema
    )

    # Probe the resolved binary against the schemaVersion our specs declare. `waza
    # migrate` requires the file be named eval.yaml/eval.yml, so use a throwaway dir.
    $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("waza-schema-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
    $spec = Join-Path $probeDir 'eval.yaml'
    $body = @(
        "schemaVersion: `"$TargetSchema`""
        'skill: schema-probe'
        'tasks: []'
    ) -join "`n"
    Set-Content -LiteralPath $spec -Value $body -Encoding utf8NoBOM

    try {
        $output = & $WazaPath migrate $spec 2>&1 | Out-String
        $exit = $LASTEXITCODE
        if (-not (Test-SchemaCompat -MigrateOutput $output -TargetSchema $TargetSchema -ExitCode $exit)) {
            throw "waza at '$WazaPath' does not support spec schemaVersion $TargetSchema (from tools/eval-tools.psd1). ``waza migrate`` said: $($output.Trim())"
        }
    }
    finally {
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $true
}

function Install-WazaBinary {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [Parameter(Mandatory)]
        [hashtable]$Asset
    )

    $installDir = Expand-InstallDir -Token ([string]$Asset.InstallDir)
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    $target = Join-Path $installDir ([string]$Asset.BinaryName)

    $offlinePath = if ($Tool.ContainsKey('OfflinePath')) { $Tool.OfflinePath } else { $null }
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("waza-dl-" + [guid]::NewGuid().ToString('N'))

    if (-not $PSCmdlet.ShouldProcess($target, "Install waza $($Tool.Version)")) {
        return $target
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($offlinePath)) {
            Copy-Item -LiteralPath $offlinePath -Destination $temp -Force
        }
        else {
            $url = "https://github.com/$($Tool.Repo)/releases/download/$($Tool.Tag)/$($Asset.File)"
            Write-Host "Downloading $url"
            Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing
        }

        # Same committed-checksum verification for online and offline sources.
        Assert-Sha256 -Path $temp -Expected ([string]$Asset.Sha256) | Out-Null
        Copy-Item -LiteralPath $temp -Destination $target -Force
        if (-not $IsWindows) {
            & chmod '+x' $target
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    return $target
}

function Install-GhTool {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [Parameter(Mandatory)]
        [string]$PlatformOs
    )

    if (-not $Tool.ContainsKey('Install') -or -not $Tool.Install.ContainsKey($PlatformOs)) {
        throw "gh has no provisioning path for platform '$PlatformOs'."
    }

    $spec = $Tool.Install[$PlatformOs]
    $manager = [string]$spec.Manager
    $id = [string]$spec.Id

    $managerAvailable = $null -ne (Get-Command -Name $manager -ErrorAction SilentlyContinue)
    if (-not $managerAvailable) {
        # REQ-19: no fail — the caller records a SKIP.
        throw "SKIP: package manager '$manager' is not available on this $PlatformOs host; install gh manually ($id)."
    }

    if (-not $PSCmdlet.ShouldProcess($id, "Install gh via $manager")) {
        return
    }

    switch ($manager) {
        'winget' { & winget install --exact --id $id --accept-source-agreements --accept-package-agreements 2>&1 | Out-Host }
        'apt' { & sudo apt-get install -y $id 2>&1 | Out-Host }
        'brew' { & brew install $id 2>&1 | Out-Host }
        default { throw "Unsupported package manager '$manager'." }
    }
}

function Invoke-EnsureEvalTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ManifestPath,

        [switch]$Approve,

        [switch]$CheckUpdates
    )

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = Join-Path $RepoRoot 'tools/eval-tools.psd1'
    }

    $manifest = Import-EvalToolManifest -Path $ManifestPath
    $platformKey = Get-EvalPlatformKey
    $platformOs = Get-EvalPlatformOs -PlatformKey $platformKey
    $interactive = [Environment]::UserInteractive -and -not $Approve

    $decisions = [System.Collections.Generic.List[object]]::new()
    $resolvedPaths = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()
    $wazaPath = $null
    $wazaSkipped = $false

    foreach ($tool in $manifest.Tools) {
        $name = [string]$tool.Name
        $versionArgs = if ($name -eq 'gh') { @('--version') } else { @('--version') }
        $candidatePaths = Get-ToolCandidatePath -Tool $tool -PlatformKey $platformKey
        $installed = Get-InstalledToolVersion -Command $name -VersionArgs $versionArgs -CandidatePath $candidatePaths
        $installedVersion = if ($installed) { $installed.Version } else { $null }
        $decision = Resolve-EvalToolDecision -Tool $tool -InstalledVersion $installedVersion

        switch ($decision.Action) {
            'install' {
                $approved = Get-ApprovalDecision -ToolName $name -Version $decision.Version -Approve:$Approve -Interactive:$interactive
                if (-not $approved) {
                    $decision = [pscustomobject]@{ Tool = $name; Action = 'skip'; Reason = "install declined ($($decision.Reason))"; Version = $decision.Version }
                    $skipped.Add($decision)
                    if ($name -eq 'waza') { $wazaSkipped = $true }
                    break
                }

                try {
                    if ($name -eq 'waza') {
                        $asset = $tool.Assets[$platformKey]
                        if ($null -eq $asset) {
                            throw "No waza asset for platform '$platformKey'."
                        }
                        $binaryPath = Install-WazaBinary -Tool $tool -Asset $asset
                        $resolvedPaths.Add((Split-Path -Parent $binaryPath))
                        $wazaPath = $binaryPath
                    }
                    else {
                        Install-GhTool -Tool $tool -PlatformOs $platformOs
                    }
                }
                catch {
                    $message = [string]$_.Exception.Message
                    if ($message -like 'SKIP:*') {
                        $decision = [pscustomobject]@{ Tool = $name; Action = 'skip'; Reason = $message.Substring(5).Trim(); Version = $decision.Version }
                        $skipped.Add($decision)
                        if ($name -eq 'waza') { $wazaSkipped = $true }
                        break
                    }
                    throw
                }
            }
            'ok' {
                if ($installed) { $resolvedPaths.Add((Split-Path -Parent $installed.Path)) }
                if ($name -eq 'waza' -and $installed) { $wazaPath = $installed.Path }
            }
            'run-as-is' {
                if ($installed) { $resolvedPaths.Add((Split-Path -Parent $installed.Path)) }
                if ($name -eq 'waza' -and $installed) { $wazaPath = $installed.Path }
            }
            'newer' {
                if ($installed) { $resolvedPaths.Add((Split-Path -Parent $installed.Path)) }
                if ($name -eq 'waza' -and $installed) { $wazaPath = $installed.Path }
                if ($CheckUpdates) {
                    Write-Host "$name $($decision.Version) is newer than the pinned $([string]$tool.Version). A manifest pin-bump is a separate, reviewable change (not automated here)."
                }
            }
        }

        $decisions.Add($decision)
    }

    # Fail loudly if the resolved waza cannot handle the schemaVersion our specs declare.
    if (-not $wazaSkipped -and $wazaPath -and (Test-Path -LiteralPath $wazaPath)) {
        Assert-WazaSchemaSupport -WazaPath $wazaPath -TargetSchema ([string]$manifest.SpecSchemaVersion) | Out-Null
    }

    return [pscustomobject]@{
        Manifest = $ManifestPath
        Platform = $platformKey
        SpecSchema = [string]$manifest.SpecSchemaVersion
        Tools = $decisions.ToArray()
        ResolvedPaths = ($resolvedPaths | Select-Object -Unique)
        Skipped = $skipped.ToArray()
    }
}

# Execute only when run as a script (not when dot-sourced for testing).
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-EnsureEvalTools -RepoRoot $RepoRoot -ManifestPath $ManifestPath -Approve:$Approve -CheckUpdates:$CheckUpdates
    foreach ($decision in $result.Tools) {
        Write-Host ("  {0,-6} {1,-10} {2}" -f $decision.Tool, $decision.Action, $decision.Reason)
    }
    foreach ($skip in $result.Skipped) {
        Write-Host ("  SKIP {0}: {1}" -f $skip.Tool, $skip.Reason) -ForegroundColor Yellow
    }
    $result
}
