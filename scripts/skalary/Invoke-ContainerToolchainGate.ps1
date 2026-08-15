#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Measure', 'VerifyResult')]
    [string]$Mode = 'Detect',
    [string]$BaseSha,
    [string]$CandidateSha,
    [string]$BaseRoot,
    [string]$CandidateRoot,
    [string]$ReceiptPath,
    [string]$ProvenancePath,
    [string]$SummaryPath,
    [string]$DiagnosticLogPath,
    [string]$DetectorConclusion,
    [string]$Relevance,
    [string]$ImageConclusion,
    [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift')]
    [string]$DetectionCandidateOnlyReason,
    [ValidateSet('', 'true', 'false')]
    [string]$DetectionRelevance,
    [string]$CopilotVersion,
    [string]$RunnerArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant(),
    [ValidateRange(1, 2100)]
    [int]$CandidateBudgetSeconds = 1500,
    [ValidateRange(1, 600)]
    [int]$BaseBudgetSeconds = 600,
    [ValidateRange(1, 2100)]
    [int]$RunnerBudgetSeconds = 2100,
    [ValidateRange(1, 1048576)]
    [int]$AdvisoryGrowthMiB = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GateSchema = 'skalary/container-toolchain-receipt@1'
$script:SmokeSchema = 'skalary/container-toolchain-smoke@1'
$script:BaseImage = 'debian:trixie-slim'
$script:MaxReceiptBytes = 65535
$script:MaxProcessOutput = 65535
# Build failures surface at the end of BuildKit progress, so capture keeps a bounded head for
# the invocation context and spends the rest of the budget on the tail that names the failure.
$script:ProcessHeadChars = 16384
$script:MaxDiagnosticChars = 1024
$script:MaxReceiptFailedCases = 32
$script:MaxPayloadFileBytes = 4MB
$script:ShaPattern = '^[0-9A-Fa-f]{40}$'
$script:ZeroSha = '0000000000000000000000000000000000000000'
# The Debian baseline layer may only resolve from Debian hosts; the later maintained-toolchain
# layers add exactly these two channels, and the image may present no other active apt origin.
$script:DebianAptHosts = @('deb.debian.org', 'security.debian.org')
$script:AllowedAptHosts = @(
    'deb.debian.org',
    'download.docker.com',
    'packages.microsoft.com',
    'security.debian.org'
)
$script:AttestedManifestPath = '/usr/local/share/autopilot/toolchain.tsv'
$script:AttestedDebianSourcesPath = '/usr/local/share/autopilot/provenance/apt-sources.txt'
$script:AttestedFinalSourcesPath = '/usr/local/share/autopilot/provenance/final-apt-sources.txt'
$script:AllowedOutcomes = @(
    'success',
    'irrelevant',
    'candidate-build-failed',
    'candidate-smoke-failed',
    'candidate-output-invalid',
    'candidate-timeout',
    'base-build-failed',
    'base-timeout',
    'unexpected-error'
)
$script:AllowedCandidateOnlyReasons = @(
    'zero-base',
    'base-unreachable',
    'base-context-absent',
    'base-payload-drift',
    'base-build-failed',
    'base-timeout'
)

function Limit-GateText {
    param(
        [AllowNull()][object]$Value,
        [ValidateRange(0, 1048576)][int]$Maximum = 512,
        [switch]$PreserveNul
    )

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $controlPattern = if ($PreserveNul) { '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' } else { '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' }
    $text = [regex]::Replace($text, $controlPattern, '')
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($text.Length -gt $Maximum) { return $text.Substring(0, $Maximum) }
    return $text
}

function ConvertTo-GateMarkdown {
    param([AllowNull()][object]$Value)

    $text = (Limit-GateText -Value $Value -Maximum 1024).Replace("`n", ' ')
    $text = $text.Replace('\', '\\')
    foreach ($character in @('`', '*', '_', '{', '}', '[', ']', '<', '>', '(', ')', '#', '+', '-', '.', '!', '|')) {
        $text = $text.Replace($character, "\$character")
    }
    return $text
}

function Get-GateSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GateTextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Sort-GateOrdinal {
    param([AllowEmptyCollection()][string[]]$Value)

    $copy = [string[]]@($Value)
    [array]::Sort($copy, [System.StringComparer]::Ordinal)
    return $copy
}

function New-GateCaptureState {
    return @{
        Head = [System.Text.StringBuilder]::new()
        Tail = [System.Text.StringBuilder]::new()
        Dropped = [int64]0
        Overflow = $false
        InvalidControl = $false
        Done = $false
    }
}

function Add-GateCaptureChunk {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Chunk,
        [switch]$AllowControlCharacters
    )

    if (-not $AllowControlCharacters -and
        [regex]::IsMatch($Chunk, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]')) {
        $State.InvalidControl = $true
    }
    if ($Chunk.Length -eq 0) { return }

    $offset = 0
    $headRoom = $script:ProcessHeadChars - $State.Head.Length
    if ($headRoom -gt 0) {
        $take = [math]::Min($headRoom, $Chunk.Length)
        [void]$State.Head.Append($Chunk, 0, $take)
        $offset = $take
    }
    if ($offset -ge $Chunk.Length) { return }

    [void]$State.Tail.Append($Chunk, $offset, $Chunk.Length - $offset)
    $tailMaximum = $script:MaxProcessOutput - $script:ProcessHeadChars - 128
    if ($State.Tail.Length -gt $tailMaximum) {
        $excess = $State.Tail.Length - $tailMaximum
        [void]$State.Tail.Remove(0, $excess)
        $State.Dropped += $excess
        $State.Overflow = $true
    }
}

function Get-GateCaptureText {
    <#
    .SYNOPSIS
        Joins a bounded capture into head, an explicit truncation marker, and the tail.
    .NOTES
        A head-only bound throws away the end of a build log, which is where the failing
        instruction and its error live; the marker keeps the discarded amount auditable.
    #>
    param([Parameter(Mandatory)][hashtable]$State)

    if ($State.Dropped -le 0) { return ($State.Head.ToString() + $State.Tail.ToString()) }
    $marker = "`n...[$($State.Dropped) characters truncated]...`n"
    return ($State.Head.ToString() + $marker + $State.Tail.ToString())
}

function Get-GateProcessDiagnostic {
    <#
    .SYNOPSIS
        Returns the bounded tail of a failed process, preferring the stream that named it.
    #>
    param(
        [Parameter(Mandatory)][object]$Result,
        [ValidateRange(1, 65535)][int]$Maximum = $script:MaxDiagnosticChars
    )

    $text = if (-not [string]::IsNullOrWhiteSpace($Result.Stderr)) { [string]$Result.Stderr }
    else { [string]$Result.Stdout }
    $text = (Limit-GateText -Value $text -Maximum $script:MaxProcessOutput).TrimEnd()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text.Length -le $Maximum) { return $text }
    return ('...' + $text.Substring($text.Length - ($Maximum - 3)))
}

function Write-GateDiagnosticLog {
    <#
    .SYNOPSIS
        Persists the bounded capture of a failing stage so the receipt tail is not the only copy.
    #>
    param(
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][object]$Result
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $lines = @(
        "stage: $Stage",
        "exitCode: $($Result.ExitCode)",
        "timedOut: $($Result.TimedOut)",
        "elapsedMs: $($Result.ElapsedMs)",
        "stdoutTruncated: $($Result.StdoutOverflow)",
        "stderrTruncated: $($Result.StderrOverflow)",
        '--- stdout ---',
        (Limit-GateText -Value $Result.Stdout -Maximum $script:MaxProcessOutput),
        '--- stderr ---',
        (Limit-GateText -Value $Result.Stderr -Maximum $script:MaxProcessOutput)
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    # Stages append: a candidate build failure followed by a smoke failure are two separate facts,
    # and overwriting would leave only the last one.
    [System.IO.File]::AppendAllText($fullPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-GateProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$TimeoutSeconds,
        [string]$WorkingDirectory,
        [switch]$PreserveControlCharacters
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    foreach ($argument in $ArgumentList) { [void]$startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw "Failed to start '$FilePath'." }
        $stdoutBuffer = [char[]]::new(4096)
        $stderrBuffer = [char[]]::new(4096)
        $stdoutState = New-GateCaptureState
        $stderrState = New-GateCaptureState
        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length)
        $stderrTask = $process.StandardError.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
        $timedOut = $false
        $drainDeadline = [TimeSpan]::MaxValue

        while (-not ($stdoutState.Done -and $stderrState.Done)) {
            if (-not $stdoutState.Done -and $stdoutTask.IsCompleted) {
                $count = $stdoutTask.GetAwaiter().GetResult()
                if ($count -eq 0) {
                    $stdoutState.Done = $true
                }
                else {
                    Add-GateCaptureChunk -State $stdoutState -Chunk ([string]::new($stdoutBuffer, 0, $count)) `
                        -AllowControlCharacters:$PreserveControlCharacters
                    $stdoutTask = $process.StandardOutput.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length)
                }
            }
            if (-not $stderrState.Done -and $stderrTask.IsCompleted) {
                $count = $stderrTask.GetAwaiter().GetResult()
                if ($count -eq 0) {
                    $stderrState.Done = $true
                }
                else {
                    Add-GateCaptureChunk -State $stderrState -Chunk ([string]::new($stderrBuffer, 0, $count))
                    $stderrTask = $process.StandardError.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
                }
            }

            if (-not $timedOut -and $clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                $drainDeadline = $clock.Elapsed.Add([TimeSpan]::FromSeconds(5))
                try { $process.Kill($true) } catch { }
            }
            if ($timedOut -and $clock.Elapsed -ge $drainDeadline) { break }
            if (-not ($stdoutState.Done -and $stderrState.Done)) {
                Start-Sleep -Milliseconds 5
            }
        }

        # Both streams can close while the child is still alive, so the exit code is only
        # readable after the process has actually exited: a still-running child is a timeout,
        # not an ExitCode read that throws and turns into an unexpected-error receipt.
        if (-not $process.HasExited) { [void]$process.WaitForExit(5000) }
        if (-not $process.HasExited) {
            $timedOut = $true
            try { $process.Kill($true) } catch { }
            [void]$process.WaitForExit(5000)
        }
        $exitCode = if ($timedOut) { -1 }
        elseif ($process.HasExited) { $process.ExitCode }
        else { -1 }

        $stdout = Get-GateCaptureText -State $stdoutState
        $stderr = Get-GateCaptureText -State $stderrState
        return [pscustomobject]@{
            ExitCode = $exitCode
            TimedOut = $timedOut
            Stdout = if ($PreserveControlCharacters) { $stdout } else { Limit-GateText -Value $stdout -Maximum $script:MaxProcessOutput }
            Stderr = Limit-GateText -Value $stderr -Maximum $script:MaxProcessOutput
            StdoutOverflow = [bool]$stdoutState.Overflow
            StderrOverflow = [bool]$stderrState.Overflow
            StdoutInvalidControl = [bool]$stdoutState.InvalidControl
            StderrInvalidControl = [bool]$stderrState.InvalidControl
            ElapsedMs = [int64]$clock.ElapsedMilliseconds
        }
    }
    finally {
        $clock.Stop()
        $process.Dispose()
    }
}

function Assert-GateSha {
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Value)
    if (-not [regex]::IsMatch($Value, $script:ShaPattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "$Name must be exactly 40 hexadecimal characters."
    }
}

function Assert-GateRoot {
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Name is required." }
    $fullPath = [System.IO.Path]::GetFullPath($Value)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "$Name does not name a checkout directory: '$Value'."
    }
    return $fullPath
}

function Test-GateCheckoutHead {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Sha)
    $result = Invoke-GateProcess -FilePath 'git' -ArgumentList @('-C', $Root, 'rev-parse', '--verify', 'HEAD') -TimeoutSeconds 15
    return $result.ExitCode -eq 0 -and
        [string]::Equals($result.Stdout.Trim(), $Sha, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-GateRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = $Path.Replace('\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        $normalized.Contains([char]0) -or
        @($normalized.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "Unsafe repository-relative path '$Path'."
    }
    return $normalized
}

function Test-GateDockerfileBase {
    param([Parameter(Mandatory)][string]$Path)

    $dockerfile = Get-Content -LiteralPath $Path -Raw
    $froms = @([regex]::Matches(
            $dockerfile,
            '(?im)^\s*FROM\s+(?:--platform=(?<platform>\S+)\s+)?(?<image>\S+)(?:\s+AS\s+\S+)?\s*$'
        ))
    return $froms.Count -eq 1 -and
        [string]::Equals($froms[0].Groups['image'].Value, $script:BaseImage, [System.StringComparison]::Ordinal) -and
        (-not $froms[0].Groups['platform'].Success -or
            [string]::Equals($froms[0].Groups['platform'].Value, 'linux/amd64', [System.StringComparison]::Ordinal))
}

function Test-GateConcreteVersion {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or $Value.Length -gt 64) { return $false }
    return $Value -match '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
}

function Test-GateCheckoutFile {
    param(
        [Parameter(Mandatory)][string]$CheckoutRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $root = [System.IO.Path]::GetFullPath($CheckoutRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($root, $fullPath)
    if ($relative -eq '..' -or $relative.StartsWith("../", [System.StringComparison]::Ordinal) -or
        $relative.StartsWith("..\",
            [System.StringComparison]::Ordinal)) {
        return $false
    }

    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
    if ($null -eq $rootItem -or $rootItem.LinkType -or
        ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return $false
    }
    $current = $root
    foreach ($segment in $relative.Split(
            [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )) {
        $current = Join-Path $current $segment
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.LinkType -or
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            return $false
        }
    }
    $file = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    return $file -is [System.IO.FileInfo] -and $file.Length -le $script:MaxPayloadFileBytes
}

function Get-ContainerGateContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CheckoutRoot)

    $pluginManifestPath = Join-Path $CheckoutRoot 'plugins/autopilot/plugin.json'
    if (-not (Test-GateCheckoutFile -CheckoutRoot $CheckoutRoot -Path $pluginManifestPath)) {
        throw "Autopilot plugin manifest is absent from '$CheckoutRoot'."
    }
    $plugin = Get-Content -LiteralPath $pluginManifestPath -Raw | ConvertFrom-Json -Depth 100
    $mappings = @($plugin.files)
    $dockerMapping = @($mappings | Where-Object {
            [string]::Equals([string]$_.src, 'devcontainer/Dockerfile', [System.StringComparison]::Ordinal)
        })
    if ($dockerMapping.Count -ne 1) { throw 'plugin.json must map devcontainer/Dockerfile exactly once.' }

    $dockerfilePath = Join-Path $CheckoutRoot "plugins/autopilot/$($dockerMapping[0].src)"
    if (-not (Test-GateCheckoutFile -CheckoutRoot $CheckoutRoot -Path $dockerfilePath)) {
        throw "Canonical Dockerfile is absent: '$dockerfilePath'."
    }
    $dockerfile = Get-Content -LiteralPath $dockerfilePath -Raw
    if ([regex]::IsMatch($dockerfile, '(?im)^\s*ADD\s+')) {
        throw 'Dockerfile ADD instructions are unsupported because path closure must remain local and explicit.'
    }
    if ([regex]::IsMatch($dockerfile, '(?im)^\s*COPY\b[^\r\n]*(?:\\|\x60)\s*$')) {
        throw 'Continued Dockerfile COPY instructions are unsupported because path closure must be unambiguous.'
    }
    $copySources = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($dockerfile, '(?im)^\s*COPY\s+(?:--[^\s]+\s+)*(?<body>[^\r\n]+?)\s*$')) {
        $body = $match.Groups['body'].Value.Trim()
        if ($body.StartsWith('[')) {
            $parts = @($body | ConvertFrom-Json)
            for ($index = 0; $index -lt $parts.Count - 1; $index++) {
                $copySources.Add((ConvertTo-GateRelativePath ([string]$parts[$index])))
            }
        }
        else {
            $parts = @($body -split '\s+' | Where-Object { $_ })
            for ($index = 0; $index -lt $parts.Count - 1; $index++) {
                $copySources.Add((ConvertTo-GateRelativePath $parts[$index]))
            }
        }
    }
    if ($copySources.Count -eq 0) { throw 'Dockerfile has no local COPY sources.' }

    $installedDockerfilePath = Join-Path $CheckoutRoot ".github/$($dockerMapping[0].dest)"
    $installedContextPath = Split-Path -Parent (Split-Path -Parent $installedDockerfilePath)
    $requiredSources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$requiredSources.Add('devcontainer/Dockerfile')
    [void]$requiredSources.Add('devcontainer/toolchain.tsv')
    [void]$requiredSources.Add('devcontainer/container-toolchain-smoke.sh')
    [void]$requiredSources.Add('scripts/launch-container.ps1')
    foreach ($source in $copySources) { [void]$requiredSources.Add($source) }
    foreach ($optionalSource in @('.dockerignore', 'devcontainer/Dockerfile.dockerignore')) {
        $canonicalOptional = Join-Path $CheckoutRoot "plugins/autopilot/$optionalSource"
        $installedOptional = Join-Path $installedContextPath $optionalSource
        if ((Test-Path -LiteralPath $canonicalOptional) -or (Test-Path -LiteralPath $installedOptional)) {
            [void]$requiredSources.Add($optionalSource)
        }
    }

    $payload = [System.Collections.Generic.List[object]]::new()
    foreach ($source in $requiredSources) {
        $mapping = @($mappings | Where-Object {
                [string]::Equals([string]$_.src, $source, [System.StringComparison]::Ordinal)
            })
        if ($mapping.Count -ne 1) { throw "plugin.json must map Docker input '$source' exactly once." }
        $destination = ConvertTo-GateRelativePath ([string]$mapping[0].dest)
        $installedPath = [System.IO.Path]::GetFullPath((Join-Path $CheckoutRoot ".github/$destination"))
        $expectedInstalledPath = [System.IO.Path]::GetFullPath((Join-Path $installedContextPath $source))
        if (-not [string]::Equals($installedPath, $expectedInstalledPath, [System.StringComparison]::Ordinal)) {
            throw "plugin.json destination for '$source' must preserve its path beneath the installed Docker build context."
        }
        $payload.Add([pscustomobject]@{
                Source = $source
                Destination = $destination
                CanonicalRelative = "plugins/autopilot/$source"
                InstalledRelative = ".github/$destination"
                CanonicalPath = Join-Path $CheckoutRoot "plugins/autopilot/$source"
                InstalledPath = $installedPath
            })
    }

    return [pscustomobject]@{
        PluginManifestPath = $pluginManifestPath
        DockerfilePath = $dockerfilePath
        InstalledDockerfilePath = $installedDockerfilePath
        InstalledContextPath = $installedContextPath
        Payload = @(Sort-GateOrdinal @($payload.Source) | ForEach-Object {
                $source = $_
                $payload | Where-Object {
                    [string]::Equals($_.Source, $source, [System.StringComparison]::Ordinal)
                }
            })
    }
}

function Get-ContainerGatePathSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CheckoutRoot)

    $context = Get-ContainerGateContext -CheckoutRoot $CheckoutRoot
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $installedContextRelative = [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($CheckoutRoot),
        [System.IO.Path]::GetFullPath($context.InstalledContextPath)
    ).Replace('\', '/')
    foreach ($entry in $context.Payload) {
        [void]$paths.Add($entry.CanonicalRelative)
        [void]$paths.Add($entry.InstalledRelative)
    }
    foreach ($owned in @(
            'plugins/autopilot/plugin.json',
            'plugins/autopilot/.dockerignore',
            'plugins/autopilot/devcontainer/Dockerfile.dockerignore',
            "$installedContextRelative/.dockerignore",
            "$installedContextRelative/devcontainer/Dockerfile.dockerignore",
            'scripts/skalary/Invoke-ContainerToolchainGate.ps1',
            '.github/workflows/autopilot-container-ci.yml',
            'tests/skalary/AutopilotContainer.Tests.ps1',
            'tests/skalary/AutopilotContainerGate.Tests.ps1'
        )) {
        [void]$paths.Add($owned)
    }
    return @(Sort-GateOrdinal @($paths))
}

function Test-ContainerPayloadParity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CheckoutRoot)

    try { $context = Get-ContainerGateContext -CheckoutRoot $CheckoutRoot }
    catch {
        # The contract error names the offending mapping or path; collapsing it to a category
        # leaves a red gate with nothing to act on.
        return [pscustomobject]@{
            Valid = $false
            Reason = 'context-absent'
            Detail = (Limit-GateText -Value $_.Exception.Message -Maximum 512)
            Entries = @()
            Context = $null
        }
    }
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $context.Payload) {
        $canonicalUsable = Test-GateCheckoutFile -CheckoutRoot $CheckoutRoot -Path $item.CanonicalPath
        $installedUsable = Test-GateCheckoutFile -CheckoutRoot $CheckoutRoot -Path $item.InstalledPath
        if (-not $canonicalUsable -or -not $installedUsable) {
            $missing = if (-not $canonicalUsable) { $item.CanonicalRelative } else { $item.InstalledRelative }
            $side = if (-not $canonicalUsable) { 'canonical' } else { 'installed' }
            return [pscustomobject]@{
                Valid = $false
                Reason = 'context-absent'
                Detail = "$side payload file is absent, unsafe, or oversized: '$missing'"
                Entries = @($entries)
                Context = $context
            }
        }
        $canonicalHash = Get-GateSha256 $item.CanonicalPath
        $installedHash = Get-GateSha256 $item.InstalledPath
        $entries.Add([ordered]@{
                source = $item.Source
                canonicalSha256 = $canonicalHash
                installedSha256 = $installedHash
            })
        if (-not [string]::Equals($canonicalHash, $installedHash, [System.StringComparison]::Ordinal)) {
            return [pscustomobject]@{
                Valid = $false
                Reason = 'payload-drift'
                Detail = ("'$($item.Source)' canonical=$($canonicalHash.Substring(0, 16)) " +
                    "installed=$($installedHash.Substring(0, 16))")
                Entries = @($entries)
                Context = $context
            }
        }
    }
    return [pscustomobject]@{ Valid = $true; Reason = ''; Detail = ''; Entries = @($entries); Context = $context }
}

function Get-GateChangedPaths {
    param([Parameter(Mandatory)][string]$CandidateRoot, [Parameter(Mandatory)][string]$BaseSha, [Parameter(Mandatory)][string]$CandidateSha)

    $result = Invoke-GateProcess -FilePath 'git' -ArgumentList @(
        '-C', $CandidateRoot, 'diff', '--name-status', '-z', '--find-renames', $BaseSha, $CandidateSha, '--'
    ) -TimeoutSeconds 30 -PreserveControlCharacters
    if ($result.ExitCode -ne 0) { throw "git diff failed: $($result.Stderr)" }
    if ($result.StdoutOverflow) { throw 'NUL-delimited git diff output exceeded the capture bound.' }

    $fields = @($result.Stdout.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries))
    $paths = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $fields.Count;) {
        $status = $fields[$index++]
        if ($status -notmatch '^(?<kind>[ACDMRTUXB])\d*$') { throw "Invalid git diff status '$status'." }
        if ($index -ge $fields.Count) { throw 'Truncated NUL-delimited git diff output.' }
        $paths.Add($fields[$index++])
        if ($Matches.kind -in @('R', 'C')) {
            if ($index -ge $fields.Count) { throw 'Truncated NUL-delimited rename/copy output.' }
            $paths.Add($fields[$index++])
        }
    }
    return @($paths)
}

function Get-ContainerGateDetection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseSha,
        [Parameter(Mandatory)][string]$CandidateSha,
        [Parameter(Mandatory)][string]$BaseRoot,
        [Parameter(Mandatory)][string]$CandidateRoot
    )

    Assert-GateSha BaseSha $BaseSha
    Assert-GateSha CandidateSha $CandidateSha
    $candidateFull = Assert-GateRoot CandidateRoot $CandidateRoot
    if ([string]::IsNullOrWhiteSpace($BaseRoot)) { throw 'BaseRoot is required.' }
    $baseFull = [System.IO.Path]::GetFullPath($BaseRoot)
    if (-not (Test-GateCheckoutHead -Root $candidateFull -Sha $CandidateSha)) {
        throw 'Candidate checkout HEAD does not equal CandidateSha.'
    }
    if ([string]::Equals($BaseSha, $script:ZeroSha, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'zero-base'; ChangedPaths = @(); RelevantPaths = @(); PathSet = @() }
    }
    if (-not (Test-Path -LiteralPath $baseFull -PathType Container)) {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'base-unreachable'; ChangedPaths = @(); RelevantPaths = @(); PathSet = @() }
    }
    if (-not (Test-GateCheckoutHead -Root $baseFull -Sha $BaseSha)) {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'base-unreachable'; ChangedPaths = @(); RelevantPaths = @(); PathSet = @() }
    }
    $commit = Invoke-GateProcess -FilePath 'git' -ArgumentList @('-C', $candidateFull, 'cat-file', '-e', "$BaseSha^{commit}") -TimeoutSeconds 15
    if ($commit.ExitCode -ne 0) {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'base-unreachable'; ChangedPaths = @(); RelevantPaths = @(); PathSet = @() }
    }
    try { $pathSet = @(Get-ContainerGatePathSet -CheckoutRoot $baseFull) }
    catch {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'base-context-absent'; ChangedPaths = @(); RelevantPaths = @(); PathSet = @() }
    }
    try { $changedPaths = @(Get-GateChangedPaths -CandidateRoot $candidateFull -BaseSha $BaseSha -CandidateSha $CandidateSha) }
    catch {
        return [pscustomobject]@{ Relevant = $true; CandidateOnlyReason = 'base-unreachable'; ChangedPaths = @(); RelevantPaths = @(); PathSet = $pathSet }
    }

    $owned = [System.Collections.Generic.HashSet[string]]::new([string[]]$pathSet, [System.StringComparer]::Ordinal)
    $relevantPathSet = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($changedPath in $changedPaths) {
        if ($owned.Contains($changedPath)) { [void]$relevantPathSet.Add($changedPath) }
    }
    $relevantPaths = @($relevantPathSet)
    return [pscustomobject]@{
        Relevant = $relevantPaths.Count -gt 0
        CandidateOnlyReason = ''
        ChangedPaths = @($changedPaths)
        RelevantPaths = @($relevantPaths)
        PathSet = $pathSet
    }
}

function Get-GateAptHost {
    <#
    .SYNOPSIS
        Extracts lowercase hosts from a recorded apt source URI list.
    .NOTES
        Returns $null when any line is not an http(s) URI: an unparsable origin record is a
        failed attestation, not an empty allowlist that passes by default.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$SourceText)

    $hosts = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in ($SourceText -split "`r?`n")) {
        $value = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $match = [regex]::Match($value, '^https?://(?<host>[^/:\s]+)(?::[0-9]+)?(?:/|$)')
        if (-not $match.Success) { return $null }
        [void]$hosts.Add($match.Groups['host'].Value.ToLowerInvariant())
    }
    if ($hosts.Count -eq 0) { return $null }
    return @($hosts)
}

function Test-GateAllowedAptHost {
    param(
        [AllowNull()][string[]]$Value,
        [Parameter(Mandatory)][string[]]$Allowed
    )

    if ($null -eq $Value -or @($Value).Count -eq 0) { return $false }
    foreach ($candidate in $Value) {
        if ($candidate -notin $Allowed) { return $false }
    }
    return $true
}

function Test-GateSmokeOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Output, [Parameter(Mandatory)][string]$ManifestPath)

    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($Output)
    if ($bytes -gt 65535 -or $Output.Contains("`r") -or $Output.TrimEnd("`n").Contains("`n") -or
        [regex]::IsMatch($Output, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]')) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke output is not one bounded JSON line.'; FailedCases = @(); Value = $null }
    }
    try { $value = $Output.TrimEnd("`n") | ConvertFrom-Json -Depth 20 }
    catch { return [pscustomobject]@{ Valid = $false; Summary = 'Smoke output is not valid JSON.'; FailedCases = @(); Value = $null } }
    try {
    if ((@($value.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'cases,digests,origin,schema,state') {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke object fields are not closed.'; FailedCases = @(); Value = $null }
    }
    if ($value.schema -isnot [string] -or $value.state -isnot [string] -or
        $value.schema -ne $script:SmokeSchema -or $value.state -notin @('pass', 'fail')) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke schema or state is invalid.'; FailedCases = @(); Value = $null }
    }
    if ((@($value.origin.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'aptHosts,os' -or
        (@($value.digests.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'manifestSha256,provenanceSha256') {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin or digest fields are not closed.'; FailedCases = @(); Value = $null }
    }
    foreach ($digest in @($value.digests.manifestSha256, $value.digests.provenanceSha256)) {
        if ($digest -isnot [string] -or $digest -notmatch '^[a-f0-9]{64}$') {
            return [pscustomobject]@{ Valid = $false; Summary = 'Smoke digest is invalid.'; FailedCases = @(); Value = $null }
        }
    }
    if ($value.origin.os -isnot [string] -or [string]::IsNullOrWhiteSpace($value.origin.os) -or
        $value.origin.aptHosts -isnot [System.Array] -or
        @($value.origin.aptHosts | Where-Object {
                $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or ([string]$_).Length -gt 253
            }).Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin fields are invalid.'; FailedCases = @(); Value = $null }
    }
    $expectedIds = @(Sort-GateOrdinal @(Get-Content -LiteralPath $ManifestPath | Where-Object {
            $_ -and -not $_.TrimStart().StartsWith('#')
        } | ForEach-Object { ($_ -split "`t", 3)[0] }))
    if ($expectedIds.Count -eq 0) {
        # An empty manifest would otherwise produce `0 cases; state=pass`: a green run that
        # exercised nothing, which is the one verdict this gate must never report.
        return [pscustomobject]@{ Valid = $false; Summary = 'Toolchain manifest declares no cases.'; FailedCases = @(); Value = $null }
    }
    $actualIds = [System.Collections.Generic.List[string]]::new()
    $failedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($value.cases)) {
        if ((@($case.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'id,state,version' -or
            $case.id -isnot [string] -or $case.state -isnot [string] -or $case.version -isnot [string] -or
            [string]::IsNullOrWhiteSpace($case.id) -or [string]::IsNullOrWhiteSpace($case.version) -or
            $case.state -notin @('pass', 'fail') -or
            ([string]$case.id).Length -gt 64 -or
            ([string]$case.version).Length -gt 128) {
            return [pscustomobject]@{ Valid = $false; Summary = 'Smoke case is invalid.'; FailedCases = @(); Value = $null }
        }
        if ($value.state -eq 'pass' -and $case.state -ne 'pass') {
            return [pscustomobject]@{ Valid = $false; Summary = 'Passing smoke output contains a failed case.'; FailedCases = @(); Value = $null }
        }
        $actualIds.Add([string]$case.id)
        if ($case.state -ne 'pass') { $failedIds.Add([string]$case.id) }
    }
    if (((Sort-GateOrdinal @($actualIds)) -join "`n") -cne ($expectedIds -join "`n")) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke case IDs do not match the manifest.'; FailedCases = @(); Value = $null }
    }
    if ($value.origin.os.Length -gt 64) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin fields exceed their bounds.'; FailedCases = @(); Value = $null }
    }
    # A failure count is not actionable; the failing case IDs are what a reader needs, so they
    # travel with the summary into the receipt and the job summary.
    $failed = @(Sort-GateOrdinal @($failedIds))
    $summary = "$($actualIds.Count) cases; state=$($value.state)"
    if ($failed.Count -gt 0) {
        $named = @($failed | Select-Object -First $script:MaxReceiptFailedCases)
        $summary += "; failed=$($failed.Count): " + ($named -join ',')
        if ($failed.Count -gt $named.Count) { $summary += ',...' }
    }
    return [pscustomobject]@{ Valid = $true; Summary = $summary; FailedCases = $failed; Value = $value }
    }
    catch {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke object shape is invalid.'; FailedCases = @(); Value = $null }
    }
}

function Get-GateAptConfigHost {
    <#
    .SYNOPSIS
        Returns every http(s) host named by a non-comment line under a copied /etc/apt tree.
    .NOTES
        This is deliberately conservative rather than directive-aware: any disallowed host
        appearing in a source-list file fails, which needs no model of apt's syntax and cannot
        be evaded by a form of source line this parser does not know. Comment lines are skipped
        because Debian's own `.sources` file names `snapshot.debian.org` in one, and only
        `sources.list`, `*.list` and `*.sources` are read so that binary keyrings cannot make
        the scan report a host. Returns $null when the tree cannot be read within its bounds.
    #>
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    $hosts = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'sources.list' -or $_.Extension -in @('.list', '.sources') })
    if ($files.Count -gt 256) { return $null }
    foreach ($file in $files) {
        if ($file.LinkType -or $file.Length -gt $script:MaxPayloadFileBytes) { return $null }
        foreach ($line in ([System.IO.File]::ReadAllLines($file.FullName))) {
            $value = $line.Trim()
            if (-not $value -or $value.StartsWith('#')) { continue }
            foreach ($match in [regex]::Matches($value, '(?i)\bhttps?://(?<authority>[^/\s]+)')) {
                # The whole authority is kept, port aside, exactly as `Get-GateAptHost` keeps it.
                # Narrowing to a host character class would stop at the userinfo delimiter, so
                # `https://download.docker.com@evil.example.com/...` — which apt resolves against
                # `evil.example.com` — would be reported as the allowed host, and the two parsers
                # holding the image to one allowlist would disagree about what a host is.
                $authority = $match.Groups['authority'].Value.ToLowerInvariant() -replace ':[0-9]+$', ''
                if ($authority) { [void]$hosts.Add($authority) }
            }
        }
    }
    return @($hosts)
}

function Test-GateImageAttestation {
    <#
    .SYNOPSIS
        Reads image contents from the trusted host instead of believing candidate smoke output.
    .DESCRIPTION
        The smoke program runs inside the candidate image and reports its own manifest digest
        and apt origins, so a hostile candidate can print a passing object while installing
        from anywhere. This copies the manifest, the recorded apt sources, and the image's live
        `/etc/apt` tree out with `docker cp` — a trusted-host read of the image filesystem —
        hashes and parses them here, and compares them against the trusted checkout and the
        origin allowlist. Smoke output is only believed where it agrees with this.

        What this does *not* establish: the recorded provenance files are written by the
        candidate's own Dockerfile, so a Dockerfile that installs from elsewhere and then
        rewrites both the record and `/etc/apt` still passes. This detects a lying smoke
        program and an inconsistent image, not a hostile build recipe; the recipe is what human
        review of the diff is for, and the design note records that limit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImageTag,
        [Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$TimeoutSeconds
    )

    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "skalary-attest-$([guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $workRoot -Force)
    $containerId = ''
    try {
        $create = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'create', '--network', 'none', $ImageTag, 'true'
        ) -TimeoutSeconds ([math]::Min(60, $TimeoutSeconds))
        if ($create.ExitCode -ne 0 -or $create.Stdout.Trim() -notmatch '^[a-f0-9]{12,64}$') {
            return [pscustomobject]@{ Valid = $false; Reason = 'attestation-container-unavailable'; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
        }
        $containerId = $create.Stdout.Trim()

        $copied = @{}
        foreach ($entry in @(
                @{ Name = 'manifest'; Source = $script:AttestedManifestPath },
                @{ Name = 'debianSources'; Source = $script:AttestedDebianSourcesPath },
                @{ Name = 'finalSources'; Source = $script:AttestedFinalSourcesPath }
            )) {
            $destination = Join-Path $workRoot $entry.Name
            $copy = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
                'cp', "${containerId}:$($entry.Source)", $destination
            ) -TimeoutSeconds ([math]::Min(60, $TimeoutSeconds))
            $item = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            if ($copy.ExitCode -ne 0 -or $item -isnot [System.IO.FileInfo] -or $item.LinkType -or
                $item.Length -le 0 -or $item.Length -gt $script:MaxPayloadFileBytes) {
                return [pscustomobject]@{ Valid = $false; Reason = "attestation-file-unreadable:$($entry.Source)"; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
            }
            $copied[$entry.Name] = $destination
        }

        $manifestSha = Get-GateSha256 $copied['manifest']
        if (-not [string]::Equals($manifestSha, $ExpectedManifestSha256.ToLowerInvariant(), [System.StringComparison]::Ordinal)) {
            return [pscustomobject]@{
                Valid = $false
                Reason = "attestation-manifest-mismatch:image=$($manifestSha.Substring(0, 16)) expected=$($ExpectedManifestSha256.Substring(0, 16))"
                ManifestSha256 = $manifestSha
                AptHosts = @()
                DebianAptHosts = @()
            }
        }

        $debianHosts = Get-GateAptHost -SourceText ([System.IO.File]::ReadAllText($copied['debianSources']))
        $finalHosts = Get-GateAptHost -SourceText ([System.IO.File]::ReadAllText($copied['finalSources']))
        if (-not (Test-GateAllowedAptHost -Value $debianHosts -Allowed $script:DebianAptHosts)) {
            return [pscustomobject]@{
                Valid = $false
                Reason = ('attestation-debian-origin-disallowed:' + (@($debianHosts) -join ','))
                ManifestSha256 = $manifestSha
                AptHosts = @()
                DebianAptHosts = @($debianHosts)
            }
        }
        if (-not (Test-GateAllowedAptHost -Value $finalHosts -Allowed $script:AllowedAptHosts)) {
            return [pscustomobject]@{
                Valid = $false
                Reason = ('attestation-origin-disallowed:' + (@($finalHosts) -join ','))
                ManifestSha256 = $manifestSha
                AptHosts = @($finalHosts)
                DebianAptHosts = @($debianHosts)
            }
        }

        # The record above is a file the image wrote about itself; this reads the configuration
        # apt actually carries, so a record that disagrees with the image it describes fails.
        $configRoot = Join-Path $workRoot 'etc-apt'
        $configCopy = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'cp', "${containerId}:/etc/apt", $configRoot
        ) -TimeoutSeconds ([math]::Min(60, $TimeoutSeconds))
        $liveHosts = if ($configCopy.ExitCode -eq 0) { Get-GateAptConfigHost -Root $configRoot } else { $null }
        if ($null -eq $liveHosts -or @($liveHosts).Count -eq 0) {
            return [pscustomobject]@{
                Valid = $false
                Reason = 'attestation-apt-config-unreadable'
                ManifestSha256 = $manifestSha
                AptHosts = @($finalHosts)
                DebianAptHosts = @($debianHosts)
            }
        }
        if (-not (Test-GateAllowedAptHost -Value $liveHosts -Allowed $script:AllowedAptHosts)) {
            return [pscustomobject]@{
                Valid = $false
                Reason = ('attestation-live-origin-disallowed:' + (@($liveHosts) -join ','))
                ManifestSha256 = $manifestSha
                AptHosts = @($finalHosts)
                DebianAptHosts = @($debianHosts)
            }
        }
        return [pscustomobject]@{
            Valid = $true
            Reason = ''
            ManifestSha256 = $manifestSha
            AptHosts = @($finalHosts)
            DebianAptHosts = @($debianHosts)
        }
    }
    finally {
        if ($containerId) {
            [void](Invoke-GateProcess -FilePath 'docker' -ArgumentList @('rm', '-f', $containerId) -TimeoutSeconds 30)
        }
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-GateSmokeAttestationAgreement {
    <#
    .SYNOPSIS
        Requires candidate smoke claims to agree with the trusted-host attestation.
    #>
    param(
        [Parameter(Mandatory)][object]$Smoke,
        [Parameter(Mandatory)][object]$Attestation
    )

    if (-not [string]::Equals([string]$Smoke.digests.manifestSha256, [string]$Attestation.ManifestSha256, [System.StringComparison]::Ordinal)) {
        return 'smoke-manifest-digest-forged'
    }
    $claimed = @(Sort-GateOrdinal @(@($Smoke.origin.aptHosts) | ForEach-Object { ([string]$_).ToLowerInvariant() }))
    $attested = @(Sort-GateOrdinal @($Attestation.AptHosts))
    if (($claimed -join ',') -cne ($attested -join ',')) {
        return ('smoke-origin-mismatch:claimed=' + ($claimed -join '|') + ' attested=' + ($attested -join '|'))
    }
    return ''
}

function Write-ContainerGateProvenance {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Provenance, [string]$Path)

    $content = (($Provenance | ConvertTo-Json -Depth 10 -Compress) + "`n")
    $sha256 = Get-GateTextSha256 $content
    if ($Path) {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $directory = Split-Path -Parent $fullPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
        [System.IO.File]::WriteAllText($fullPath, $content, [System.Text.UTF8Encoding]::new($false))
    }
    return $sha256
}

function Stop-GateContainer {
    param([Parameter(Mandatory)][string]$CidFile)

    if (-not (Test-Path -LiteralPath $CidFile -PathType Leaf)) { return }
    $containerId = (Get-Content -LiteralPath $CidFile -Raw).Trim()
    if ($containerId -notmatch '^[a-f0-9]{12,64}$') { return }
    $stop = Invoke-GateProcess -FilePath 'docker' -ArgumentList @('stop', '--time', '1', $containerId) -TimeoutSeconds 10
    if ($stop.ExitCode -ne 0 -or $stop.TimedOut) {
        [void](Invoke-GateProcess -FilePath 'docker' -ArgumentList @('kill', $containerId) -TimeoutSeconds 10)
    }
}

function New-ContainerGateReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('success', 'irrelevant', 'candidate-build-failed', 'candidate-smoke-failed', 'candidate-output-invalid', 'candidate-timeout', 'base-build-failed', 'base-timeout', 'unexpected-error')][string]$Outcome,
        [bool]$Relevant = $false,
        [ValidateSet('not-run', 'comparable', 'candidate-only')][string]$Comparison = 'not-run',
        [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift', 'base-build-failed', 'base-timeout')][string]$CandidateOnlyReason = '',
        [string]$BaseSha = '',
        [string]$CandidateSha = '',
        [string]$Architecture = '',
        [string]$BaseImageIdentity = '',
        [string]$DockerIdentity = '',
        [string]$CopilotVersion = '',
        [string]$ProvenanceSha256 = '',
        [int64]$CandidateBytes = 0,
        [int64]$BaseBytes = 0,
        [Nullable[int64]]$DeltaBytes = $null,
        [int64]$TotalMs = 0,
        [int64]$CandidateMs = 0,
        [int64]$BaseMs = 0,
        [string]$SmokeSummary = '',
        [AllowEmptyCollection()][string[]]$SmokeFailedCases = @(),
        [string]$Diagnostic = '',
        [int]$AdvisoryGrowthMiB = 250
    )

    $blocking = $Outcome -in @(
        'candidate-build-failed', 'candidate-smoke-failed', 'candidate-output-invalid',
        'candidate-timeout', 'unexpected-error'
    )
    $advisory = $null -ne $DeltaBytes -and $DeltaBytes -gt ([int64]$AdvisoryGrowthMiB * 1MB)
    $failedCases = @(@($SmokeFailedCases) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First $script:MaxReceiptFailedCases |
            ForEach-Object { Limit-GateText -Value $_ -Maximum 64 })
    return [ordered]@{
        schema = $script:GateSchema
        outcome = $Outcome
        relevant = $Relevant
        comparison = $Comparison
        candidateOnlyReason = $CandidateOnlyReason
        blocking = $blocking
        advisory = [bool]$advisory
        identities = [ordered]@{
            baseSha = (Limit-GateText $BaseSha 40).ToLowerInvariant()
            candidateSha = (Limit-GateText $CandidateSha 40).ToLowerInvariant()
            architecture = Limit-GateText $Architecture 32
            baseImage = Limit-GateText $BaseImageIdentity 256
            docker = Limit-GateText $DockerIdentity 256
            copilotVersion = Limit-GateText $CopilotVersion 64
        }
        provenance = [ordered]@{ sha256 = Limit-GateText $ProvenanceSha256 64 }
        timing = [ordered]@{ totalMs = [math]::Max([int64]0, $TotalMs); candidateMs = [math]::Max([int64]0, $CandidateMs); baseMs = [math]::Max([int64]0, $BaseMs) }
        measurement = [ordered]@{
            candidateBytes = [math]::Max([int64]0, $CandidateBytes)
            baseBytes = [math]::Max([int64]0, $BaseBytes)
            deltaBytes = $DeltaBytes
            advisoryGrowthMiB = $AdvisoryGrowthMiB
        }
        smoke = [ordered]@{
            summary = Limit-GateText $SmokeSummary 512
            failedCases = $failedCases
        }
        diagnostic = Limit-GateText $Diagnostic 1024
    }
}

function Write-ContainerGateReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Receipt, [Parameter(Mandatory)][string]$Path)

    $fallback = '{"schema":"skalary/container-toolchain-receipt@1","outcome":"unexpected-error","relevant":true,"comparison":"not-run","candidateOnlyReason":"","blocking":true,"advisory":false,"identities":{"baseSha":"","candidateSha":"","architecture":"","baseImage":"","docker":"","copilotVersion":""},"provenance":{"sha256":""},"timing":{"totalMs":0,"candidateMs":0,"baseMs":0},"measurement":{"candidateBytes":0,"baseBytes":0,"deltaBytes":null,"advisoryGrowthMiB":250},"smoke":{"summary":"","failedCases":[]},"diagnostic":"fallback receipt"}'
    try {
        $json = $Receipt | ConvertTo-Json -Depth 12 -Compress
        if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:MaxReceiptBytes) { $json = $fallback }
    }
    catch { $json = $fallback }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [System.IO.File]::WriteAllText($fullPath, "$json`n", [System.Text.UTF8Encoding]::new($false))
    return $json
}

function Write-ContainerGateSummary {
    <#
    .SYNOPSIS
        Renders the terminal receipt as the job summary a reviewer actually reads.
    .NOTES
        Sizes, delta, threshold, advisory state, and failing smoke cases live here because a
        summary that omits them makes a comparable green run indistinguishable from a
        candidate-only one without downloading and parsing the artifact.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Receipt, [Parameter(Mandatory)][string]$Path)

    $formatMiB = {
        param([AllowNull()][object]$Bytes)
        if ($null -eq $Bytes) { return 'n/a' }
        return ('{0:N1} MiB' -f ([double]$Bytes / 1MB))
    }
    $deltaBytes = $Receipt.measurement.deltaBytes
    $deltaText = if ($null -eq $deltaBytes) { 'not comparable' }
    else {
        $sign = if ([int64]$deltaBytes -ge 0) { '+' } else { '-' }
        $sign + (& $formatMiB ([math]::Abs([int64]$deltaBytes)))
    }
    $advisoryText = if ($Receipt.advisory) { 'over threshold (advisory)' }
    elseif ($null -eq $deltaBytes) { 'not evaluated' }
    else { 'within threshold' }
    $failedCases = @($Receipt.smoke.failedCases)
    $lines = @(
        '## Autopilot container toolchain',
        '',
        "- Outcome: **$(ConvertTo-GateMarkdown $Receipt.outcome)**",
        "- Blocking: $(ConvertTo-GateMarkdown ([string]$Receipt.blocking))",
        "- Relevant: $(ConvertTo-GateMarkdown ([string]$Receipt.relevant))",
        "- Comparison: $(ConvertTo-GateMarkdown $Receipt.comparison)",
        "- Candidate-only reason: $(ConvertTo-GateMarkdown $Receipt.candidateOnlyReason)",
        "- Candidate image: $(ConvertTo-GateMarkdown (& $formatMiB $Receipt.measurement.candidateBytes))",
        "- Base image: $(ConvertTo-GateMarkdown (& $formatMiB $Receipt.measurement.baseBytes))",
        "- Delta: $(ConvertTo-GateMarkdown $deltaText) (threshold $(ConvertTo-GateMarkdown ([string]$Receipt.measurement.advisoryGrowthMiB)) MiB — $(ConvertTo-GateMarkdown $advisoryText))",
        "- Timing: total $(ConvertTo-GateMarkdown ([string]$Receipt.timing.totalMs)) ms; candidate $(ConvertTo-GateMarkdown ([string]$Receipt.timing.candidateMs)) ms; base $(ConvertTo-GateMarkdown ([string]$Receipt.timing.baseMs)) ms",
        "- Smoke: $(ConvertTo-GateMarkdown $Receipt.smoke.summary)",
        "- Failed smoke cases: $(if ($failedCases.Count -gt 0) { ConvertTo-GateMarkdown (@($failedCases) -join ', ') } else { 'none' })",
        "- Diagnostic: $(ConvertTo-GateMarkdown $Receipt.diagnostic)",
        ('- Receipt provenance: `' + (ConvertTo-GateMarkdown $Receipt.provenance.sha256) + '`')
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [System.IO.File]::WriteAllText($fullPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Test-ContainerGateResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DetectorConclusion,
        [Parameter(Mandatory)][string]$Relevance,
        [Parameter(Mandatory)][string]$ImageConclusion
    )
    if ($DetectorConclusion -ne 'success' -or $Relevance -notin @('true', 'false')) { return $false }
    if ($Relevance -eq 'false') { return $ImageConclusion -eq 'skipped' }
    return $ImageConclusion -eq 'success'
}

function Invoke-ContainerToolchainGate {
    [CmdletBinding()]
    param(
        [ValidateSet('Detect', 'Measure', 'VerifyResult')][string]$Mode = 'Detect',
        [string]$BaseSha,
        [string]$CandidateSha,
        [string]$BaseRoot,
        [string]$CandidateRoot,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [string]$ProvenancePath,
        [string]$SummaryPath,
        [string]$DiagnosticLogPath,
        [string]$DetectorConclusion,
        [string]$Relevance,
        [string]$ImageConclusion,
        [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift')]
        [string]$DetectionCandidateOnlyReason,
        [ValidateSet('', 'true', 'false')]
        [string]$DetectionRelevance,
        [string]$CopilotVersion,
        [string]$RunnerArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant(),
        [int]$CandidateBudgetSeconds = 1500,
        [int]$BaseBudgetSeconds = 600,
        [int]$RunnerBudgetSeconds = 2100,
        [int]$AdvisoryGrowthMiB = 250
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $receipt = $null
    $exitCode = 1
    $comparison = 'not-run'
    $candidateOnlyReason = ''
    $candidateMs = [int64]0
    $baseMs = [int64]0
    $candidateBytes = [int64]0
    $baseBytes = [int64]0
    $deltaBytes = $null
    $smokeSummary = ''
    $baseImageIdentity = ''
    $dockerIdentity = ''
    $provenanceSha = ''
    $relevant = $true
    $baseParity = $null
    $smokeFailedCases = @()
    $contradictionDiagnostic = ''
    $candidatePhaseStartMs = $null
    $candidatePhaseEndMs = $null
    $basePhaseStartMs = $null
    try {
        if ($Mode -eq 'VerifyResult') {
            $passed = Test-ContainerGateResult -DetectorConclusion $DetectorConclusion -Relevance $Relevance -ImageConclusion $ImageConclusion
            $relevant = $Relevance -eq 'true'
            $outcome = if ($passed -and -not $relevant) { 'irrelevant' } elseif ($passed) { 'success' } else { 'unexpected-error' }
            $receipt = New-ContainerGateReceipt -Outcome $outcome -Relevant $relevant -Diagnostic "detector=$DetectorConclusion; relevance=$Relevance; image=$ImageConclusion" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            $exitCode = if ($passed) { 0 } else { 1 }
            return [pscustomobject]@{ ExitCode = $exitCode; Receipt = $receipt }
        }

        $detection = Get-ContainerGateDetection -BaseSha $BaseSha -CandidateSha $CandidateSha -BaseRoot $BaseRoot -CandidateRoot $CandidateRoot
        $relevant = [bool]$detection.Relevant
        $candidateOnlyReason = [string]$detection.CandidateOnlyReason
        if ($Mode -eq 'Measure' -and $DetectionCandidateOnlyReason) {
            $candidateOnlyReason = $DetectionCandidateOnlyReason
        }
        # The detector's relevance is the decision the gate's truth table already accepted. If
        # measurement re-derives irrelevance — a base that became usable between jobs, say — the
        # blocking candidate build would be skipped while the final table still reads
        # detector=true plus image=success. Contradiction resolves toward the blocking path.
        if ($Mode -eq 'Measure' -and $DetectionRelevance -eq 'true' -and -not $relevant) {
            $relevant = $true
            $contradictionDiagnostic = 'Detector reported relevant=true; measurement re-detection disagreed and was rejected.'
        }
        if ($Mode -eq 'Detect' -or -not $relevant) {
            $outcome = if ($relevant) { 'success' } else { 'irrelevant' }
            $comparison = if ($candidateOnlyReason) { 'candidate-only' } else { 'not-run' }
            $receipt = New-ContainerGateReceipt -Outcome $outcome -Relevant $relevant -Comparison $comparison `
                -CandidateOnlyReason $candidateOnlyReason -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture -Diagnostic ("relevantPaths=" + (@($detection.RelevantPaths) -join ',')) `
                -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            $exitCode = 0
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt; Detection = $detection }
        }

        $candidateRootFull = [System.IO.Path]::GetFullPath($CandidateRoot)
        $baseRootFull = [System.IO.Path]::GetFullPath($BaseRoot)
        $candidatePhaseStartSeconds = $clock.Elapsed.TotalSeconds
        $candidatePhaseStartMs = [int64]$clock.ElapsedMilliseconds
        $candidateParity = Test-ContainerPayloadParity -CheckoutRoot $candidateRootFull
        if (-not $candidateParity.Valid) {
            # Partial hash entries are exactly the evidence that identifies which file drifted,
            # so provenance is written before the failure return rather than left a placeholder.
            $provenanceSha = Write-ContainerGateProvenance -Provenance ([ordered]@{
                    schema = 'skalary/container-toolchain-provenance@1'
                    baseSha = $BaseSha.ToLowerInvariant()
                    candidateSha = $CandidateSha.ToLowerInvariant()
                    platform = 'linux/amd64'
                    parity = [ordered]@{
                        valid = $false
                        reason = $candidateParity.Reason
                        detail = (Limit-GateText -Value $candidateParity.Detail -Maximum 512)
                    }
                    payload = @($candidateParity.Entries)
                }) -Path $ProvenancePath
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha `
                -Diagnostic "Candidate payload parity: $($candidateParity.Reason): $($candidateParity.Detail)" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if (-not (Test-GateDockerfileBase -Path $candidateParity.Context.InstalledDockerfilePath)) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture -Diagnostic "Candidate Dockerfile must use only '$script:BaseImage'." -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }

        $provenanceDocument = [ordered]@{
            schema = 'skalary/container-toolchain-provenance@1'
            baseSha = $BaseSha.ToLowerInvariant()
            candidateSha = $CandidateSha.ToLowerInvariant()
            platform = 'linux/amd64'
            parity = [ordered]@{ valid = $true; reason = ''; detail = '' }
            payload = @($candidateParity.Entries)
        }
        $provenanceSha = Write-ContainerGateProvenance -Provenance $provenanceDocument -Path $ProvenancePath

        $remaining = [math]::Min(
            $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($remaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic 'Runner budget elapsed before base-image pull.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $pull = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'pull', '--platform', 'linux/amd64', $script:BaseImage
        ) -TimeoutSeconds $remaining
        if ($pull.TimedOut) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic 'Base image pull timed out.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if ($pull.ExitCode -ne 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-build-failed' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic $pull.Stderr -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $candidateRemaining = [math]::Min(
            $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($candidateRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic 'Candidate budget elapsed before image inspection.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $imageInspect = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'image', 'inspect', '--format', '{{.Os}}/{{.Architecture}} {{.Id}} {{join .RepoDigests ","}}', $script:BaseImage
        ) -TimeoutSeconds ([math]::Min(30, $candidateRemaining))
        if ($imageInspect.ExitCode -ne 0 -or $imageInspect.StdoutOverflow -or [string]::IsNullOrWhiteSpace($imageInspect.Stdout)) {
            throw 'Could not resolve the pulled base-image identity.'
        }
        $baseImageIdentity = $imageInspect.Stdout.Trim()
        if (-not $baseImageIdentity.StartsWith('linux/amd64 ', [System.StringComparison]::Ordinal)) {
            throw "Pulled base image does not resolve to linux/amd64: '$baseImageIdentity'."
        }
        $candidateRemaining = [math]::Min(
            $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($candidateRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -ProvenanceSha256 $provenanceSha -Diagnostic 'Candidate budget elapsed before daemon inspection.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $dockerInfo = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'version', '--format', '{{.Server.Version}}'
        ) -TimeoutSeconds ([math]::Min(30, $candidateRemaining))
        if ($dockerInfo.ExitCode -ne 0 -or $dockerInfo.StdoutOverflow -or [string]::IsNullOrWhiteSpace($dockerInfo.Stdout)) {
            throw 'Could not resolve the Docker daemon identity.'
        }
        $dockerIdentity = $dockerInfo.Stdout.Trim()

        if ([string]::IsNullOrWhiteSpace($CopilotVersion)) {
            $candidateRemaining = [math]::Min(
                $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
                $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
            )
            if ($candidateRemaining -le 0) {
                $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -ProvenanceSha256 $provenanceSha -Diagnostic 'Candidate budget elapsed before Copilot version resolution.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
                return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
            }
            # `npm` is a shim: `npm.cmd` on Windows, a plain executable elsewhere. Process.Start
            # resolves neither by shell, so the platform's actual file name is named here rather
            # than letting a local run die on a missing-file exception CI never sees.
            $npmFile = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [System.Runtime.InteropServices.OSPlatform]::Windows)) { 'npm.cmd' } else { 'npm' }
            # An unusable npm is not a gate failure: the Dockerfile's pinned ARG below is the
            # authoritative version anyway, and the registry probe only refreshes it.
            $versionResult = $null
            try {
                $versionResult = Invoke-GateProcess -FilePath $npmFile -ArgumentList @(
                    'view', '@github/copilot', 'version', '--json'
                ) -TimeoutSeconds ([math]::Min(30, $candidateRemaining))
            }
            catch { $versionResult = $null }
            if ($null -ne $versionResult -and $versionResult.ExitCode -eq 0 -and
                -not $versionResult.StdoutOverflow -and -not $versionResult.StdoutInvalidControl) {
                $CopilotVersion = $versionResult.Stdout.Trim().Trim('"')
            }
            if ([string]::IsNullOrWhiteSpace($CopilotVersion)) {
                $dockerfileText = Get-Content -LiteralPath $candidateParity.Context.InstalledDockerfilePath -Raw
                $versionMatch = [regex]::Match($dockerfileText, '(?m)^ARG COPILOT_CLI_VERSION=(?<version>[0-9A-Za-z.+-]+)$')
                if (-not $versionMatch.Success) { throw 'Could not resolve a Copilot CLI version.' }
                $CopilotVersion = $versionMatch.Groups['version'].Value
            }
        }
        if (-not (Test-GateConcreteVersion $CopilotVersion)) {
            throw 'CopilotVersion must be a concrete semantic version.'
        }

        $candidateTag = "skalary-autopilot-candidate-$($CandidateSha.Substring(0, 12).ToLowerInvariant())"
        $candidateRemaining = $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds)
        if ($candidateRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -Diagnostic 'Candidate budget elapsed before build.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $candidateBudget = [math]::Min($candidateRemaining, [math]::Max(1, $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)))
        $candidateBuild = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'build', '--pull=false', '--platform', 'linux/amd64',
            '--build-arg', "COPILOT_CLI_VERSION=$CopilotVersion",
            '--tag', $candidateTag, '--file', $candidateParity.Context.InstalledDockerfilePath,
            $candidateParity.Context.InstalledContextPath
        ) -TimeoutSeconds $candidateBudget
        $candidateMs += $candidateBuild.ElapsedMs
        if ($candidateBuild.TimedOut) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-build' -Result $candidateBuild
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -Diagnostic ('Candidate build timed out. ' + (Get-GateProcessDiagnostic -Result $candidateBuild -Maximum 900)) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if ($candidateBuild.ExitCode -ne 0) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-build' -Result $candidateBuild
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-build-failed' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -Diagnostic (Get-GateProcessDiagnostic -Result $candidateBuild) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $candidateRemaining = $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds)
        if ($candidateRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -Diagnostic 'Candidate budget elapsed before smoke.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $smokeBudget = [math]::Min($candidateRemaining, [math]::Min(300, [math]::Max(1, $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds))))
        $cidFile = Join-Path ([System.IO.Path]::GetTempPath()) "skalary-toolchain-$([guid]::NewGuid().ToString('N')).cid"
        $smoke = $null
        try {
            $smoke = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
                'run', '--rm', '--network', 'none', '--cidfile', $cidFile, $candidateTag, 'container-toolchain-smoke'
            ) -TimeoutSeconds $smokeBudget
        }
        finally {
            if ($null -ne $smoke -and $smoke.TimedOut) { Stop-GateContainer -CidFile $cidFile }
            Remove-Item -LiteralPath $cidFile -Force -ErrorAction SilentlyContinue
        }
        $candidateMs += $smoke.ElapsedMs
        if ($smoke.TimedOut) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-smoke' -Result $smoke
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -Diagnostic ('Candidate smoke timed out. ' + (Get-GateProcessDiagnostic -Result $smoke -Maximum 900)) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if ($smoke.StdoutOverflow -or $smoke.StdoutInvalidControl) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-smoke' -Result $smoke
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -Diagnostic 'Candidate smoke output exceeded its bound or contained forbidden control characters.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $installedManifestPath = Join-Path $candidateParity.Context.InstalledContextPath 'devcontainer/toolchain.tsv'
        $smokeValidation = Test-GateSmokeOutput -Output $smoke.Stdout -ManifestPath $installedManifestPath
        if (-not $smokeValidation.Valid) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-smoke' -Result $smoke
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeValidation.Summary -Diagnostic $smokeValidation.Summary -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $smokeSummary = $smokeValidation.Summary
        $smokeFailedCases = @($smokeValidation.FailedCases)
        if ($smoke.ExitCode -ne 0 -or $smokeValidation.Value.state -ne 'pass') {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-smoke' -Result $smoke
            $failedText = if ($smokeFailedCases.Count -gt 0) {
                'Failed smoke cases: ' + (@($smokeFailedCases) -join ', ') + '.'
            }
            else {
                'Candidate smoke reported failure without naming a case.'
            }
            $stderrTail = Get-GateProcessDiagnostic -Result $smoke -Maximum 512
            $diagnostic = if ([string]::IsNullOrWhiteSpace($stderrTail)) { $failedText } else { "$failedText $stderrTail" }
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-smoke-failed' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -SmokeFailedCases $smokeFailedCases -Diagnostic $diagnostic -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }

        # Candidate smoke has now claimed a pass. Nothing above proves the image installed what
        # the manifest says or resolved packages from an allowed origin, because every value in
        # that claim came from the candidate. Read the image from the trusted host and require
        # the claim to agree with it.
        $attestationBudget = [math]::Max(1, [math]::Min(
                $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
                $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
            ))
        $attestation = Test-GateImageAttestation -ImageTag $candidateTag `
            -ExpectedManifestSha256 (Get-GateSha256 $installedManifestPath) `
            -TimeoutSeconds ([math]::Min(180, $attestationBudget))
        if (-not $attestation.Valid) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic "Image attestation failed: $($attestation.Reason)" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $agreement = Test-GateSmokeAttestationAgreement -Smoke $smokeValidation.Value -Attestation $attestation
        if ($agreement) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic "Smoke output disagrees with image attestation: $agreement" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $smokeSummary += '; attested origins=' + (@($attestation.AptHosts) -join ',')
        $candidateRemaining = [math]::Min(
            $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($candidateRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic 'Candidate budget elapsed before size inspection.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $candidateSize = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'image', 'inspect', '--format', '{{.Size}}', $candidateTag
        ) -TimeoutSeconds ([math]::Min(30, $candidateRemaining))
        if ($candidateSize.TimedOut) {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs ($candidateMs + $candidateSize.ElapsedMs) -SmokeSummary $smokeSummary -Diagnostic 'Candidate size inspection timed out.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if ($candidateSize.ExitCode -ne 0 -or $candidateSize.Stdout.Trim() -notmatch '^\d+$') {
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -SmokeSummary $smokeSummary -Diagnostic 'Candidate image size is invalid.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $candidateBytes = [int64]$candidateSize.Stdout.Trim()
        $candidatePhaseEndMs = [int64]$clock.ElapsedMilliseconds

        if (-not $candidateOnlyReason) {
            $basePhaseStartMs = [int64]$clock.ElapsedMilliseconds
            $basePhaseStartSeconds = $clock.Elapsed.TotalSeconds
            $baseParity = Test-ContainerPayloadParity -CheckoutRoot $baseRootFull
            if ($baseParity.Reason -eq 'context-absent') { $candidateOnlyReason = 'base-context-absent' }
            elseif (-not $baseParity.Valid) { $candidateOnlyReason = 'base-payload-drift' }
            elseif (-not (Test-GateDockerfileBase -Path $baseParity.Context.InstalledDockerfilePath)) {
                $candidateOnlyReason = 'base-payload-drift'
            }
        }
        if ($candidateOnlyReason) {
            $comparison = 'candidate-only'
            $baseDetail = if ($candidateOnlyReason -in @('base-context-absent', 'base-payload-drift') -and $baseParity) {
                "Base payload: $($baseParity.Reason): $($baseParity.Detail)"
            }
            else { $contradictionDiagnostic }
            $receipt = New-ContainerGateReceipt -Outcome 'success' -Relevant $true -Comparison $comparison -CandidateOnlyReason $candidateOnlyReason -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic $baseDetail -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            $exitCode = 0
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        $baseTag = "skalary-autopilot-base-$($BaseSha.Substring(0, 12).ToLowerInvariant())"
        $baseBudget = [math]::Min(
            $BaseBudgetSeconds,
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($baseBudget -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'base-timeout' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-timeout' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic 'Runner budget elapsed before base build.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        $baseBuild = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'build', '--pull=false', '--platform', 'linux/amd64',
            '--build-arg', "COPILOT_CLI_VERSION=$CopilotVersion",
            '--tag', $baseTag, '--file', $baseParity.Context.InstalledDockerfilePath,
            $baseParity.Context.InstalledContextPath
        ) -TimeoutSeconds $baseBudget
        $baseMs = $baseBuild.ElapsedMs
        if ($baseBuild.TimedOut) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-build' -Result $baseBuild
            $receipt = New-ContainerGateReceipt -Outcome 'base-timeout' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-timeout' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -BaseMs $baseMs -SmokeSummary $smokeSummary -Diagnostic ('Base build timed out. ' + (Get-GateProcessDiagnostic -Result $baseBuild -Maximum 900)) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        if ($baseBuild.ExitCode -ne 0) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-build' -Result $baseBuild
            $receipt = New-ContainerGateReceipt -Outcome 'base-build-failed' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-build-failed' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -BaseMs $baseMs -SmokeSummary $smokeSummary -Diagnostic (Get-GateProcessDiagnostic -Result $baseBuild) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        $baseRemaining = [math]::Min(
            $BaseBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $basePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($baseRemaining -le 0) {
            $receipt = New-ContainerGateReceipt -Outcome 'base-timeout' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-timeout' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -BaseMs $baseMs -SmokeSummary $smokeSummary -Diagnostic 'Base budget elapsed before size inspection.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        $baseSize = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'image', 'inspect', '--format', '{{.Size}}', $baseTag
        ) -TimeoutSeconds ([math]::Min(30, $baseRemaining))
        if ($baseSize.TimedOut) {
            $receipt = New-ContainerGateReceipt -Outcome 'base-timeout' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-timeout' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -BaseMs ($baseMs + $baseSize.ElapsedMs) -SmokeSummary $smokeSummary -Diagnostic 'Base size inspection timed out.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        if ($baseSize.ExitCode -ne 0 -or $baseSize.Stdout.Trim() -notmatch '^\d+$') { throw 'Base image size is invalid.' }
        $baseBytes = [int64]$baseSize.Stdout.Trim()
        $deltaBytes = $candidateBytes - $baseBytes
        $comparison = 'comparable'
        $receipt = New-ContainerGateReceipt -Outcome 'success' -Relevant $true -Comparison $comparison -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -BaseBytes $baseBytes -DeltaBytes $deltaBytes -CandidateMs $candidateMs -BaseMs $baseMs -SmokeSummary $smokeSummary -Diagnostic $contradictionDiagnostic -AdvisoryGrowthMiB $AdvisoryGrowthMiB
        $exitCode = 0
        return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
    }
    catch {
        $receipt = New-ContainerGateReceipt -Outcome 'unexpected-error' -Relevant $relevant -Comparison $comparison `
            -CandidateOnlyReason $candidateOnlyReason -BaseSha $BaseSha -CandidateSha $CandidateSha `
            -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity `
            -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes `
            -BaseBytes $baseBytes -DeltaBytes $deltaBytes -CandidateMs $candidateMs -BaseMs $baseMs `
            -SmokeSummary $smokeSummary -Diagnostic $_.Exception.Message -AdvisoryGrowthMiB $AdvisoryGrowthMiB
        return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
    }
    finally {
        $clock.Stop()
        if ($null -eq $receipt) {
            $receipt = New-ContainerGateReceipt -Outcome 'unexpected-error' -Relevant $true -Diagnostic 'No terminal receipt was produced.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
        }
        $receipt.timing.totalMs = [int64]$clock.ElapsedMilliseconds
        if ($null -ne $candidatePhaseStartMs) {
            $candidateEndMs = if ($null -ne $candidatePhaseEndMs) {
                $candidatePhaseEndMs
            }
            elseif ($null -ne $basePhaseStartMs) {
                $basePhaseStartMs
            }
            else {
                [int64]$clock.ElapsedMilliseconds
            }
            $receipt.timing.candidateMs = [math]::Max([int64]0, $candidateEndMs - $candidatePhaseStartMs)
        }
        if ($null -ne $basePhaseStartMs) {
            $receipt.timing.baseMs = [math]::Max([int64]0, [int64]$clock.ElapsedMilliseconds - $basePhaseStartMs)
        }
        $json = Write-ContainerGateReceipt -Receipt $receipt -Path $ReceiptPath
        if ($SummaryPath) { Write-ContainerGateSummary -Receipt $receipt -Path $SummaryPath }
        Write-Host $json
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { throw 'ReceiptPath is required.' }
    $result = Invoke-ContainerToolchainGate @PSBoundParameters
    exit $result.ExitCode
}
