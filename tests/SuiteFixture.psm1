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
    'plugins'
    'scripts/skalary'
)

# Points at HEAD of the fixture commit so Build-Registry resolves a version rather
# than a SHA. Kept semver-shaped because that is what a real release tag looks like.
$script:FixtureTag = 'v1.0.0'

# Every fixture is built from the same payload, so pinning the commit timestamps makes
# every fixture resolve to the same commit SHA. That is load-bearing, not cosmetic:
# Install-Plugin's registry-parity check only runs when the source SHA is an object in
# the target repo, which held for the clone-based fixture and would otherwise be lost.
$script:FixtureCommitDate = '2000-01-01T00:00:00+00:00'

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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    foreach ($relative in $script:FixturePayload) {
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
        `git init` plus the allowlisted payload, committed once and tagged. The
        remote is set to the canonical GitHub URL because `Build-Registry.ps1`
        derives the bootstrap one-liner from `git remote get-url origin` and
        rejects anything that is not a GitHub URL.
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

    Invoke-FixtureGit -Arguments (@('-C', $Path, 'add', '--') + $script:FixturePayload)

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
    Copy-SkalaryFixturePayload, Get-SkalaryFixturePayload, Get-SkalaryFixtureTag
