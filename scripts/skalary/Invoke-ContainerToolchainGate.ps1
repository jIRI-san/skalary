#requires -Version 7.0
<#
.SYNOPSIS
    Detects, measures, and reports the autopilot container toolchain gate.
.NOTES
    The parameter block below and `Invoke-ContainerToolchainGate`'s parameter block are one
    contract stated twice: PowerShell needs a script-level block to be callable as a file and a
    function-level block to be callable after dot-sourcing. They are kept attribute-identical, and
    `test:AutopilotContainer.GateRunnerContract` compares the two reflectively so a validation
    attribute added to one and not the other is red rather than a silent difference between how CI
    invokes the runner and how the tests do.
#>
[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Measure', 'VerifyResult', 'Initialize')]
    [string]$Mode = 'Detect',
    [string]$BaseSha,
    [string]$CandidateSha,
    [string]$BaseRoot,
    [string]$CandidateRoot,
    [string]$ReceiptPath,
    [string]$ProvenancePath,
    [string]$SummaryPath,
    [string]$DiagnosticLogPath,
    [string]$StepOutputPath,
    [string]$Diagnostic,
    [string]$DetectorConclusion,
    [string]$Relevance,
    [string]$ImageConclusion,
    [ValidateSet('', 'not-run', 'comparable', 'candidate-only')]
    [string]$MeasurementComparison,
    [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift', 'base-build-failed', 'base-timeout')]
    [string]$MeasurementCandidateOnlyReason,
    [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift')]
    [string]$DetectionCandidateOnlyReason,
    [ValidateSet('', 'true', 'false')]
    [string]$DetectionRelevance,
    [ValidatePattern('^\d{0,6}$')]
    [string]$RelevantPathCount,
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
# An apt configuration file is parsed character by character on the host, so its size is the
# host's cost, not the image's. Debian's own files are single-digit kilobytes; the cap is three
# orders of magnitude above that and still bounds the scan, and a file over it fails the read
# closed rather than being skipped — a scan that cannot afford to read a file has not read it.
$script:MaxAptConfigFileBytes = 256KB
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
# Every whole-run failure the smoke program can hit outside an individual case. Without these a
# gate failure caused by, say, an unreadable manifest reports `state=fail` and nothing else, and
# the receipt has to say "reported failure without naming a case" — a red gate with no diagnosis.
$script:AllowedSmokeReasons = @(
    'case-count-mismatch',
    'encoder-failed',
    'manifest-digest-unavailable',
    'manifest-duplicate-case',
    'manifest-unreadable',
    'not-autopilot-user',
    'output-oversize',
    'provenance-digest-unavailable',
    'provenance-incomplete',
    'usr-local-bin-writable'
)
# Every transport apt ships a `/usr/lib/apt/methods/` binary for. A source naming one of these
# with no authority — `file:/srv/repo`, `cdrom:[...]/` — is still an origin, and the allowlist
# holds only hostnames, so naming the scheme is what makes such a source fail rather than vanish.
$script:AptTransportScheme = @(
    'cdrom', 'copy', 'file', 'ftp', 'http', 'https', 'mirror', 'rsh', 's3', 'ssh', 'store', 'tor'
)
# Everything above holds the image to a set of *hostnames*. A proxy defeats that check without
# touching a single one of them: apt still asks for `deb.debian.org`, and whatever the proxy points
# at answers. So a proxy directive is refused outright rather than reconciled with the allowlist,
# and the test is deny-by-default on the segment — any tag segment containing `proxy` — because the
# forms are not a closed set (`Acquire::http::Proxy`, `::Proxy::deb.debian.org`, `Proxy-Auto-Detect`,
# `ProxyAutoDetect`, and the same under every transport). The cost is an unquoted value containing
# the word failing the read; the values Debian's own files carry are quoted, and this reader empties
# a quoted value before the test runs.
$script:AptProxyTagPattern = '(?i)(?<=^|[\s{};]|::)[A-Za-z0-9._+-]*proxy[A-Za-z0-9._+-]*(?![A-Za-z0-9._+-])'
# A proxy substitutes the bytes; these accept them unsigned. Either half alone is enough — an
# unauthenticated fetch from a proxied `deb.debian.org` installs whatever answered — so the
# authentication settings are refused on the same terms as the proxy ones: by segment, in any
# scope, whatever value is assigned. Asserting "not true" would need this reader to agree with
# apt's `StringToBool` on every spelling of true, and a disagreement there is silent. Debian's own
# `apt.conf.d` files assign none of these, so refusing the segment blocks no honest image.
$script:AptTrustTagPattern = '(?i)(?<=^|[\s{};]|::)(?:Allow[A-Za-z0-9-]*|Trust[A-Za-z0-9-]*|Untrusted|Unauthenticated|Insecure[A-Za-z0-9-]*|Weak[A-Za-z0-9-]*|Check-Valid-Until|Check-Date|Verify-Peer|Verify-Host|CaInfo|CaPath|gpgv)(?![A-Za-z0-9._+-])'
# The same bypass written in the source list rather than the configuration: `deb [trusted=yes] …`
# and deb822's `Trusted: yes` tell apt to install from that origin without a valid signature, and
# `allow-insecure` / `allow-weak` / `allow-downgrade-to-insecure` are the per-source spellings of
# the configuration keys above. Only an explicitly false value passes, so a form this reader cannot
# evaluate — an empty field, a continuation line, an unfamiliar word — fails closed.
$script:AptSourceTrustPattern = '(?i)(?<![A-Za-z0-9._+-])(?:trusted|allow-insecure|allow-weak|allow-downgrade-to-insecure)[ \t]*[:=][ \t]*(?<value>[A-Za-z0-9]*)'
$script:AptSourceTrustFalse = @('no', 'false', '0')
# apt reads `APT_CONFIG` before it reads anything under `/etc/apt`, and the file it names may
# relocate every path this gate enumerates. An image needs no such variable — a setting it wants
# can live in `apt.conf.d`, where this gate can read it — so any non-empty value is refused, which
# is apt's own condition for honouring it. Proxy variables are refused for the reason above: they
# redirect the fetch while every hostname in the tree stays allowlisted.
$script:ImageEnvProxyPattern = '(?i)proxy'
$script:MaxImageEnvEntries = 256
$script:MaxImageEnvBytes = 65536

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
    param([ValidateRange(1024, 67108864)][int]$Maximum = $script:MaxProcessOutput)

    # The head bound scales with the total bound so a larger capture keeps a proportionally larger
    # invocation context instead of a fixed 16 KiB head followed by megabytes of tail.
    $head = [math]::Max(1024, [math]::Min($script:ProcessHeadChars, [int]($Maximum / 4)))
    return @{
        Head = [System.Text.StringBuilder]::new()
        Tail = [System.Text.StringBuilder]::new()
        Maximum = $Maximum
        HeadMaximum = $head
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
    $headRoom = $State.HeadMaximum - $State.Head.Length
    if ($headRoom -gt 0) {
        $take = [math]::Min($headRoom, $Chunk.Length)
        [void]$State.Head.Append($Chunk, 0, $take)
        $offset = $take
    }
    if ($offset -ge $Chunk.Length) { return }

    [void]$State.Tail.Append($Chunk, $offset, $Chunk.Length - $offset)
    $tailMaximum = $State.Maximum - $State.HeadMaximum - 128
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
    .NOTES
        Stages that fail without a child process — a payload-parity mismatch, a rejected image
        attestation — pass `-Note` instead of `-Result`. Before that, every blocking outcome
        outside build and smoke reached the artifact with nothing but the receipt's 1024-character
        diagnostic, which is the one place a reader looks after the runner is gone.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Result')]
    param(
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory, ParameterSetName = 'Result')][object]$Result,
        [Parameter(Mandatory, ParameterSetName = 'Note')][AllowEmptyString()][string]$Note
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $lines = if ($PSCmdlet.ParameterSetName -eq 'Note') {
        @("stage: $Stage", '--- note ---', (Limit-GateText -Value $Note -Maximum $script:MaxProcessOutput))
    }
    else {
        @(
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
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    # Stages append: a candidate build failure followed by a smoke failure are two separate facts,
    # and overwriting would leave only the last one.
    [System.IO.File]::AppendAllText($fullPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Write-GateStepOutput {
    <#
    .SYNOPSIS
        Appends `name=value` step outputs for the calling workflow.
    .NOTES
        Values are constrained to a short safe alphabet before they are written. `$GITHUB_OUTPUT`
        is line-oriented, so a value containing a newline injects an output the runner never
        intended to set; refusing rather than escaping keeps the closed vocabularies this gate
        emits (`true`/`false`, the candidate-only reason set) the only thing that can appear.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Value
    )

    $lines = foreach ($entry in $Value.GetEnumerator()) {
        $name = [string]$entry.Key
        $text = [string]$entry.Value
        if ($name -notmatch '^[a-z][a-z0-9_]{0,63}$') { throw "Refusing to write step output '$name'." }
        if ($text.Length -gt 128 -or $text -notmatch '^[A-Za-z0-9._-]*$') {
            throw "Refusing to write step output '$name' with an unsafe value."
        }
        "$name=$text"
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [System.IO.File]::AppendAllText($fullPath, ((@($lines) -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-GateProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$TimeoutSeconds,
        [string]$WorkingDirectory,
        [ValidateRange(1024, 67108864)][int]$MaxOutputChars = $script:MaxProcessOutput,
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
        # A Docker build emits tens of megabytes of progress; a 4 KiB buffer turns that into
        # thousands of round trips through the loop below. The buffer is sized to the pipe, not
        # to the retained capture, because reading is what has to keep up with the child.
        $stdoutBuffer = [char[]]::new(65536)
        $stderrBuffer = [char[]]::new(65536)
        $stdoutState = New-GateCaptureState -Maximum $MaxOutputChars
        $stderrState = New-GateCaptureState -Maximum $MaxOutputChars
        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length)
        $stderrTask = $process.StandardError.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
        $timedOut = $false
        $drainDeadline = [TimeSpan]::MaxValue

        while (-not ($stdoutState.Done -and $stderrState.Done)) {
            # Waiting on the pending reads costs nothing while the child is quiet and returns the
            # instant either stream produces bytes. An unconditional sleep did both jobs badly: it
            # burned wakeups on an idle child and added latency to a chatty one.
            $pending = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
            if (-not $stdoutState.Done) { $pending.Add($stdoutTask) }
            if (-not $stderrState.Done) { $pending.Add($stderrTask) }
            if ($pending.Count -gt 0) {
                $waitMs = if ($timedOut) { 100 } else {
                    $left = ($TimeoutSeconds * 1000) - $clock.ElapsedMilliseconds
                    [int][math]::Max(1, [math]::Min(1000, $left))
                }
                [void][System.Threading.Tasks.Task]::WaitAny($pending.ToArray(), $waitMs)
            }

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
    # `COPY --from=` names a stage or a registry image, not a path in the build context. The
    # source is therefore not a local payload file, but the parser below strips flags and then
    # treats every source as one — so `COPY --from=attacker/image devcontainer/toolchain.tsv /x`
    # would enter the payload set as a hash-verified local file while the image actually copies
    # bytes nobody in this repository controls. This Dockerfile has a single `FROM`, so there is
    # no legitimate `--from` to preserve.
    if ([regex]::IsMatch($dockerfile, '(?im)^\s*COPY\s+(?:--[^\s]+\s+)*--from=')) {
        throw 'Dockerfile COPY --from is unsupported because its source is not a local build-context path.'
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
        $expectedInstalledPath = [System.IO.Path]::GetFullPath((Join-Path $installedContextPath $source))
        $mapping = @($mappings | Where-Object {
                $candidateDestination = ConvertTo-GateRelativePath ([string]$_.dest)
                $candidateInstalledPath = [System.IO.Path]::GetFullPath(
                    (Join-Path $CheckoutRoot ".github/$candidateDestination")
                )
                [string]::Equals(
                    $candidateInstalledPath,
                    $expectedInstalledPath,
                    [System.StringComparison]::Ordinal
                )
            })
        if ($mapping.Count -ne 1) {
            throw "plugin.json must install Docker input '$source' exactly once beneath its build context."
        }
        $destination = ConvertTo-GateRelativePath ([string]$mapping[0].dest)
        $installedPath = [System.IO.Path]::GetFullPath((Join-Path $CheckoutRoot ".github/$destination"))
        $canonicalSource = ConvertTo-GateRelativePath ([string]$mapping[0].src)
        $payload.Add([pscustomobject]@{
                Source = $source
                Destination = $destination
                CanonicalRelative = "plugins/autopilot/$canonicalSource"
                InstalledRelative = ".github/$destination"
                CanonicalPath = Join-Path $CheckoutRoot "plugins/autopilot/$canonicalSource"
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
    <#
    .NOTES
        The capture bound is raised for this call alone. `git diff --name-status -z` between two
        distant commits can emit far more than the 1 MiB a build log is bounded to, and the bound
        being hit throws — so a legitimately large diff reported "output exceeded the capture
        bound" and the gate failed for a reason that had nothing to do with the change.
        `StdoutOverflow` still throws, because a truncated path list would silently under-report
        relevance, which is the one direction this detector must never fail in.
    #>
    param([Parameter(Mandatory)][string]$CandidateRoot, [Parameter(Mandatory)][string]$BaseSha, [Parameter(Mandatory)][string]$CandidateSha)

    $result = Invoke-GateProcess -FilePath 'git' -ArgumentList @(
        '-C', $CandidateRoot, 'diff', '--name-status', '-z', '--find-renames', $BaseSha, $CandidateSha, '--'
    ) -TimeoutSeconds 30 -MaxOutputChars 4194304 -PreserveControlCharacters
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
    if ((@($value.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'cases,digests,origin,reasons,schema,state') {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke object fields are not closed.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    if ($value.schema -isnot [string] -or $value.state -isnot [string] -or
        $value.schema -ne $script:SmokeSchema -or $value.state -notin @('pass', 'fail')) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke schema or state is invalid.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    # `reasons` names the whole-run failures that no case can carry — an unreadable manifest, a
    # writable `/usr/local/bin`, a run that is not `autopilot`. Without it those ten conditions
    # all reported a bare `state=fail` with an empty failed-case list, and the receipt could say
    # only that the smoke program had failed without saying what it found. The vocabulary is
    # closed so a hostile or broken image cannot use it as a free-text channel into the summary.
    if ($value.reasons -isnot [System.Array]) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke reasons field is not an array.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    $reasons = @($value.reasons)
    if ($reasons.Count -gt $script:AllowedSmokeReasons.Count -or
        @($reasons | Where-Object { $_ -isnot [string] -or $_ -notin $script:AllowedSmokeReasons }).Count -gt 0 -or
        @($reasons | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke reasons are not a closed set.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    if ($value.state -eq 'pass' -and $reasons.Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Passing smoke output reports a failure reason.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    $reasons = @(Sort-GateOrdinal @($reasons | ForEach-Object { [string]$_ }))
    # A failing run reports what it can. The whole-run fallbacks — an encoder that died, an
    # oversize payload — emit empty digests and no cases *because* the run failed, and rejecting
    # them for that turned a named diagnosis (`encoder-failed`, `output-oversize`) into the
    # generic `candidate-output-invalid`, discarding the one thing the smoke program managed to
    # say. A failing run that named a closed reason therefore keeps its reasons even when the
    # evidence they would have accompanied is absent. Nothing here relaxes for `state=pass`:
    # a passing claim still has to produce well-formed digests, origins, and the full case set,
    # because attestation agreement is checked against exactly those fields.
    $degraded = ($value.state -eq 'fail' -and $reasons.Count -gt 0)
    if ((@($value.origin.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'aptHosts,os' -or
        (@($value.digests.PSObject.Properties.Name | Sort-Object) -join ',') -ne 'manifestSha256,provenanceSha256') {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin or digest fields are not closed.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    if (-not $degraded) {
        foreach ($digest in @($value.digests.manifestSha256, $value.digests.provenanceSha256)) {
            if ($digest -isnot [string] -or $digest -notmatch '^[a-f0-9]{64}$') {
                return [pscustomobject]@{ Valid = $false; Summary = 'Smoke digest is invalid.'; FailedCases = @(); Reasons = @(); Value = $null }
            }
        }
        if ($value.origin.os -isnot [string] -or [string]::IsNullOrWhiteSpace($value.origin.os) -or
            $value.origin.aptHosts -isnot [System.Array] -or
            @($value.origin.aptHosts | Where-Object {
                    $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or ([string]$_).Length -gt 253
                }).Count -gt 0) {
            return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin fields are invalid.'; FailedCases = @(); Reasons = @(); Value = $null }
        }
    }
    $expectedIds = @(Sort-GateOrdinal @(Get-Content -LiteralPath $ManifestPath | Where-Object {
            $_ -and -not $_.TrimStart().StartsWith('#')
        } | ForEach-Object { ($_ -split "`t", 3)[0] }))
    if ($expectedIds.Count -eq 0) {
        # An empty manifest would otherwise produce `0 cases; state=pass`: a green run that
        # exercised nothing, which is the one verdict this gate must never report.
        return [pscustomobject]@{ Valid = $false; Summary = 'Toolchain manifest declares no cases.'; FailedCases = @(); Reasons = @(); Value = $null }
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
            return [pscustomobject]@{ Valid = $false; Summary = 'Smoke case is invalid.'; FailedCases = @(); Reasons = @(); Value = $null }
        }
        if ($value.state -eq 'pass' -and $case.state -ne 'pass') {
            return [pscustomobject]@{ Valid = $false; Summary = 'Passing smoke output contains a failed case.'; FailedCases = @(); Reasons = @(); Value = $null }
        }
        $actualIds.Add([string]$case.id)
        if ($case.state -ne 'pass') { $failedIds.Add([string]$case.id) }
    }
    if (((Sort-GateOrdinal @($actualIds)) -join "`n") -cne ($expectedIds -join "`n")) {
        # A case set that does not match the manifest is the one failure the smoke program is
        # allowed to report about itself rather than being called invalid: it says so, and this
        # agrees. Every degraded failure lands here — the fallbacks emit no cases at all — so the
        # reason set, not `case-count-mismatch` alone, is what earns the diagnosis a receipt.
        if ($degraded) {
            $summary = "case ids do not match the manifest; state=fail; reasons=" + ($reasons -join ',')
            if ($reasons -notcontains 'case-count-mismatch') { $summary += '; digests unavailable' }
            return [pscustomobject]@{ Valid = $true; Summary = $summary; FailedCases = @(); Reasons = $reasons; Value = $value }
        }
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke case IDs do not match the manifest.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    if (-not $degraded -and $value.origin.os.Length -gt 64) {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke origin fields exceed their bounds.'; FailedCases = @(); Reasons = @(); Value = $null }
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
    if ($reasons.Count -gt 0) { $summary += '; reasons=' + ($reasons -join ',') }
    if ($value.state -eq 'fail' -and $failed.Count -eq 0 -and $reasons.Count -eq 0) {
        # `state=fail` with neither a failing case nor a reason is a verdict with no diagnosis.
        return [pscustomobject]@{ Valid = $false; Summary = 'Failing smoke output names neither a case nor a reason.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
    return [pscustomobject]@{ Valid = $true; Summary = $summary; FailedCases = $failed; Reasons = $reasons; Value = $value }
    }
    catch {
        return [pscustomobject]@{ Valid = $false; Summary = 'Smoke object shape is invalid.'; FailedCases = @(); Reasons = @(); Value = $null }
    }
}

function Test-GateReparseItem {
    <#
    .SYNOPSIS
        True when a filesystem item is a link or reparse point rather than the thing it names.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

    if (-not [string]::IsNullOrEmpty($Item.LinkType)) { return $true }
    return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Get-GateAptConfigToken {
    <#
    .SYNOPSIS
        A bounded, candidate-safe name for a file under the copied /etc/apt tree.
    .NOTES
        The path is read out of the candidate image, so it is untrusted text that travels into a
        diagnostics log, a receipt, and a job summary. It is reduced to a fixed alphabet and 64
        characters here: enough to say which file failed the read, too little to carry control
        characters, markup, or a payload into the artifacts a reviewer opens.
    #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)

    $relative = $Path
    if ($Path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $Path.Substring($Root.Length)
    }
    $relative = ($relative -replace '\\', '/').Trim('/')
    $relative = [regex]::Replace($relative, '[^A-Za-z0-9._/-]', '_')
    if ($relative.Length -gt 64) { $relative = $relative.Substring(0, 64) }
    if (-not $relative) { return 'unnamed' }
    return $relative
}

function ConvertTo-GateAptConfigStatement {
    <#
    .SYNOPSIS
        Reduces an apt configuration file to the directive text apt itself would act on.
    .NOTES
        A line-at-a-time scan cannot decide this file, and the gap is not academic: apt's parser
        accumulates text across lines until an unquoted `{`, `;` or `}`, and strips comments before
        that accumulation. `Dir` on one line and `{ Etc { sourcelist "/opt/hidden"; };` on the next
        is one statement to apt and two harmless-looking lines to a line scanner, and `D/*x*/ir`
        is the token `Dir` to apt and no token at all on disk. So the file is normalized once,
        the way apt normalizes it, and the directive test runs on the result:

        - `/* … */` is removed with nothing in its place, because apt splices the surrounding
          fragments together — inserting a space here would let comment-splicing hide a token.
          An unterminated one runs to end of file, as it does for apt.
        - `//` and non-magic `#` comments run to end of line, and both are recognized only outside
          quotes: `Acquire::http::Proxy "http://p:3128"; Dir::Etc::sourcelist "/x";` contains a
          `//` inside a string, and a quote-blind strip would delete the real directive after it.
        - `#include`, `#clear` and `#x-apt-configure-index` are apt's magic comments and are *not*
          comments; the first two are kept for the directive test to find. apt honours them at any
          offset a statement can begin, not only at column zero, so neither is anchored here.
        - Quotes are handled by position, because apt strips them from the *word* it parses. In a
          value they are emptied, which stops a path or URL that merely contains `Dir` from failing
          an honest image. In the tag they are spliced out and the contents kept, because apt reads
          `D"i"r::Etc::sourcelist` and `"#include"` as the tag `Dir::Etc::sourcelist` and the
          directive `#include`, and a reader that emptied them would be shown nothing at all.
        - `%XX` escapes are decoded, because apt decodes them while parsing a word: `%44ir` is the
          tag `Dir` and `%23include` is an active include. Decoding happens after comments are
          stripped, exactly as it does for apt, so a decoded `#` or `/` cannot forge a comment.
        - Newlines and runs of whitespace collapse to one space, which is how apt joins the lines
          of a statement.

        The cost of that fidelity is a quoted list element — `APT::NeverAutoRemove { "^linux-.*"; }`
        — being read in tag position, so a list of paths naming `Dir` fails the read. That is the
        deliberate direction to be wrong in: the alternative is a tag the candidate can spell in a
        way this reader cannot see.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $builder = [System.Text.StringBuilder]::new()
    $index = 0
    $length = $Text.Length
    # A statement's first word is its tag; everything after it is a value. Quotes mean different
    # things in the two positions, so the scan tracks which one it is in.
    $inTag = $true
    $tagStarted = $false
    while ($index -lt $length) {
        $character = $Text[$index]
        if ($character -eq '"') {
            $close = $Text.IndexOf('"', $index + 1)
            $content = if ($close -lt 0) {
                $Text.Substring($index + 1)
            }
            else {
                $Text.Substring($index + 1, $close - $index - 1)
            }
            if ($inTag) {
                # apt strips the quotes and keeps the contents, joined to whatever surrounds them.
                [void]$builder.Append($content)
            }
            else {
                [void]$builder.Append('""')
            }
            $tagStarted = $true
            if ($close -lt 0) { break }
            $index = $close + 1
            continue
        }
        if ($character -eq '/' -and $index + 1 -lt $length -and $Text[$index + 1] -eq '*') {
            $close = $Text.IndexOf('*/', $index + 2, [System.StringComparison]::Ordinal)
            if ($close -lt 0) { break }
            $index = $close + 2
            continue
        }
        $isLineComment = $character -eq '/' -and $index + 1 -lt $length -and $Text[$index + 1] -eq '/'
        if (-not $isLineComment -and $character -eq '#') {
            # Bounded look-ahead: `$Text.Substring($index)` would copy the rest of the file at every
            # `#`, which is quadratic in a file this gate permits to be megabytes long.
            $window = $Text.Substring($index, [System.Math]::Min(32, $length - $index))
            $isLineComment = -not [regex]::IsMatch(
                $window, '(?i)^#(?:include|clear|x-apt-configure-index)\b')
        }
        if ($isLineComment) {
            $newline = $Text.IndexOf("`n", $index)
            [void]$builder.Append(' ')
            if ($tagStarted) { $inTag = $false }
            if ($newline -lt 0) { break }
            $index = $newline + 1
            continue
        }
        if ($character -eq ';' -or $character -eq '{' -or $character -eq '}') {
            $inTag = $true
            $tagStarted = $false
        }
        elseif ([char]::IsWhiteSpace($character)) {
            if ($tagStarted) { $inTag = $false }
        }
        else {
            $tagStarted = $true
        }
        [void]$builder.Append($character)
        $index++
    }

    $collapsed = [regex]::Replace($builder.ToString(), '\s+', ' ').Trim()
    return [regex]::Replace(
        $collapsed,
        '%([0-9A-Fa-f]{2})',
        [System.Text.RegularExpressions.MatchEvaluator] {
            param($match)
            [string][char][System.Convert]::ToInt32($match.Groups[1].Value, 16)
        })
}

function Get-GateAptConfigRejection {
    <#
    .SYNOPSIS
        Names why an apt configuration file disqualifies the copied tree, or '' when it does not.
    .NOTES
        Four directive classes fail the read. The first two stop the tree this scan enumerates from
        being the tree apt reads; the last two leave that tree in place and change what arrives
        through it.

        The first is a path directive. Every `Dir` and `RootDir` tag is refused unless it names one
        of the subtrees that provably relocate no source list — `Dir::Cache`, `Dir::State`,
        `Dir::Log`, `Dir::Media` — and refusing by default rather than listing the dangerous forms
        is the point. Enumerating dangerous forms is what let `Binary::apt-get::Dir::Etc::sourcelist
        "/opt/hidden"` through: apt scopes configuration per binary, so it relocates the source list
        for apt-get alone while `apt-config dump`'s unscoped value stays innocent. `RootDir` went
        through for a different reason and is worse — apt prefixes it onto *every* resolved path,
        so it moves `/etc/apt` itself while leaving the copied tree allowlisted and clean. Both
        read as an allowlisted `/etc/apt` that apt never consults. The named-safe set is what
        Debian's own base images ship (`apt.conf.d/docker-clean` sets `Dir::Cache::*`); anything
        else is a decision a human should make with the diff in front of them.

        The second is an active `#` directive. A leading `#` is not proof of a comment in an apt
        configuration file: `#include` pulls in a file this scan never sees and which is free to
        relocate the source lists, so it fails closed regardless of what it names. `#clear` is the
        same argument in reverse — it discards assignments the checks above depend on — so a
        `#clear` naming a path tag fails too.

        The third and fourth classes do not move the tree at all, and that is what makes them worth
        refusing here: they substitute the *packages* while every hostname this gate compares stays
        exactly as an honest image would write it. A proxy answers for `deb.debian.org`, and an
        unauthenticated or trust-bypassing setting accepts what it answers with. The allowlist
        cannot see either, because neither changes a name — so the configuration read, which is the
        only place they appear, refuses both.

        Both tests run over `ConvertTo-GateAptConfigStatement` output rather than raw lines, so a
        statement split across lines, or a token spliced apart by a `/* */` comment, is read as apt
        reads it rather than as it appears on disk.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $statements = ConvertTo-GateAptConfigStatement -Text $Text
    if ([regex]::IsMatch($statements, '(?i)#include\b')) { return 'config-include' }
    if ([regex]::IsMatch($statements, '(?i)#clear[^;]*(?<=^|[\s{};]|::)(?:Root)?Dir(?![A-Za-z])')) {
        return 'config-dir-clear'
    }
    # A tag is a `::`-joined chain of segments, so the token is only a `Dir` tag where a segment can
    # begin: at the start of a word or straight after a `::`. That keeps `DPkg::Chrootdir` and a
    # `/srv/dir/x` left over from an unquoted value out, while a binary-scoped
    # `Binary::apt-get::Dir::…` — which is exactly why a preceding colon must be allowed — is in.
    foreach ($match in [regex]::Matches(
            $statements, '(?i)(?<=^|[\s{};]|::)(?<root>Root)?Dir(?![A-Za-z])')) {
        if ($match.Groups['root'].Success) { return 'config-dir-override' }
        $start = $match.Index + $match.Length
        $window = $statements.Substring($start, [System.Math]::Min(16, $statements.Length - $start))
        if (-not [regex]::IsMatch($window, '(?i)^::(?:Cache|State|Log|Media)(?![A-Za-z0-9-])')) {
            return 'config-dir-override'
        }
    }
    # Ordered after the relocation tests on purpose: a file carrying both is a relocation first,
    # and that is the finding whose repair is the larger one.
    if ([regex]::IsMatch($statements, $script:AptProxyTagPattern)) { return 'config-proxy' }
    if ([regex]::IsMatch($statements, $script:AptTrustTagPattern)) { return 'config-trust' }
    return ''
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

        `apt.conf` and `apt.conf.d/*` are read for one thing only: a directive that moves the
        source-list directory this function and the Dockerfile's own recorder both enumerate out of
        view. `Get-GateAptConfigRejection` decides which lines those are — a source-relocating `Dir`
        assignment in any scope, including a binary-scoped one, an active `#include` or `#clear`,
        and the two directive classes that leave the tree alone and change what arrives through it:
        a proxy, and an unauthenticated or trust-bypassing acquisition setting. Any of them fails
        the read outright, because an image that points `Dir::Etc::sourcelist` at a file outside
        `/etc/apt`, includes a configuration file this scan never sees, or accepts unsigned packages
        from whatever answers for `deb.debian.org`, presents an allowlisted tree that says nothing
        about what it installs. Fail closed rather than report the hosts of a configuration that is
        not in effect. Config files are never scanned for hosts — a URL in a note there is not a
        source.

        Source files carry the same waiver in their own syntax — `deb [trusted=yes] …` and deb822's
        `Trusted: yes` — and it fails the read for the same reason: it changes no hostname, so every
        allowlist comparison downstream would pass on a source apt installs from unsigned.


        The tree is required to be a plain tree of plain files. A symlinked `sources.list.d`, or a
        single symlinked `.sources` inside it, is not recursed into by `Get-ChildItem` and is not
        returned by a `-File` enumeration either, so the scan used to report the hosts of the part
        it could see and say nothing about the part apt actually reads. Any link or reparse point
        anywhere under the root now fails the read outright.

        Every failure sets `Reason` to a bounded code — and, where a file is at fault, the
        sanitized name of that file. A read that fails closed without saying which of a dozen
        conditions fired is a verdict the reader cannot act on, and this one is reached only from
        a post-merge job whose entire audience is whoever opens the receipt.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [AllowNull()][ref]$Reason
    )

    if ($null -ne $Reason) { $Reason.Value = '' }
    if (-not (Test-Path -LiteralPath $Root)) {
        if ($null -ne $Reason) { $Reason.Value = 'root-absent' }
        return $null
    }
    $hosts = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    # `-ErrorAction SilentlyContinue` would swallow a permission or reparse-point error and hand
    # back the files it *could* read, so a tree whose disallowed half is unreadable would pass on
    # the allowed half. Errors are collected and any of them fails the read.
    $enumerationErrors = @()
    try {
        $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
        if (Test-GateReparseItem -Item $rootItem) {
            if ($null -ne $Reason) { $Reason.Value = 'root-link' }
            return $null
        }
    }
    catch {
        if ($null -ne $Reason) { $Reason.Value = 'root-unreadable' }
        return $null
    }
    $rootFull = $rootItem.FullName
    # Directories are enumerated alongside files precisely so a redirected one can be seen: a
    # `-File` enumeration returns nothing for a symlinked directory and reports no error either.
    $allItems = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +enumerationErrors)
    if ($enumerationErrors.Count -gt 0) {
        if ($null -ne $Reason) { $Reason.Value = 'enumeration-failed' }
        return $null
    }
    if ($allItems.Count -gt 4096) {
        if ($null -ne $Reason) { $Reason.Value = 'tree-oversize' }
        return $null
    }
    $linked = @($allItems | Where-Object { Test-GateReparseItem -Item $_ })
    if ($linked.Count -gt 0) {
        if ($null -ne $Reason) {
            $Reason.Value = 'tree-link:' + (Get-GateAptConfigToken -Root $rootFull -Path $linked[0].FullName)
        }
        return $null
    }
    $allFiles = @($allItems | Where-Object { -not $_.PSIsContainer })
    $files = @($allFiles | Where-Object {
            $_.Name -eq 'sources.list' -or $_.Name -eq 'apt.conf' -or
            $_.Extension -in @('.list', '.sources') -or
            $_.Directory.Name -eq 'apt.conf.d'
        })
    if ($files.Count -gt 256) {
        if ($null -ne $Reason) { $Reason.Value = 'file-count-oversize' }
        return $null
    }
    foreach ($file in $files) {
        $token = Get-GateAptConfigToken -Root $rootFull -Path $file.FullName
        if ($file.Length -gt $script:MaxPayloadFileBytes) {
            if ($null -ne $Reason) { $Reason.Value = "file-oversize:$token" }
            return $null
        }
        $lines = $null
        try { $lines = [System.IO.File]::ReadAllLines($file.FullName) }
        catch {
            if ($null -ne $Reason) { $Reason.Value = "file-unreadable:$token" }
            return $null
        }
        $isConfig = ($file.Name -eq 'apt.conf' -or $file.Directory.Name -eq 'apt.conf.d')
        if ($isConfig) {
            if ($file.Length -gt $script:MaxAptConfigFileBytes) {
                if ($null -ne $Reason) { $Reason.Value = "config-oversize:$token" }
                return $null
            }
            # Configuration files are read for one thing only: a relocation of the tree this
            # function enumerates. They are not scanned for hosts, because a URL in an
            # `apt.conf.d` note is a comment about a source, not a source — treating it as one
            # would fail images over text apt never fetches from. The whole file goes to the
            # directive test at once, because apt's own statements are not bounded by lines.
            $rejection = Get-GateAptConfigRejection -Text ($lines -join "`n")
            if ($rejection) {
                if ($null -ne $Reason) { $Reason.Value = "${rejection}:$token" }
                return $null
            }
            continue
        }
        foreach ($line in $lines) {
            $value = $line.Trim()
            if (-not $value) { continue }
            if ($value.StartsWith('#') -or $value.StartsWith('//')) { continue }
            # A source may waive its own authentication: `deb [trusted=yes] …` and deb822's
            # `Trusted: yes` tell apt to install from that origin with no valid signature, and the
            # `allow-*` options are the per-source spelling of the same waiver. None of them names
            # a different host, so every host check in this file passes while the packages that
            # arrive are whatever answered. Only an explicitly false value survives.
            $trust = [regex]::Match($value, $script:AptSourceTrustPattern)
            if ($trust.Success -and
                $trust.Groups['value'].Value.ToLowerInvariant() -notin $script:AptSourceTrustFalse) {
                if ($null -ne $Reason) { $Reason.Value = "source-trusted:$token" }
                return $null
            }
            # Two scans, because one cannot see both URI forms apt accepts without letting the
            # weaker form hide the stronger one. Matching only `scheme://authority` saw
            # `https://deb.debian.org/...` and missed every source with no authority at all —
            # `file:/srv/repo`, `cdrom:[...]/`, `mirror+file:///etc/apt/mirrors/debian.list` —
            # because the authority group cannot match an empty string. Those are origins apt
            # fetches from, so they are reported as a pseudo-host that fails the allowlist rather
            # than passing as "no host found".
            #
            # A single combined pattern is wrong, and wrong in the dangerous direction. deb822
            # permits `URIs:https://evil.example/repo` with no space, and apt honours it; a pattern
            # that matched `<scheme>:<rest>` would bind `scheme=URIs`, swallow the real URL into
            # `rest`, discard it as a non-transport scheme, and — because matching resumes past the
            # end of the match — never look at the embedded `https://` again. The origin would
            # simply not be reported, and the subset check would pass on whatever else the tree
            # contained. So authorities are scanned for first, over the whole line.
            foreach ($match in [regex]::Matches($value, '(?i)(?<![A-Za-z0-9+.-])(?<scheme>[a-z][a-z0-9+.-]*)://(?<rest>\S*)')) {
                $scheme = $match.Groups['scheme'].Value.ToLowerInvariant()
                # The whole authority is kept, port aside, exactly as `Get-GateAptHost` keeps it.
                # Narrowing to a host character class would stop at the userinfo delimiter, so
                # `https://download.docker.com@evil.example.com/...` — which apt resolves against
                # `evil.example.com` — would be reported as the allowed host, and the two parsers
                # holding the image to one allowlist would disagree about what a host is.
                $authority = ((($match.Groups['rest'].Value) -split '/', 2)[0]).ToLowerInvariant() -replace ':[0-9]+$', ''
                if ($authority) {
                    # A non-http(s) scheme is not "no host": `ftp://` and `tor+https://` are
                    # origins apt will fetch from that this allowlist was never written against.
                    if ($scheme -in @('http', 'https')) { [void]$hosts.Add($authority) }
                    else { [void]$hosts.Add("${scheme}://$authority") }
                }
                elseif (($scheme -split '\+', 2)[0] -in $script:AptTransportScheme) {
                    # `scheme:///path` — a triple slash leaves the authority genuinely empty. It is
                    # still an origin, so it is reported opaquely rather than dropped.
                    [void]$hosts.Add("${scheme}:opaque")
                }
            }
            # Then the authority-less forms. Only a scheme apt has a transport method for is
            # reported, so a bare `Field:value` in a deb822 stanza is not mistaken for a source;
            # every transport Debian ships is listed, and a composite (`mirror+file`, `tor+http`)
            # is recognised by its leading segment.
            foreach ($match in [regex]::Matches($value, '(?i)(?<![A-Za-z0-9+.-])(?<scheme>[a-z][a-z0-9+.-]*):(?!//)(?<rest>\S+)')) {
                $scheme = $match.Groups['scheme'].Value.ToLowerInvariant()
                if (($scheme -split '\+', 2)[0] -in $script:AptTransportScheme) {
                    [void]$hosts.Add("${scheme}:opaque")
                }
            }
        }
    }
    return @($hosts)
}

function Get-GateImageEnvRejection {
    <#
    .SYNOPSIS
        Names the environment entry that would let apt read a configuration this gate never sees,
        or '' when none does.
    .NOTES
        Every check in this file reads `/etc/apt`. `APT_CONFIG` makes that the wrong tree without
        touching a byte of it: apt reads the file the variable names *before* `/etc/apt/apt.conf`,
        and that file may relocate `Dir::Etc::sourcelist`, disable authentication, or set a proxy —
        the three findings the configuration scan exists to refuse — from a path the scan does not
        enumerate. An image needs no such variable: a setting it wants can live in `apt.conf.d`,
        where this gate can read it. So any non-empty value is refused, which is also apt's own
        condition for honouring it (`getenv` non-null *and* non-empty), and an empty one is left to
        pass because it is what apt itself treats as unset.

        Proxy variables are refused on the same grounds as the proxy directives: `http_proxy` and
        its siblings redirect the fetch while every hostname in the tree stays allowlisted, and apt
        honours them through libcurl and its own methods. The name test is deny-by-default on the
        substring rather than a list of the eight spellings, because the list is the side that
        grows.

        The input is `docker inspect` output describing a candidate image, so it is untrusted and
        bounded twice — total bytes and entry count — before it is parsed, and the offending name
        travels onward as a token on a fixed alphabet rather than as whatever the image called it.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $text = $Json.Trim()
    if (-not $text) { return 'unreadable' }
    if ($text.Length -gt $script:MaxImageEnvBytes) { return 'oversize' }
    # `null` is what Docker reports for an image that sets no environment at all. That is the one
    # shape with nothing to reject; anything that is not an array of strings is a read this
    # function did not understand, and an ununderstood read is not evidence of a clean image. The
    # array shape is decided on the text rather than on the parse, because a one-element array
    # comes back from `ConvertFrom-Json` as its element and would otherwise be indistinguishable
    # from a bare JSON string — which is exactly the shape a single `APT_CONFIG=` entry has.
    if ([string]::Equals($text, 'null', [System.StringComparison]::Ordinal)) { return '' }
    if (-not ($text.StartsWith('[') -and $text.EndsWith(']'))) { return 'unreadable' }
    $parsed = $null
    try { $parsed = @(ConvertFrom-Json -InputObject $text) }
    catch { return 'unreadable' }
    if ($parsed.Count -gt $script:MaxImageEnvEntries) { return 'oversize' }
    foreach ($entry in $parsed) {
        if ($entry -isnot [string]) { return 'unreadable' }
        $separator = $entry.IndexOf('=')
        # Docker writes `NAME=VALUE`; an entry with no `=` names a variable with no value, which
        # neither apt nor this test has anything to act on.
        if ($separator -lt 0) { continue }
        $name = $entry.Substring(0, $separator)
        if (-not $entry.Substring($separator + 1)) { continue }
        if ([string]::Equals($name, 'APT_CONFIG', [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'apt-config'
        }
        if ([regex]::IsMatch($name, $script:ImageEnvProxyPattern)) {
            $token = [regex]::Replace($name, '[^A-Za-z0-9_]', '_')
            if ($token.Length -gt 32) { $token = $token.Substring(0, 32) }
            return "proxy:$token"
        }
    }
    return ''
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
        origin allowlist. It also reads the environment the image hands every container it starts,
        because `APT_CONFIG` and the proxy variables decide what the copied tree is worth. Smoke
        output is only believed where it agrees with this.

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
    # `TimeoutSeconds` is the budget for the whole attestation, not for each of its five docker
    # calls. Passing `min(60, TimeoutSeconds)` to every call let a five-second remainder fund five
    # seconds of work five times over, so attestation could outlive the gate deadline it was given.
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $remaining = {
        [int][math]::Floor($TimeoutSeconds - $clock.Elapsed.TotalSeconds)
    }
    try {
        $create = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'create', '--network', 'none', $ImageTag, 'true'
        ) -TimeoutSeconds ([math]::Min(60, $TimeoutSeconds))
        if ($create.ExitCode -ne 0 -or $create.Stdout.Trim() -notmatch '^[a-f0-9]{12,64}$') {
            return [pscustomobject]@{ Valid = $false; Reason = 'attestation-container-unavailable'; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
        }
        $containerId = $create.Stdout.Trim()

        # The environment is read before anything is copied, because it decides whether the files
        # that would be copied are the ones apt reads at all. The container is created from the
        # image with no environment of this gate's own, so its `Config.Env` is the image's
        # environment as every run of it inherits — and reading it from the container rather than
        # the image config keeps the answer true of the runtime even if this call ever gains an
        # `--env` of its own.
        $envBudget = & $remaining
        if ($envBudget -lt 1) {
            return [pscustomobject]@{ Valid = $false; Reason = 'attestation-timeout'; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
        }
        $inspect = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'inspect', '--format', '{{json .Config.Env}}', $containerId
        ) -TimeoutSeconds ([math]::Min(60, $envBudget))
        $envReason = if ($inspect.ExitCode -ne 0) { 'inspect-failed' }
        else { Get-GateImageEnvRejection -Json $inspect.Stdout }
        if ($envReason) {
            return [pscustomobject]@{ Valid = $false; Reason = "attestation-image-env:$envReason"; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
        }

        $copied = @{}
        foreach ($entry in @(
                @{ Name = 'manifest'; Source = $script:AttestedManifestPath },
                @{ Name = 'debianSources'; Source = $script:AttestedDebianSourcesPath },
                @{ Name = 'finalSources'; Source = $script:AttestedFinalSourcesPath }
            )) {
            $budget = & $remaining
            if ($budget -lt 1) {
                return [pscustomobject]@{ Valid = $false; Reason = 'attestation-timeout'; ManifestSha256 = ''; AptHosts = @(); DebianAptHosts = @() }
            }
            $destination = Join-Path $workRoot $entry.Name
            $copy = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
                'cp', "${containerId}:$($entry.Source)", $destination
            ) -TimeoutSeconds ([math]::Min(60, $budget))
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
        $configBudget = & $remaining
        if ($configBudget -lt 1) {
            return [pscustomobject]@{
                Valid = $false
                Reason = 'attestation-timeout'
                ManifestSha256 = $manifestSha
                AptHosts = @($finalHosts)
                DebianAptHosts = @($debianHosts)
            }
        }
        $configCopy = Invoke-GateProcess -FilePath 'docker' -ArgumentList @(
            'cp', "${containerId}:/etc/apt", $configRoot
        ) -TimeoutSeconds ([math]::Min(60, $configBudget))
        # Parsing the copied tree is host-side work with its own bound (4096 items, 4 MiB each),
        # so it is the one step left that could run past the deadline after every docker call has
        # respected it. The budget is checked once more before it starts.
        if ((& $remaining) -lt 1) {
            return [pscustomobject]@{
                Valid = $false
                Reason = 'attestation-timeout'
                ManifestSha256 = $manifestSha
                AptHosts = @($finalHosts)
                DebianAptHosts = @($debianHosts)
            }
        }
        $configReason = ''
        $liveHosts = if ($configCopy.ExitCode -eq 0) {
            Get-GateAptConfigHost -Root $configRoot -Reason ([ref]$configReason)
        }
        else {
            $configReason = 'copy-failed'
            $null
        }
        if ($null -eq $liveHosts -or @($liveHosts).Count -eq 0) {
            # A read that fails closed and says only "unreadable" cannot be acted on: a copy that
            # never ran, a symlinked `sources.list.d`, and a binary-scoped `Dir::Etc::sourcelist`
            # are three different repairs. The bounded reason from the reader names which one.
            if (-not $configReason) { $configReason = 'no-origin' }
            return [pscustomobject]@{
                Valid = $false
                Reason = "attestation-apt-config-unreadable:$configReason"
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
            # Cleanup is the one call allowed to overrun the deadline, and only down to a five
            # second floor: a container left running with no cidfile is a leak nothing later in
            # the run can find, which is worse than a few seconds past the budget. It is still
            # bounded, so a wedged daemon cannot hold the job open.
            $cleanupBudget = [math]::Max(5, [math]::Min(30, (& $remaining)))
            [void](Invoke-GateProcess -FilePath 'docker' -ArgumentList @('rm', '-f', $containerId) -TimeoutSeconds $cleanupBudget)
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
        [AllowEmptyCollection()][string[]]$SmokeReasons = @(),
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
    # Whole-run smoke failures have no case to hang from; the closed reason set is what makes a
    # `state=fail` receipt diagnosable without the reader fetching the smoke output itself.
    $reasons = @(@($SmokeReasons) |
            Where-Object { $_ -in $script:AllowedSmokeReasons } |
            Sort-Object -Unique)
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
            reasons = $reasons
        }
        diagnostic = Limit-GateText $Diagnostic 1024
    }
}

function Write-ContainerGateReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Receipt, [Parameter(Mandatory)][string]$Path)

    $fallback = '{"schema":"skalary/container-toolchain-receipt@1","outcome":"unexpected-error","relevant":true,"comparison":"not-run","candidateOnlyReason":"","blocking":true,"advisory":false,"identities":{"baseSha":"","candidateSha":"","architecture":"","baseImage":"","docker":"","copilotVersion":""},"provenance":{"sha256":""},"timing":{"totalMs":0,"candidateMs":0,"baseMs":0},"measurement":{"candidateBytes":0,"baseBytes":0,"deltaBytes":null,"advisoryGrowthMiB":250},"smoke":{"summary":"","failedCases":[],"reasons":[]},"diagnostic":"fallback receipt"}'
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

    # An image that was never built has no size. Rendering its `0` through the MiB formatter
    # produced `0.0 MiB`, which reads as a measured result — a base that failed to build and a
    # base that is genuinely empty printed the same line.
    $formatSize = {
        param([AllowNull()][object]$Bytes)
        if ($null -eq $Bytes -or [int64]$Bytes -le 0) { return 'not measured' }
        return ('{0:N1} MiB' -f ([double]$Bytes / 1MB))
    }
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
    $smokeReasons = @(if ($Receipt.smoke.Contains('reasons')) { $Receipt.smoke.reasons } else { @() })
    $lines = @(
        '## Autopilot container toolchain',
        '',
        "- Outcome: **$(ConvertTo-GateMarkdown $Receipt.outcome)**",
        "- Blocking: $(ConvertTo-GateMarkdown ([string]$Receipt.blocking))",
        "- Relevant: $(ConvertTo-GateMarkdown ([string]$Receipt.relevant))",
        "- Comparison: $(ConvertTo-GateMarkdown $Receipt.comparison)",
        "- Candidate-only reason: $(ConvertTo-GateMarkdown $Receipt.candidateOnlyReason)",
        "- Candidate image: $(ConvertTo-GateMarkdown (& $formatSize $Receipt.measurement.candidateBytes))",
        "- Base image: $(ConvertTo-GateMarkdown (& $formatSize $Receipt.measurement.baseBytes))",
        "- Delta: $(ConvertTo-GateMarkdown $deltaText) (threshold $(ConvertTo-GateMarkdown ([string]$Receipt.measurement.advisoryGrowthMiB)) MiB — $(ConvertTo-GateMarkdown $advisoryText))",
        "- Timing: total $(ConvertTo-GateMarkdown ([string]$Receipt.timing.totalMs)) ms; candidate $(ConvertTo-GateMarkdown ([string]$Receipt.timing.candidateMs)) ms; base $(ConvertTo-GateMarkdown ([string]$Receipt.timing.baseMs)) ms",
        "- Smoke: $(ConvertTo-GateMarkdown $Receipt.smoke.summary)",
        "- Failed smoke cases: $(if ($failedCases.Count -gt 0) { ConvertTo-GateMarkdown (@($failedCases) -join ', ') } else { 'none' })",
        "- Smoke failure reasons: $(if ($smokeReasons.Count -gt 0) { ConvertTo-GateMarkdown (@($smokeReasons) -join ', ') } else { 'none' })",
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
    <#
    .NOTES
        Attribute-identical to the script-level `param()` block at the top of this file, except
        for `ReceiptPath`: the script block cannot mark it `Mandatory` because dot-sourcing the
        file for testing would then prompt, so the file-invocation path checks it explicitly
        instead. `test:AutopilotContainer.GateRunnerContract` compares the two blocks reflectively.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Detect', 'Measure', 'VerifyResult', 'Initialize')][string]$Mode = 'Detect',
        [string]$BaseSha,
        [string]$CandidateSha,
        [string]$BaseRoot,
        [string]$CandidateRoot,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [string]$ProvenancePath,
        [string]$SummaryPath,
        [string]$DiagnosticLogPath,
        [string]$StepOutputPath,
        [string]$Diagnostic,
        [string]$DetectorConclusion,
        [string]$Relevance,
        [string]$ImageConclusion,
        [ValidateSet('', 'not-run', 'comparable', 'candidate-only')][string]$MeasurementComparison,
        [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift', 'base-build-failed', 'base-timeout')][string]$MeasurementCandidateOnlyReason,
        [ValidateSet('', 'zero-base', 'base-unreachable', 'base-context-absent', 'base-payload-drift')]
        [string]$DetectionCandidateOnlyReason,
        [ValidateSet('', 'true', 'false')]
        [string]$DetectionRelevance,
        [ValidatePattern('^\d{0,6}$')]
        [string]$RelevantPathCount,
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
    $smokeReasons = @()
    $contradictionDiagnostic = ''
    $candidatePhaseStartMs = $null
    $candidatePhaseEndMs = $null
    $basePhaseStartMs = $null
    try {
        if ($Mode -eq 'Initialize') {
            # A placeholder receipt used to be three JSON string literals inside the workflow, so
            # the receipt shape existed in two places and the workflow's copy named no commit, no
            # path, and no reason — a reader who fetched it learned only that something had been
            # skipped. Building it here keeps one owner of the schema and lets the placeholder
            # carry the identities and the reason it was written.
            $reason = if ($DetectionCandidateOnlyReason) { $DetectionCandidateOnlyReason } else { '' }
            # A placeholder is written when a job died before its own receipt existed. For an
            # irrelevant commit that is the truth. For a *relevant* one it is not: hardcoding
            # `irrelevant` turned a lost measurement job into a non-blocking receipt claiming the
            # commit did not touch the toolchain, which is the one reading that lets a red run
            # disappear. Relevance is therefore carried in, and a relevant placeholder is the
            # blocking `unexpected-error` a lost runner actually is.
            $initializeRelevant = $DetectionRelevance -eq 'true'
            $initializeOutcome = if ($initializeRelevant) { 'unexpected-error' } else { 'irrelevant' }
            $receipt = New-ContainerGateReceipt -Outcome $initializeOutcome -Relevant $initializeRelevant `
                -Comparison 'not-run' -CandidateOnlyReason $reason -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture `
                -Diagnostic (Limit-GateText -Value $Diagnostic -Maximum 1024) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            $exitCode = 0
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }

        if ($Mode -eq 'VerifyResult') {
            $passed = Test-ContainerGateResult -DetectorConclusion $DetectorConclusion -Relevance $Relevance -ImageConclusion $ImageConclusion
            $relevant = $Relevance -eq 'true'
            $outcome = if ($passed -and -not $relevant) { 'irrelevant' } elseif ($passed) { 'success' } else { 'unexpected-error' }
            # The final receipt is the artifact a reader opens first and, when the measurement job
            # was skipped, the only one there is. It used to name no commit at all, so the verdict
            # that decides whether main is green could not be attributed to the change it judged.
            # The identities and the detector's evidence — why the base was unusable, how many
            # relevant paths it found — are carried through so the terminal receipt stands alone.
            # Comparison is produced by Measure, not inferred from a successful image job. A base
            # failure is a successful candidate-only measurement, so re-deriving this value from
            # job conclusions would contradict the measurement receipt for the same run.
            $comparison = if ($ImageConclusion -eq 'success' -and $MeasurementComparison) { $MeasurementComparison }
            elseif ($DetectionCandidateOnlyReason) { 'candidate-only' }
            else { 'not-run' }
            $finalCandidateOnlyReason = if ($ImageConclusion -eq 'success' -and $MeasurementCandidateOnlyReason) {
                $MeasurementCandidateOnlyReason
            }
            else {
                $DetectionCandidateOnlyReason
            }
            if ($comparison -eq 'candidate-only' -and -not $finalCandidateOnlyReason) {
                throw 'A candidate-only measurement did not report its reason.'
            }
            if ($comparison -eq 'comparable' -and $finalCandidateOnlyReason) {
                throw 'A comparable measurement reported a candidate-only reason.'
            }
            $pathEvidence = if ($RelevantPathCount) { "relevantPaths=$RelevantPathCount" } else { 'relevantPaths=unreported' }
            $reasonEvidence = if ($finalCandidateOnlyReason) { $finalCandidateOnlyReason } else { 'none' }
            $receipt = New-ContainerGateReceipt -Outcome $outcome -Relevant $relevant -Comparison $comparison `
                -CandidateOnlyReason $finalCandidateOnlyReason -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture `
                -Diagnostic "detector=$DetectorConclusion; relevance=$Relevance; image=$ImageConclusion; $pathEvidence; candidateOnlyReason=$reasonEvidence" `
                -AdvisoryGrowthMiB $AdvisoryGrowthMiB
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
            # The detector's two outputs used to be assembled by the workflow, which meant the
            # closed candidate-only reason set was re-stated in YAML and could drift from the one
            # `New-ContainerGateReceipt` validates. The runner owns both values; the workflow only
            # names the file to write them to.
            if ($Mode -eq 'Detect' -and $StepOutputPath) {
                # The path list itself cannot be a step output: `$GITHUB_OUTPUT` is line-oriented
                # and the safe alphabet excludes `/`, so the count travels and the detector receipt
                # artifact keeps the names. Without it the final receipt could say "relevant" while
                # no reader could tell whether that rested on one path or twenty.
                Write-GateStepOutput -Path $StepOutputPath -Value ([ordered]@{
                        relevance = if ($relevant) { 'true' } else { 'false' }
                        candidate_only_reason = $candidateOnlyReason
                        relevant_path_count = [string]@($detection.RelevantPaths).Count
                    })
            }
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
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-payload-parity' `
                -Note "$($candidateParity.Reason): $($candidateParity.Detail)"
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha `
                -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha `
                -Diagnostic "Candidate payload parity: $($candidateParity.Reason): $($candidateParity.Detail)" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if (-not (Test-GateDockerfileBase -Path $candidateParity.Context.InstalledDockerfilePath)) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-dockerfile-base' `
                -Note "Candidate Dockerfile must use only '$script:BaseImage'."
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
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-image-pull' -Result $pull
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic 'Base image pull timed out.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        if ($pull.ExitCode -ne 0) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-image-pull' -Result $pull
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-build-failed' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -ProvenanceSha256 $provenanceSha -Diagnostic (Get-GateProcessDiagnostic -Result $pull) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
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
            'image', 'inspect', '--format', '{{.Os}}/{{.Architecture}} {{.Id}} {{json .RepoDigests}}', $script:BaseImage
        ) -TimeoutSeconds ([math]::Min(30, $candidateRemaining))
        if ($imageInspect.ExitCode -ne 0 -or $imageInspect.StdoutOverflow -or [string]::IsNullOrWhiteSpace($imageInspect.Stdout)) {
            # The throw lands in the catch below, which knows only the message. Without this the
            # uploaded diagnostics log held nothing but its seeded header, and the one artifact a
            # reader opens after the runner is gone explained a blocking verdict with a sentence.
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-image-inspect' -Result $imageInspect
            throw ('Could not resolve the pulled base-image identity. ' +
                (Get-GateProcessDiagnostic -Result $imageInspect -Maximum 512))
        }
        $baseImageIdentity = $imageInspect.Stdout.Trim()
        if (-not $baseImageIdentity.StartsWith('linux/amd64 ', [System.StringComparison]::Ordinal)) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-image-inspect' -Result $imageInspect
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
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'docker-daemon-identity' -Result $dockerInfo
            throw ('Could not resolve the Docker daemon identity. ' +
                (Get-GateProcessDiagnostic -Result $dockerInfo -Maximum 512))
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
            # `$smoke` is `$null` when `Invoke-GateProcess` threw before returning — a failed
            # start, or a kill that raised. Keying cleanup on `TimedOut` alone left the container
            # from that path running with the cidfile deleted, so nothing could stop it later.
            if ($null -eq $smoke -or $smoke.TimedOut) { Stop-GateContainer -CidFile $cidFile }
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
        $smokeReasons = @($smokeValidation.Reasons)
        if ($smoke.ExitCode -ne 0 -or $smokeValidation.Value.state -ne 'pass') {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-smoke' -Result $smoke
            $failedText = if ($smokeFailedCases.Count -gt 0) {
                'Failed smoke cases: ' + (@($smokeFailedCases) -join ', ') + '.'
            }
            elseif ($smokeReasons.Count -gt 0) {
                'Smoke failure reasons: ' + (@($smokeReasons) -join ', ') + '.'
            }
            else {
                'Candidate smoke reported failure without naming a case.'
            }
            $stderrTail = Get-GateProcessDiagnostic -Result $smoke -Maximum 512
            $diagnostic = if ([string]::IsNullOrWhiteSpace($stderrTail)) { $failedText } else { "$failedText $stderrTail" }
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-smoke-failed' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -SmokeFailedCases $smokeFailedCases -SmokeReasons $smokeReasons -Diagnostic $diagnostic -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }

        # Candidate smoke has now claimed a pass. Nothing above proves the image installed what
        # the manifest says or resolved packages from an allowed origin, because every value in
        # that claim came from the candidate. Read the image from the trusted host and require
        # the claim to agree with it.
        # `max(1, ...)` used to be here, which handed a one-second budget to a step that cannot
        # finish in one second whenever the budget was already gone — a guaranteed
        # `attestation-timeout` dressed up as work attempted. An exhausted budget is a timeout,
        # and it is reported as one without spending a container create on it.
        $attestationBudget = [math]::Min(
            $CandidateBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds - $candidatePhaseStartSeconds),
            $RunnerBudgetSeconds - [int][math]::Ceiling($clock.Elapsed.TotalSeconds)
        )
        if ($attestationBudget -lt 1) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-attestation' -Note 'Budget elapsed before image attestation.'
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-timeout' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic 'Candidate budget elapsed before image attestation.' -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $attestation = Test-GateImageAttestation -ImageTag $candidateTag `
            -ExpectedManifestSha256 (Get-GateSha256 $installedManifestPath) `
            -TimeoutSeconds ([math]::Min(180, $attestationBudget))
        if (-not $attestation.Valid) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-attestation' -Note $attestation.Reason
            $receipt = New-ContainerGateReceipt -Outcome 'candidate-output-invalid' -Relevant $true -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateMs $candidateMs -SmokeSummary $smokeSummary -Diagnostic "Image attestation failed: $($attestation.Reason)" -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 1; Receipt = $receipt }
        }
        $agreement = Test-GateSmokeAttestationAgreement -Smoke $smokeValidation.Value -Attestation $attestation
        if ($agreement) {
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-attestation-agreement' -Note $agreement
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
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'candidate-size-inspect' -Result $candidateSize
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
        if ($baseSize.ExitCode -ne 0 -or $baseSize.Stdout.Trim() -notmatch '^\d+$') {
            # Comparable-base work is advisory by contract: it can only ever remove a delta from
            # the receipt, never fail a candidate. A non-zero exit or a malformed size used to
            # throw into the global catch and reappear as a blocking `unexpected-error`, so a
            # daemon hiccup while measuring the *base* failed a candidate that had already passed
            # every blocking check. It closes to the same candidate-only evidence a base build
            # failure does.
            Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'base-size-inspect' -Result $baseSize
            $receipt = New-ContainerGateReceipt -Outcome 'base-build-failed' -Relevant $true -Comparison 'candidate-only' -CandidateOnlyReason 'base-build-failed' -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -CandidateMs $candidateMs -BaseMs ($baseMs + $baseSize.ElapsedMs) -SmokeSummary $smokeSummary -Diagnostic ('Base image size is invalid. ' + (Get-GateProcessDiagnostic -Result $baseSize -Maximum 512)) -AdvisoryGrowthMiB $AdvisoryGrowthMiB
            return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
        }
        $baseBytes = [int64]$baseSize.Stdout.Trim()
        $deltaBytes = $candidateBytes - $baseBytes
        $comparison = 'comparable'
        $receipt = New-ContainerGateReceipt -Outcome 'success' -Relevant $true -Comparison $comparison -BaseSha $BaseSha -CandidateSha $CandidateSha -Architecture $RunnerArchitecture -BaseImageIdentity $baseImageIdentity -DockerIdentity $dockerIdentity -CopilotVersion $CopilotVersion -ProvenanceSha256 $provenanceSha -CandidateBytes $candidateBytes -BaseBytes $baseBytes -DeltaBytes $deltaBytes -CandidateMs $candidateMs -BaseMs $baseMs -SmokeSummary $smokeSummary -Diagnostic $contradictionDiagnostic -AdvisoryGrowthMiB $AdvisoryGrowthMiB
        $exitCode = 0
        return [pscustomobject]@{ ExitCode = 0; Receipt = $receipt }
    }
    catch {
        # An unexpected error is the one outcome whose cause is not already a closed reason, so it
        # is the outcome that most needs the log. Writing it here — rather than only at the throw
        # sites — means no `unexpected-error` receipt can be uploaded beside an empty diagnostics
        # log, including for a failure raised somewhere nobody anticipated.
        Write-GateDiagnosticLog -Path $DiagnosticLogPath -Stage 'unexpected-error' -Note (
            $_.Exception.Message + "`n--- script stack ---`n" + [string]$_.ScriptStackTrace)
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
        if ($Mode -eq 'Measure' -and $StepOutputPath) {
            Write-GateStepOutput -Path $StepOutputPath -Value ([ordered]@{
                    comparison = [string]$receipt.comparison
                    candidate_only_reason = [string]$receipt.candidateOnlyReason
                })
        }
        if ($SummaryPath) { Write-ContainerGateSummary -Receipt $receipt -Path $SummaryPath }
        Write-Host $json
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { throw 'ReceiptPath is required.' }
    $result = Invoke-ContainerToolchainGate @PSBoundParameters
    exit $result.ExitCode
}
