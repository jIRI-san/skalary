#requires -Version 7.0
<#
.SYNOPSIS
ts-arch (TypeScript) deterministic adapter (REQ-9). Runs a human-owned, reviewed vitest architecture spec by
invoking the locally-installed vitest binary directly via node, and parses its JUnit result into the strict
adapter result contract.

.DESCRIPTION
Only reached for a locked contract whose body hash the dispatcher already verified. Never derives, compiles,
or generates test code from a contract — it runs the reviewed spec the human owns. When the node/npm toolchain
is absent it returns skip-absent-toolchain (never a false pass, never a hard fail). Real execution is opt-in
(a committed fixture lives under evals/fixtures/tsarch); structural validation never shells node/npm.

Determinism: the project MUST commit a package-lock.json; the adapter installs with `npm ci --ignore-scripts`
(exact, lockfile-pinned + integrity-checked, no lifecycle scripts) and then runs vitest by invoking
node_modules/vitest/vitest.mjs DIRECTLY (never `npm exec`, which can auto-fetch from the registry and mangles the
--outputFile arg), so the vitest EXECUTION uses only pinned packages and never reaches the network. The one-time
`npm ci` install is integrity-pinned by the lockfile but may fetch tarballs from the registry on a cache miss.

Entrypoint: Invoke-TsArchAdapter -Context @{ ContractId; TargetRoot; RepoRoot; BodyPaths }.
BodyPaths[0] is the reviewed spec file. The project root is the nearest ancestor directory with a package.json.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TsArchCommand {
    <#
    .SYNOPSIS
    Pure vitest argument list scoped to a single reviewed spec, emitting JUnit to a fixed path. The launcher
    (node + the locally-installed vitest binary) is resolved separately by Invoke-TsArchAdapter; these are only
    the args vitest itself receives. Pure string construction (testable without a toolchain).

    .DESCRIPTION
    Uses the `--outputFile=<path>` '=' form deliberately: vitest ignores a space-separated outputFile value, so
    the junit reporter would silently write nothing. The reviewed spec is the only test file vitest runs.
    #>
    param(
        [Parameter(Mandatory)][string]$SpecPath,
        [Parameter(Mandatory)][string]$JUnitPath
    )
    $cmd = [System.Collections.Generic.List[string]]::new()
    $cmd.Add('run')
    $cmd.Add($SpecPath)
    $cmd.Add('--reporter=junit')
    $cmd.Add("--outputFile=$JUnitPath")
    return , $cmd.ToArray()
}

function Resolve-TsArchVitest {
    <#
    .SYNOPSIS
    Resolves the locally-installed vitest entrypoint (node_modules/vitest/vitest.mjs) under a project root.
    Returns $null when vitest is not installed. The adapter invokes this binary DIRECTLY via node (never
    `npm exec`, which can auto-fetch from the registry and mangles args) so the vitest execution never reaches
    the network.
    #>
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $entry = Join-Path $ProjectRoot 'node_modules/vitest/vitest.mjs'
    if (Test-Path -LiteralPath $entry -PathType Leaf) { return (Resolve-Path -LiteralPath $entry).Path }
    return $null
}

function Resolve-TsArchProjectRoot {
    <#
    .SYNOPSIS
    Walks up from a start path to the nearest ancestor directory that contains a package.json (the project the
    reviewed spec belongs to). Returns $null when none is found.
    #>
    param([Parameter(Mandatory)][string]$StartPath)

    $dir = if (Test-Path -LiteralPath $StartPath -PathType Container) {
        (Resolve-Path -LiteralPath $StartPath).Path
    }
    else {
        Split-Path -Parent ((Resolve-Path -LiteralPath $StartPath).Path)
    }

    while (-not [string]::IsNullOrEmpty($dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir 'package.json') -PathType Leaf) { return $dir }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function ConvertFrom-VitestJUnit {
    <#
    .SYNOPSIS
    Parses a vitest JUnit document into the strict result contract { status; ran; findings[]; artifacts[] }.

    .DESCRIPTION
    Maps per-testcase outcomes with a PASSING ALLOW-LIST (never a default-green):
      all testcases pass, >=1 testcase -> 'pass'
      any testcase has a <failure>      -> 'fail' (findings carry test name + message)
      any testcase has an <error>       -> 'error'
      any testcase is <skipped>         -> 'error' (a locked assertion turned into it.skip/it.todo is not a green)
      zero testcases                    -> 'error' (a locked run that executed nothing is not a green)
    Accepts either a JUnit file path (-Path) or raw xml (-Xml). ran=$true because a JUnit doc means tests ran.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Xml')][string]$Xml
    )

    [xml]$doc = if ($PSCmdlet.ParameterSetName -eq 'Path') { Get-Content -LiteralPath $Path -Raw } else { $Xml }

    $cases = @($doc.SelectNodes('//testcase'))
    $findings = [System.Collections.Generic.List[object]]::new()
    $failed = 0
    $skipped = 0
    $passed = 0

    foreach ($c in $cases) {
        $name = if ($c.Attributes -and $c.Attributes['name']) { [string]$c.Attributes['name'].Value } else { '(unknown)' }
        $failNode = $c.SelectSingleNode('failure')
        $errNode = $c.SelectSingleNode('error')
        $skipNode = $c.SelectSingleNode('skipped')

        if ($null -ne $failNode) {
            $failed++
            $msg = if ($failNode.Attributes -and $failNode.Attributes['message']) { [string]$failNode.Attributes['message'].Value } else { [string]$failNode.InnerText }
            $findings.Add([pscustomobject]@{
                    severity = 'error'
                    test     = $name
                    message  = ($msg -replace '\s+', ' ').Trim()
                })
            continue
        }
        if ($null -ne $errNode) {
            $msg = if ($errNode.Attributes -and $errNode.Attributes['message']) { [string]$errNode.Attributes['message'].Value } else { [string]$errNode.InnerText }
            $findings.Add([pscustomobject]@{
                    severity = 'error'
                    test     = $name
                    message  = "test errored: $(($msg -replace '\s+', ' ').Trim())"
                })
            continue
        }
        if ($null -ne $skipNode) {
            # A skipped/todo testcase in a LOCKED spec silently disarms a reviewed assertion; never count it green.
            $skipped++
            $findings.Add([pscustomobject]@{
                    severity = 'error'
                    test     = $name
                    message  = 'test was skipped/disabled (it.skip/it.todo) in a locked spec; a skipped assertion is not a pass'
                })
            continue
        }
        $passed++
    }

    $total = $cases.Count
    # Passing allow-list: only ALL-passed with at least one real testcase is a green (no failed, no skipped, no
    # errored). Any <failure> -> fail; anything else (skipped, errored, zero-total) -> error.
    $status = if ($total -gt 0 -and $passed -eq $total) { 'pass' }
    elseif ($failed -gt 0) { 'fail' }
    else { 'error' }
    if ($status -eq 'error' -and $total -eq 0) {
        $findings.Add([pscustomobject]@{ severity = 'error'; message = 'JUnit report contained zero testcases' })
    }

    return [pscustomobject]@{
        status    = $status
        ran       = $true
        findings  = @($findings)
        artifacts = @()
    }
}

function Invoke-TsArchAdapter {
    param([Parameter(Mandatory)][hashtable]$Context)

    $bodyPaths = @($Context.BodyPaths)
    $spec = if ($bodyPaths.Count -gt 0) { $bodyPaths[0] } else { $null }
    $repoRoot = if ($Context.ContainsKey('RepoRoot') -and $Context.RepoRoot) { [string]$Context.RepoRoot } else { $null }
    if ($spec -and $repoRoot -and -not [System.IO.Path]::IsPathRooted($spec)) {
        $spec = Join-Path $repoRoot $spec
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            status    = 'skip-absent-toolchain'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'info'; message = 'node/npm toolchain not present; ts-arch run skipped' })
            artifacts = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace($spec) -or -not (Test-Path -LiteralPath $spec)) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = "ts-arch spec not found: '$spec'" })
            artifacts = @()
        }
    }

    $projectRoot = Resolve-TsArchProjectRoot -StartPath $spec
    if (-not $projectRoot) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = "no package.json found in any ancestor of spec '$spec'" })
            artifacts = @()
        }
    }

    # Sanitize ContractId before embedding it in a filesystem path: a value containing / \ or .. would let
    # --outputFile escape the temp dir. Restrict to a safe charset (path-traversal defense).
    $safeId = ([string]$Context.ContractId) -replace '[^A-Za-z0-9._-]', '_'
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = 'contract' }
    $junitDir = [System.IO.Path]::GetTempPath()
    $junitPath = Join-Path $junitDir ("ts-arch-$safeId-$([System.Guid]::NewGuid().ToString('N')).xml")

    # vitest resolves the spec relative to its cwd (the project root); pass it relative so an absolute path on a
    # different drive/root cannot confuse resolution.
    $specRel = [System.IO.Path]::GetRelativePath($projectRoot, $spec)

    Push-Location $projectRoot
    try {
        # Deterministic install from the committed lock file (exact versions, no lifecycle scripts) before run.
        # A reproducible run REQUIRES a committed package-lock.json; a pre-existing node_modules is not pinned and
        # must never be trusted as if it were (that would run unpinned, machine-dependent packages).
        $lockFile = Join-Path $projectRoot 'package-lock.json'
        if (-not (Test-Path -LiteralPath $lockFile -PathType Leaf)) {
            return [pscustomobject]@{
                status    = 'skip-absent-toolchain'
                ran       = $false
                findings  = @([pscustomobject]@{ severity = 'info'; message = 'no committed package-lock.json; cannot install deterministically, ts-arch run skipped' })
                artifacts = @()
            }
        }
        & npm ci --ignore-scripts 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                status    = 'error'
                ran       = $false
                findings  = @([pscustomobject]@{ severity = 'error'; message = 'npm ci failed (package-lock.json stale or out of sync)' })
                artifacts = @()
            }
        }

        # Invoke the locally-installed vitest binary DIRECTLY via node (never `npm exec`, which can auto-fetch
        # from the registry and mangles the --outputFile arg). A missing vitest after a locked install is a hard
        # config error, never a false pass.
        $vitest = Resolve-TsArchVitest -ProjectRoot $projectRoot
        if (-not $vitest) {
            return [pscustomobject]@{
                status    = 'error'
                ran       = $false
                findings  = @([pscustomobject]@{ severity = 'error'; message = 'vitest is not installed under the project (package-lock.json does not pin vitest)' })
                artifacts = @()
            }
        }

        $vitestArgs = Get-TsArchCommand -SpecPath $specRel -JUnitPath $junitPath
        & node $vitest @vitestArgs 2>&1 | Out-Null
        $vitestExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $junitPath)) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = 'vitest produced no JUnit result' })
            artifacts = @()
        }
    }

    $parsed = ConvertFrom-VitestJUnit -Path $junitPath
    # An abnormal exit that still parses as a green means the tool aborted mid-report; never trust that as a pass.
    if ($parsed.status -eq 'pass' -and $vitestExit -ne 0) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $true
            findings  = @([pscustomobject]@{ severity = 'error'; message = "vitest exited $vitestExit but the JUnit report parsed as passing; treating an incomplete/aborted run as error" })
            artifacts = @($junitPath)
        }
    }
    return [pscustomobject]@{
        status    = $parsed.status
        ran       = $parsed.ran
        findings  = $parsed.findings
        artifacts = @($junitPath)
    }
}
