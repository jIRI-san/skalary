#requires -Version 7.0
<#
.SYNOPSIS
    Pre-PR write-scope gate for `/si` self-improvement proposals.
.DESCRIPTION
    Plan b0c0d3 REQ-14 (RISK-6, RISK-12). `/si` proposes edits to the files that govern every
    later agent run and then opens a **same-repo** pull request. Prose confinement is an
    instruction the model may or may not honour; this script is the enforcement.

    It collects every path the proposal touches — committed against the diff base, staged,
    unstaged, and untracked — canonicalizes each one, and confines it to the allowlist:

        plugins/  docs/  .github/skills/  .github/agents/  .github/prompts/

    `.github/workflows/` and `.github/actions/` are denied outright, ahead of the allowlist.
    They are not documents: a same-repo PR branch runs workflows with repository secrets at
    PR-open time, before the draft-PR and human-review backstops apply, so a workflow edit
    that reached a coarse `.github/` allowlist would execute attacker-influenced code with
    full credentials.

    Symlinks are resolved component by component before confinement, so a link inside an
    allowed folder cannot redirect a write outside the repository.

    Exit code 0 = every touched path is in scope. Exit code 1 = refuse; the PR must not be
    opened.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-SiWriteScope.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-SiWriteScope.ps1 -RepoRoot ../worktree -BaseRef main -PassThru
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,

    # Diff base for the committed half of the proposal. `main` is the documented default;
    # the ref is resolved against origin first so a stale local branch cannot narrow scope.
    [string]$BaseRef = 'main',

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ordered deny-then-allow. Deny wins: an entry that matches both is refused, so widening the
# allowlist can never silently re-expose an execution-carrying path.
$script:DeniedPrefixes = @('.github/workflows/', '.github/actions/')
$script:AllowedPrefixes = @('plugins/', 'docs/', '.github/skills/', '.github/agents/', '.github/prompts/')

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$NullSeparated
    )

    # git emits path bytes as UTF-8; PowerShell decodes native stdout with
    # [Console]::OutputEncoding, an OEM codepage on a default Windows console. Mojibake here
    # would silently bypass the allowlist and symlink checks this guard exists to enforce.
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $output = & git -C $WorkingDirectory @Arguments 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    if ($exitCode -ne 0) {
        if ($AllowFailure) { return , @() }
        throw "git $($Arguments -join ' ') failed with exit code $exitCode in '$WorkingDirectory'."
    }

    if ($NullSeparated) {
        # -z on every file-list call: the newline form C-quotes non-ASCII and quoted paths, and
        # a quoted path resolves to nothing — which here would mean a touched file skipping the
        # gate entirely.
        $text = ($output -join "`n")
        $split = $text.Split([char]0, [char]10)
        return , @($split | Where-Object { -not [string]::IsNullOrEmpty($_) })
    }

    return , @($output)
}

function Resolve-ScopeRepoRoot {
    param([string]$StartPath)

    $start = if ([string]::IsNullOrWhiteSpace($StartPath)) { (Get-Location).Path } else { $StartPath }
    if (-not (Test-Path -LiteralPath $start -PathType Container)) {
        throw "Repository path not found: $start"
    }

    $top = Invoke-Git -WorkingDirectory $start -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if (-not $top -or [string]::IsNullOrWhiteSpace([string]$top[0])) {
        throw "Not inside a git work tree: $start"
    }

    # The root itself can sit under a symlink (a worktree in /tmp, for instance). Confinement
    # compares real paths on both sides or every path looks like an escape.
    $rootItem = Get-Item -LiteralPath ([string]$top[0]) -Force
    $rootTarget = $rootItem.ResolveLinkTarget($true)
    $resolved = if ($null -ne $rootTarget) { $rootTarget.FullName } else { $rootItem.FullName }
    return [System.IO.Path]::GetFullPath($resolved)
}

function Resolve-BaseRef {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Ref
    )

    foreach ($candidate in @("refs/remotes/origin/$Ref", "refs/heads/$Ref", $Ref)) {
        $resolved = Invoke-Git -WorkingDirectory $Root -Arguments @('rev-parse', '--verify', '--quiet', $candidate) -AllowFailure
        if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved[0])) {
            return ($candidate -replace '^refs/remotes/', '' -replace '^refs/heads/', '')
        }
    }
    return $null
}

function Get-TouchedPath {
    <#
        Every half of the proposal, because each one alone is a hole: committed work is invisible
        to a working-tree scan, and a brand-new file is invisible to a diff.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ResolvedBase
    )

    $paths = [System.Collections.Generic.List[string]]::new()

    if ($ResolvedBase) {
        # Three-dot: the changes this branch introduced since it diverged, not everything that
        # happened on the base since. --no-renames because rename detection reports only the
        # destination, which would let `git mv .github/workflows/ci.yml docs/notes.md` delete a
        # workflow without the denied source path ever reaching the gate.
        foreach ($p in (Invoke-Git -WorkingDirectory $Root -Arguments @('diff', "$ResolvedBase...HEAD", '--name-only', '--no-renames', '-z') -NullSeparated)) { $paths.Add([string]$p) }
    }

    $hasHead = Invoke-Git -WorkingDirectory $Root -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD') -AllowFailure
    if ($hasHead -and -not [string]::IsNullOrWhiteSpace([string]$hasHead[0])) {
        # diff HEAD covers staged and unstaged together; a staged-only diff would miss an edit
        # made after staging.
        foreach ($p in (Invoke-Git -WorkingDirectory $Root -Arguments @('diff', 'HEAD', '--name-only', '--no-renames', '-z') -NullSeparated)) { $paths.Add([string]$p) }
    }
    else {
        foreach ($p in (Invoke-Git -WorkingDirectory $Root -Arguments @('diff', '--cached', '--name-only', '--no-renames', '-z') -NullSeparated)) { $paths.Add([string]$p) }
    }

    foreach ($p in (Invoke-Git -WorkingDirectory $Root -Arguments @('ls-files', '--others', '--exclude-standard', '-z') -NullSeparated)) { $paths.Add([string]$p) }

    return $paths
}

function Resolve-RealPath {
    <#
        Canonicalize a repo-relative path component by component, following any symlink that
        exists along the way. Resolving only the leaf would miss the common escape: an allowed
        directory name that is itself a link somewhere else.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $current = $Root
    foreach ($segment in ($RelativePath -split '/')) {
        if ([string]::IsNullOrEmpty($segment)) { continue }
        $next = Join-Path $current $segment
        if (Test-Path -LiteralPath $next) {
            $item = Get-Item -LiteralPath $next -Force
            if ($item.LinkTarget) {
                $target = $item.ResolveLinkTarget($true)
                # A broken link resolves to nothing; keep the literal path so confinement still
                # judges it rather than silently passing.
                if ($null -ne $target) { $next = $target.FullName }
            }
        }
        $current = [System.IO.Path]::GetFullPath($next)
    }
    return $current
}

function Test-PathInRoot {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FullPath
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $Root.TrimEnd($separator) + $separator
    # Case-sensitive comparison is wrong on Windows and NTFS-cased checkouts; ordinal-ignore-case
    # is the conservative choice for a *containment* test.
    return $FullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PrefixMatch {
    <#
        A prefix carries a trailing slash so `docsomething/` cannot match `docs/`. The directory
        entry *itself* has no trailing slash, though — git emits a bare `.github/workflows` when
        that path is a symlink or a gitlink — so the bare form is matched by equality too.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Prefix
    )

    $bare = $Prefix.TrimEnd('/')
    return $Path.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    $Path.Equals($bare, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ScopeEntry {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $normalized = $RelativePath.Replace('\', '/').Trim()

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return [pscustomobject]@{ Path = $RelativePath; Allowed = $false; Reason = 'empty path' }
    }
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('/')) {
        return [pscustomobject]@{ Path = $normalized; Allowed = $false; Reason = 'absolute path outside the proposal' }
    }
    if (($normalized -split '/') -contains '..') {
        return [pscustomobject]@{ Path = $normalized; Allowed = $false; Reason = 'path traversal segment' }
    }

    # The literal path is judged first and on its own. Symlink resolution below can only ever
    # deny further: if the destination decided the verdict, a link from any out-of-scope path
    # into `docs/` would launder that path into the allowlist.
    foreach ($denied in $script:DeniedPrefixes) {
        if (Test-PrefixMatch -Path $normalized -Prefix $denied) {
            return [pscustomobject]@{
                Path = $normalized
                Allowed = $false
                Reason = "denied execution-carrying path ('$denied' runs with repository secrets on a same-repo PR)"
            }
        }
    }

    $literalAllowed = $false
    foreach ($allowed in $script:AllowedPrefixes) {
        if (Test-PrefixMatch -Path $normalized -Prefix $allowed) { $literalAllowed = $true; break }
    }
    if (-not $literalAllowed) {
        return [pscustomobject]@{ Path = $normalized; Allowed = $false; Reason = 'outside the /si write allowlist' }
    }

    $real = Resolve-RealPath -Root $Root -RelativePath $normalized
    if (-not (Test-PathInRoot -Root $Root -FullPath $real)) {
        return [pscustomobject]@{ Path = $normalized; Allowed = $false; Reason = "resolves outside the repository ('$real')" }
    }

    # An allowlisted *name* is not an allowlisted *destination*: a link inside `docs/` that lands
    # in a denied or out-of-scope tree writes there, whatever it is called.
    $resolvedRelative = [System.IO.Path]::GetRelativePath($Root, $real).Replace('\', '/')
    foreach ($denied in $script:DeniedPrefixes) {
        if (Test-PrefixMatch -Path $resolvedRelative -Prefix $denied) {
            return [pscustomobject]@{
                Path = $normalized
                Allowed = $false
                Reason = "resolves into a denied execution-carrying path ('$resolvedRelative')"
            }
        }
    }

    foreach ($allowed in $script:AllowedPrefixes) {
        if (Test-PrefixMatch -Path $resolvedRelative -Prefix $allowed) {
            return [pscustomobject]@{ Path = $normalized; Allowed = $true; Reason = "in scope ('$allowed')" }
        }
    }

    return [pscustomobject]@{ Path = $normalized; Allowed = $false; Reason = "resolves outside the /si write allowlist ('$resolvedRelative')" }
}

try {
    $root = Resolve-ScopeRepoRoot -StartPath $RepoRoot
}
catch {
    Write-Host "Test-SiWriteScope failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$resolvedBase = Resolve-BaseRef -Root $root -Ref $BaseRef
if (-not $resolvedBase) {
    # No base ref means the committed half of the proposal cannot be enumerated. Refusing is the
    # only safe answer: passing here would approve an unexamined set of commits.
    Write-Host "Test-SiWriteScope failed: cannot resolve diff base '$BaseRef' in '$root'." -ForegroundColor Red
    exit 1
}

$touched = Get-TouchedPath -Root $root -ResolvedBase $resolvedBase

$unique = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($path in $touched) {
    if (-not [string]::IsNullOrWhiteSpace($path)) { [void]$unique.Add($path.Replace('\', '/')) }
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($path in $unique) {
    $results.Add((Test-ScopeEntry -Root $root -RelativePath $path))
}

$violations = @($results | Where-Object { -not $_.Allowed })

if ($violations.Count -gt 0) {
    Write-Host "Test-SiWriteScope REFUSED: $($violations.Count) path(s) outside the /si write scope (base $resolvedBase...HEAD)." -ForegroundColor Red
    foreach ($violation in $violations) {
        Write-Host "  DENY $($violation.Path) - $($violation.Reason)" -ForegroundColor Red
    }
    if ($PassThru) { $results }
    exit 1
}

Write-Host "Test-SiWriteScope passed: $($results.Count) touched path(s) in scope (base $resolvedBase...HEAD)." -ForegroundColor Green
if ($PassThru) { $results }
exit 0
