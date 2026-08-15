#requires -Version 7.0
<#
.SYNOPSIS
    Builds the minimal synthetic git fixture the plugin-registry tests run against.
.DESCRIPTION
    The suite used to clone the whole project repository once per case. That paid for
    the entire history and working tree to exercise four directories, and `git clone`
    of a local path hardlinks the object store, so the cost could not be amortised by
    copying either.

    This module builds a synthetic repository instead: `git init`, the payload roots
    the scripts under test actually read, one commit, and a version tag. The tag is
    load-bearing — `Build-Registry.ps1` resolves the bootstrap ref from
    `git tag --points-at HEAD` and falls back to a raw SHA without one, so a fixture
    without tags would silently stop exercising version resolution (RISK-12).

    That synthetic repository is built **once** as a pristine template, and each case
    receives its own filesystem copy of it under a freshly created random root. The
    template is never handed out, so no case can be built from a tree another case has
    already written to (RISK-1).

    The template carries only the plugins the cases name and depend on, and rebuilds
    `registry.json` and the README catalog against that set. Every `Build-Registry`,
    `Test-Registry` and `Install-Plugin` call in the suite then works over the plugins
    under test rather than over all of the repo's.
#>

Set-StrictMode -Version Latest

# The payload roots the registry scripts read. An allowlist rather than "everything
# except": a file the fixture does not carry is a test that fails loudly, whereas a
# denylist quietly readmits the cost this fixture exists to remove.
$script:FixturePayload = @(
    '.gitattributes'
    '.github'
    'README.md'
    'registry.json'
    'registry-retirements.json'
    'plugins'
    'schemas/registry'
    'scripts/skalary'
)

# The plugins the registry cases actually name, plus everything those names depend on.
# `Build-Registry` hashes every file of every plugin it finds, and the fixture is copied
# once per case, so carrying the plugins no case mentions is paid for on both sides. It is
# an allowlist rather than a denylist for the same reason the payload roots above are: a
# plugin a case needs and the fixture does not carry fails loudly, whereas a denylist
# silently readmits the cost as the repo grows.
#
#   code-review, design-notes, design-review  — installed, removed and searched directly
#   continue-implementation                   — the transitive-install case; pulls code-review + autopilot
#   autopilot                                 — dependency of continue-implementation
#   create-implementation-plan                — the modified-file remove case; pulls design-review
#
# `Test-SkalaryFixturePluginClosure` proves the list is closed under `dependencies`, so a
# manifest that gains a dependency cannot leave the fixture referencing a missing plugin.
$script:FixturePlugins = @(
    'autopilot'
    'code-review'
    'continue-implementation'
    'create-implementation-plan'
    'design-notes'
    'design-review'
)

# Points at HEAD of the fixture commit so Build-Registry resolves a version rather
# than a SHA. Kept semver-shaped because that is what a real release tag looks like.
$script:FixtureTag = 'v1.0.0'

# Every fixture is built from the same payload, so pinning the commit timestamps makes
# every fixture resolve to the same commit SHA. That is load-bearing, not cosmetic:
# Install-Plugin's registry-parity check only runs when the source SHA is an object in
# the target repo, which held for the clone-based fixture and would otherwise be lost.
$script:FixtureCommitDate = '2000-01-01T00:00:00+00:00'

# The template rebuilds registry.json, and Build-Registry stamps a wall-clock `generatedAt`
# whenever the body changed — which it always has here, since the fixture carries a smaller
# plugin set than the repo. Left alone that timestamp lands in the committed tree and makes
# the commit SHA vary per build, quietly turning Install-Plugin's parity check into a no-op
# (it returns without error when the source commit is unknown to the target). Pinned to the
# commit date so the rebuild stays deterministic.
$script:FixtureRegistryGeneratedAt = '2000-01-01T00:00:00.0000000Z'

# The pristine template and the project root it was built from. Cached for the lifetime of
# the module: building the fixture is the expensive half, copying it is the cheap half.
$script:FixtureTemplatePath = $null
$script:FixtureTemplateSource = $null

function Get-SkalaryFixturePayload {
    <#
    .SYNOPSIS
        Returns the repo-relative payload roots copied into the fixture.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]]$script:FixturePayload
}

function Get-SkalaryFixturePlugins {
    <#
    .SYNOPSIS
        Returns the plugin names the fixture carries.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]]$script:FixturePlugins
}

function Test-SkalaryFixturePluginClosure {
    <#
    .SYNOPSIS
        Returns the allowlisted plugins whose dependencies the allowlist does not carry.
    .DESCRIPTION
        An empty result means the fixture's plugin set is closed under `dependencies`.
        A non-empty one names the plugin and the dependency it would install against a
        registry entry with no files behind it — which is why this is checked rather
        than assumed: the closure is a property of the repo's manifests, not of this list.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $script:FixturePlugins) {
        $manifestPath = Join-Path $ProjectRoot "plugins/$name/plugin.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $missing.Add("$name -> (no manifest at plugins/$name/plugin.json)")
            continue
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
        if ($manifest.PSObject.Properties.Name -notcontains 'dependencies') { continue }
        foreach ($dependency in @($manifest.dependencies)) {
            $dependencyName = [string]$dependency
            if ([string]::IsNullOrWhiteSpace($dependencyName)) { continue }
            if ($script:FixturePlugins -notcontains $dependencyName) {
                $missing.Add("$name -> $dependencyName")
            }
        }
    }

    return [string[]]$missing.ToArray()
}

function Get-SkalaryFixtureTag {
    <#
    .SYNOPSIS
        Returns the tag the fixture places on its initial commit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:FixtureTag
}

function New-SkalaryFixtureRootPath {
    <#
    .SYNOPSIS
        Returns a fresh randomly named path under TEMP without creating it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Prefix = 'skalary-tests'
    )

    return Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [System.Guid]::NewGuid().ToString('N'))
}

function New-SkalaryFixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh randomly named directory, failing hard if it already exists.
    .DESCRIPTION
        RISK-1: a fixture root that is reused lets one case pass on a neighbour's
        side effects. `New-Item` without -Force throws when the path exists, so a
        collision is a loud failure rather than a silent merge into someone else's tree.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Prefix = 'skalary-tests'
    )

    $path = New-SkalaryFixtureRootPath -Prefix $Prefix
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to reuse an existing fixture root: '$path'."
    }

    [void](New-Item -ItemType Directory -Path $path)
    return (Resolve-Path -LiteralPath $path).Path
}

function Copy-SkalaryFixturePayload {
    <#
    .SYNOPSIS
        Copies the allowlisted payload roots from the project repo into $Destination.
    .DESCRIPTION
        `plugins` is copied per allowlisted plugin rather than wholesale: the registry the
        fixture is built around only needs the plugins the cases name, and every plugin
        beyond them is hashed by each `Build-Registry` call and copied by each per-case
        fixture copy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    foreach ($relative in (Get-SkalaryFixturePayloadEntry)) {
        $source = Join-Path $ProjectRoot $relative
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Fixture payload root not found in '$ProjectRoot': '$relative'."
        }

        $targetPath = Join-Path $Destination $relative
        $targetParent = Split-Path -Parent $targetPath
        if ($targetParent -and -not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $targetParent -Force)
        }

        if (Test-Path -LiteralPath $source -PathType Container) {
            Copy-Item -LiteralPath $source -Destination $targetParent -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $source -Destination $targetPath -Force
        }
    }
}

function Get-SkalaryFixturePayloadEntry {
    <#
    .SYNOPSIS
        Expands the payload roots into the concrete relative paths that get copied.
    .DESCRIPTION
        Every root copies as itself except `plugins`, which expands to one entry per
        allowlisted plugin. Expanding here rather than at each call site keeps `git add`
        and the copy working from the same list.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $script:FixturePayload) {
        if ($relative -eq 'plugins') {
            foreach ($plugin in $script:FixturePlugins) { $entries.Add("plugins/$plugin") }
        }
        else {
            $entries.Add($relative)
        }
    }

    return [string[]]$entries.ToArray()
}

function Copy-SkalaryFixtureTree {
    <#
    .SYNOPSIS
        Copies a directory tree, dot-prefixed entries included, onto a path that must not exist.
    .DESCRIPTION
        `Copy-Item -Recurse` measured no cheaper than rebuilding the fixture from scratch,
        which would have made the per-case copy a rename rather than a saving (RISK-11).
        Enumerating with System.IO and copying file by file is several times cheaper.

        The destination must not already exist. That is the RISK-1 guarantee stated where a
        test can reach it: a case is only ever handed a root nothing else has written to.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Fixture template not found: '$Source'."
    }
    if (Test-Path -LiteralPath $Destination) {
        throw "Refusing to reuse an existing fixture root: '$Destination'."
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $sourceRoot = [System.IO.Path]::GetFullPath($Source).TrimEnd($separator)
    $destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd($separator)

    [void][System.IO.Directory]::CreateDirectory($destinationRoot)
    try {
        foreach ($directory in [System.IO.Directory]::EnumerateDirectories($sourceRoot, '*', [System.IO.SearchOption]::AllDirectories)) {
            [void][System.IO.Directory]::CreateDirectory($destinationRoot + $directory.Substring($sourceRoot.Length))
        }
        foreach ($file in [System.IO.Directory]::EnumerateFiles($sourceRoot, '*', [System.IO.SearchOption]::AllDirectories)) {
            [System.IO.File]::Copy($file, $destinationRoot + $file.Substring($sourceRoot.Length), $true)
        }
    }
    catch {
        # A half-copied root is never returned to the caller, so no AfterAll can reclaim it.
        # Cleaning up here is the only chance to keep a failed copy from leaking into TEMP.
        Remove-Item -LiteralPath $destinationRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function New-SkalaryFixtureTemplateRepo {
    <#
    .SYNOPSIS
        Builds one minimal synthetic skalary repository at $Path.
    .DESCRIPTION
        `git init` plus the allowlisted payload, committed and tagged. The
        remote is set to the canonical GitHub URL because `Build-Registry.ps1`
        derives the bootstrap one-liner from `git remote get-url origin` and
        rejects anything that is not a GitHub URL.

        The payload carries only the allowlisted plugins, so the repo's committed
        `registry.json` and README catalog — which describe all of them — are rebuilt
        here against the plugins the fixture actually has. Rebuilding once in the
        template is what lets every case's `Build-Registry` call hash the smaller set;
        leaving the repo's registry in place would instead leave every case resolving
        registry entries with no files behind them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Invoke-FixtureGit -Arguments @('-C', $Path, 'init', '-b', 'main', '--quiet')
    Invoke-FixtureGit -Arguments @('-C', $Path, 'config', 'user.name', 'skalary-tests')
    Invoke-FixtureGit -Arguments @('-C', $Path, 'config', 'user.email', 'skalary-tests@example.com')
    Invoke-FixtureGit -Arguments @('-C', $Path, 'config', 'commit.gpgsign', 'false')
    Invoke-FixtureGit -Arguments @('-C', $Path, 'config', 'core.autocrlf', 'false')
    Invoke-FixtureGit -Arguments @('-C', $Path, 'remote', 'add', 'origin', 'https://github.com/jIRI-san/skalary.git')

    Copy-SkalaryFixturePayload -ProjectRoot $ProjectRoot -Destination $Path

    # Before the commit, so the fixture stays a single synthetic commit. Build-Registry
    # inherits the bootstrap ref from the registry it is rewriting and so needs no HEAD
    # here; Assert-FixtureInheritsBootstrapRef makes that a checked precondition rather
    # than a coincidence, because resolving it would hit an unborn HEAD and throw.
    Assert-FixtureInheritsBootstrapRef -Path $Path
    Invoke-FixtureBuildRegistry -Path $Path
    Set-FixtureRegistryTimestamp -Path $Path

    Invoke-FixtureGit -Arguments (@('-C', $Path, 'add', '--') + (Get-SkalaryFixturePayloadEntry))

    $previousAuthorDate = $env:GIT_AUTHOR_DATE
    $previousCommitterDate = $env:GIT_COMMITTER_DATE
    $env:GIT_AUTHOR_DATE = $script:FixtureCommitDate
    $env:GIT_COMMITTER_DATE = $script:FixtureCommitDate
    try {
        Invoke-FixtureGit -Arguments @('-C', $Path, 'commit', '--quiet', '-m', 'test: synthetic skalary fixture')
    }
    finally {
        $env:GIT_AUTHOR_DATE = $previousAuthorDate
        $env:GIT_COMMITTER_DATE = $previousCommitterDate
    }

    Invoke-FixtureGit -Arguments @('-C', $Path, 'tag', $script:FixtureTag)

    # The template is copied file by file, so its file *count* is the per-case cost. Packing
    # the loose objects into one packfile roughly halves it and changes nothing git-visible.
    Invoke-FixtureGit -Arguments @('-C', $Path, 'repack', '-a', '-d', '--quiet')
}

function Set-FixtureRegistryTimestamp {
    <#
    .SYNOPSIS
        Pins the rebuilt registry's `generatedAt` so the fixture commit stays deterministic.
    .DESCRIPTION
        Rewritten as text rather than through a JSON round-trip: the registry is emitted by
        `Write-JsonFileStable` and is hashed and compared byte for byte elsewhere, so
        re-serialising it here would risk changing more than the one field. A match count
        other than one is a loud failure — a silently unpinned timestamp is exactly the
        failure this exists to prevent.

        A later `Build-Registry` run over an unchanged body preserves this value, so the
        pin survives the rebuilds the cases perform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $registryPath = Join-Path $Path 'registry.json'
    $content = [System.IO.File]::ReadAllText($registryPath)
    $pattern = '(?<prefix>"generatedAt"\s*:\s*")(?<value>[^"]*)(?<suffix>")'

    $matched = [regex]::Matches($content, $pattern)
    if ($matched.Count -ne 1) {
        throw "Expected exactly one 'generatedAt' field in '$registryPath', found $($matched.Count)."
    }

    $updated = [regex]::Replace($content, $pattern, ('${prefix}' + $script:FixtureRegistryGeneratedAt + '${suffix}'))
    [System.IO.File]::WriteAllText($registryPath, $updated, [System.Text.UTF8Encoding]::new($false))
}

function Assert-FixtureInheritsBootstrapRef {
    <#
    .SYNOPSIS
        Throws unless the fixture's registry carries the bootstrap ref Build-Registry inherits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $registryPath = Join-Path $Path 'registry.json'
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        throw "Fixture is missing registry.json at '$registryPath'."
    }

    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 100
    $ref = $null
    if ($registry.PSObject.Properties.Name -contains 'bootstrap' -and
        $null -ne $registry.bootstrap -and
        $registry.bootstrap.PSObject.Properties.Name -contains 'ref') {
        $ref = [string]$registry.bootstrap.ref
    }

    if ([string]::IsNullOrWhiteSpace($ref)) {
        throw "Fixture registry.json carries no bootstrap.ref, so rebuilding it before the fixture's first commit would resolve one against an unborn HEAD."
    }
}

function Invoke-FixtureBuildRegistry {
    <#
    .SYNOPSIS
        Runs the fixture's own Build-Registry.ps1 against the fixture.
    .DESCRIPTION
        Invoked in-process, as the registry cases already invoke it: a `.ps1` called with
        `&` dot-sources its helpers into its own scope, so nothing leaks into the calling
        session, and the fixture is built once per module load — a child `pwsh` would add
        its startup to every build for no isolation the script does not already have.
        `Push-Location` is required because Build-Registry resolves the git remote from
        the current directory rather than from -RepoRoot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $scriptPath = Join-Path $Path 'scripts/skalary/Build-Registry.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Fixture is missing Build-Registry.ps1 at '$scriptPath'."
    }

    Push-Location -LiteralPath $Path
    try {
        & $scriptPath -RepoRoot $Path | Out-Null
    }
    finally {
        Pop-Location
    }
}

function Get-SkalaryFixtureTemplate {
    <#
    .SYNOPSIS
        Returns the pristine template repository, building it on first use.
    .DESCRIPTION
        Built once per module load and never handed to a test case — cases receive copies.
        Rebuilt when the cached template is gone or was built from a different project root,
        so a stale cache costs a rebuild rather than serving the wrong fixture.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $projectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot)
    if ($script:FixtureTemplatePath -and
        $script:FixtureTemplateSource -eq $projectRootFull -and
        (Test-Path -LiteralPath $script:FixtureTemplatePath -PathType Container)) {
        return $script:FixtureTemplatePath
    }

    Remove-SkalaryFixtureTemplate

    $path = New-SkalaryFixtureRoot -Prefix 'skalary-fixture-template'
    try {
        New-SkalaryFixtureTemplateRepo -ProjectRoot $projectRootFull -Path $path
    }
    catch {
        # A half-built template is not usable by anyone, so leaving it in TEMP is pure leak.
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    $script:FixtureTemplatePath = $path
    $script:FixtureTemplateSource = $projectRootFull
    return $path
}

function Remove-SkalaryFixtureTemplate {
    <#
    .SYNOPSIS
        Deletes the cached template so the next request rebuilds it.
    #>
    [CmdletBinding()]
    param()

    if ($script:FixtureTemplatePath -and (Test-Path -LiteralPath $script:FixtureTemplatePath)) {
        Remove-Item -LiteralPath $script:FixtureTemplatePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:FixtureTemplatePath = $null
    $script:FixtureTemplateSource = $null
}

function New-SkalaryFixtureRepo {
    <#
    .SYNOPSIS
        Returns a private copy of the minimal synthetic skalary repository.
    .DESCRIPTION
        The template is built once; every call copies it into a fresh random root that does
        not exist yet. The copy is a real byte copy rather than a hardlink or a shared
        checkout, so a case that mutates its fixture cannot reach a neighbour's (RISK-1).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$Prefix = 'skalary-tests'
    )

    $template = Get-SkalaryFixtureTemplate -ProjectRoot $ProjectRoot
    $path = New-SkalaryFixtureRootPath -Prefix $Prefix
    Copy-SkalaryFixtureTree -Source $template -Destination $path
    return (Resolve-Path -LiteralPath $path).Path
}

function Invoke-FixtureGit {
    <#
    .SYNOPSIS
        Runs git with the given argument array and throws on a non-zero exit code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $LASTEXITCODE): $($output -join "`n")"
    }
}

# `Import-Module -Force` removes the previous instance first, so this reclaims a template a
# re-import would otherwise orphan in TEMP.
$ExecutionContext.SessionState.Module.OnRemove = { Remove-SkalaryFixtureTemplate }

Export-ModuleMember -Function New-SkalaryFixtureRepo, New-SkalaryFixtureRoot, Copy-SkalaryFixtureTree,
    Get-SkalaryFixtureTemplate, Remove-SkalaryFixtureTemplate,
    Copy-SkalaryFixturePayload, Get-SkalaryFixturePayload, Get-SkalaryFixturePayloadEntry,
    Get-SkalaryFixturePlugins, Test-SkalaryFixturePluginClosure, Get-SkalaryFixtureTag
