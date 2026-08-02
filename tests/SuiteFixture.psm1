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

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [System.Guid]::NewGuid().ToString('N'))
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

function New-SkalaryFixtureRepo {
    <#
    .SYNOPSIS
        Builds a minimal synthetic skalary repository and returns its path.
    .DESCRIPTION
        `git init` plus the allowlisted payload, committed once and tagged. The
        remote is set to the canonical GitHub URL because `Build-Registry.ps1`
        derives the bootstrap one-liner from `git remote get-url origin` and
        rejects anything that is not a GitHub URL.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$Path,

        [string]$Prefix = 'skalary-tests'
    )

    if (-not $Path) {
        $Path = New-SkalaryFixtureRoot -Prefix $Prefix
    }
    elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Path)
    }

    try {
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
    }
    catch {
        # A half-built fixture is not usable by anyone, so leaving it in TEMP is pure leak.
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    return $Path
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

Export-ModuleMember -Function New-SkalaryFixtureRepo, New-SkalaryFixtureRoot,
    Copy-SkalaryFixturePayload, Get-SkalaryFixturePayload, Get-SkalaryFixtureTag
