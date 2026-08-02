#requires -Version 7.0
<#
.SYNOPSIS
    Enumerates the repository files the validation gate parses.
.DESCRIPTION
    REQ-8: `validate.ps1` has to parse the same file set on Windows and Linux.

    `Get-ChildItem -Recurse` without `-Force` skips dot-prefixed entries on Unix, where
    pwsh reports them as hidden, and keeps them on Windows, where the name carries no
    such meaning. `.github` is the largest payload root in this repo, so the gate was
    parsing it on one platform and silently skipping it on the other — the two legs
    reported a pass over different file sets.

    Adding `-Force` fixes that asymmetry and creates a worse one: it reaches `.git`,
    `node_modules` and worktrees, whose contents are neither ours nor stable (RISK-5).
    Enumeration is therefore an allowlist of payload roots rather than a denylist of
    names — a root nobody listed is not scanned, instead of a name nobody thought to
    exclude being scanned. Paths are canonicalised and confirmed to stay under the repo
    root, and reparse points are refused rather than followed, so a symlink planted
    inside a payload root cannot readmit an excluded tree.
#>

Set-StrictMode -Version Latest

# Directories whose contents this repo owns. Everything parsed by the gate lives under
# one of these; anything else is out of scope by construction rather than by exclusion.
$script:PayloadDirectory = @(
    '.github'
    '.vscode'
    'docs'
    'plugins'
    'schemas'
    'scripts'
    'tests'
    'tools'
)

# Pruned wherever they appear inside a payload root. Not the mechanism that keeps `.git`
# out — the allowlist does that — but generated, vendored and runtime trees do nest, and a
# `node_modules` under `docs/` is no more ours than one at the root. `.skalary` is the
# plugin installer's runtime state (receipts and install staging, gitignored and retained
# after a successful install): parsing it would make the file count a function of local
# install history rather than of the checkout, which is the divergence REQ-8 forbids, and
# would run this repo's gate over third-party payload it does not own.
$script:PrunedDirectoryName = @(
    '.git'
    '.skalary'
    '.worktrees'
    'bin'
    'node_modules'
    'obj'
)

function Get-SkalaryPayloadRoot {
    <#
    .SYNOPSIS
        Returns the allowlisted payload directory names, in ordinal order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]]$script:PayloadDirectory
}

function Get-SkalaryPrunedDirectoryName {
    <#
    .SYNOPSIS
        Returns the directory names pruned inside every payload root.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]]$script:PrunedDirectoryName
}

function Test-ReparsePoint {
    <#
    .SYNOPSIS
        True when the path carries the reparse-point attribute (symlink or junction).
    .NOTES
        Throws when the path cannot be interrogated. Swallowing that would drop a real
        file out of the parsed set with no error and no count anomaly — a fail-open in
        the one gate whose job is to prove every payload file parses. Callers that walk
        directories decide separately not to descend into what they cannot read.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $attributes = [System.IO.File]::GetAttributes($Path)
    return (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-DirectoryWalkable {
    <#
    .SYNOPSIS
        True when the directory is a real directory this walk may descend into.
    .NOTES
        A directory that cannot be interrogated is not one to walk into, and neither is a
        reparse point: `Path.GetFullPath` normalises `..` and separators but does not
        resolve links, so the containment check alone cannot see through one (RISK-5).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        return (-not (Test-ReparsePoint -Path $Path))
    }
    catch {
        return $false
    }
}

function Get-SkalaryPayloadFile {
    <#
    .SYNOPSIS
        Returns the canonical full paths of every allowlisted file with a matching extension.
    .PARAMETER Extension
        Extensions to return, leading dot included. Matched ordinally after lowercasing
        with the invariant culture, so a `tr-TR` host does not fold `I` away from `.PS1`.
    .PARAMETER Root
        Payload roots to walk. Defaults to the repo-wide allowlist; tests pass a subset.
    .PARAMETER RequireRoot
        Fail when an allowlisted root is missing or unreadable instead of skipping it, so
        a moved or renamed root is a loud error rather than a silent loss of coverage.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string[]]$Extension,

        [string[]]$Root = $script:PayloadDirectory,

        [switch]$RequireRoot
    )

    $canonicalRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $canonicalRepoRoot -PathType Container)) {
        throw "Repository root not found: $RepoRoot"
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $repoRootWithSeparator = $canonicalRepoRoot.TrimEnd($separator) + $separator

    $wanted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Extension) {
        [void]$wanted.Add($item.ToLowerInvariant())
    }

    $pruned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $script:PrunedDirectoryName) {
        [void]$pruned.Add($name)
    }

    $files = [System.Collections.Generic.List[string]]::new()

    function Add-MatchingFile {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        # Extension first: a file the gate would never parse is not worth interrogating,
        # and an unreadable one of those must not be able to fail the run.
        if (-not $wanted.Contains([System.IO.Path]::GetExtension($Path).ToLowerInvariant())) {
            return
        }
        if (Test-ReparsePoint -Path $Path) {
            return
        }

        $canonical = [System.IO.Path]::GetFullPath($Path)
        if (-not $canonical.StartsWith($repoRootWithSeparator, [System.StringComparison]::Ordinal)) {
            # Canonicalisation resolved outside the repo, so the entry is not ours to parse.
            return
        }
        $files.Add($canonical)
    }

    # Repo-root files first, non-recursively.
    foreach ($path in [System.IO.Directory]::EnumerateFiles($canonicalRepoRoot)) {
        Add-MatchingFile -Path $path
    }

    foreach ($rootName in $Root) {
        $rootPath = Join-Path $canonicalRepoRoot $rootName
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
            if ($RequireRoot) {
                # An allowlist trades "scans too much" for "scans nothing, quietly". A root
                # that moved or was renamed would otherwise drop out of the gate in silence.
                throw "Allowlisted payload root '$rootName' not found under '$canonicalRepoRoot'."
            }
            continue
        }
        if (-not (Test-DirectoryWalkable -Path $rootPath)) {
            if ($RequireRoot) {
                throw "Allowlisted payload root '$rootName' is a reparse point or cannot be read."
            }
            continue
        }

        # An explicit stack rather than -Recurse: pruning a subtree is the point, and
        # Get-ChildItem can only filter what it has already walked into.
        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push([System.IO.Path]::GetFullPath($rootPath))
        while ($pending.Count -gt 0) {
            $current = $pending.Pop()

            foreach ($path in [System.IO.Directory]::EnumerateFiles($current)) {
                Add-MatchingFile -Path $path
            }

            foreach ($path in [System.IO.Directory]::EnumerateDirectories($current)) {
                $name = [System.IO.Path]::GetFileName($path)
                if ($pruned.Contains($name)) {
                    continue
                }
                if (-not (Test-DirectoryWalkable -Path $path)) {
                    continue
                }
                $pending.Push([System.IO.Path]::GetFullPath($path))
            }
        }
    }

    # Ordinal so the parse order — and therefore the order errors are reported in — is the
    # same on both platforms, which is the property this module exists to provide.
    $ordered = [string[]]@($files)
    [System.Array]::Sort($ordered, [System.StringComparer]::Ordinal)
    return $ordered
}

Export-ModuleMember -Function Get-SkalaryPayloadFile, Get-SkalaryPayloadRoot, Get-SkalaryPrunedDirectoryName
